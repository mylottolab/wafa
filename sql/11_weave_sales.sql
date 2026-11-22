-- =====================================================================
-- 💰 매출 센터 — 부름 서버 (2026-11-22) · 부름 Supabase SQL Editor 에서 Run. 다시 돌려도 안전합니다.
--   맨 아래 'weave sales burum ok'
--
--   ① 와파 구독 결제 기록 — 지금까지는 구독의 "지금 상태"만 있고 결제 내역이 남지 않았습니다.
--      wafa_sub_apply 가 기간이 새로 늘어날 때마다(첫 결제 · 자동 갱신) wafa_pay_log 에 한 줄 남기고,
--      환불되면 마이너스 한 줄을 남깁니다. 구독이 하는 일은 예전과 똑같습니다.
--      이미 구독 중인 분은 "지금 기간의 결제 1번"을 그 기간 시작일로 한 번만 채워 넣습니다(추정).
--   ② weave_sales(시작일, 끝일, 달러환율) — 관리자만(stats_is_admin)
--      날짜 · 앱 · 상품 · 결제수단별 건수 · 총매출(원) · 환불.
--      앱: payments 의 상품 번호 baronu_ → 바로너 · nureum_(또는 purpose nureum) → 누름 · 나머지 → 부름
--          wafa_pay_log → 와파(구독 · 보충권 · 번호)
-- =====================================================================

-- ① 와파 구독 결제 기록 -------------------------------------------------
alter table public.wafa_pay_log add column if not exists store text;

create or replace function public._wafa_sub_price(p_product text) returns int
language sql immutable as $$
  select case p_product when 'wafa_1m' then 1500 when 'wafa_3m' then 3300 when 'wafa_6m' then 5500 when 'wafa_12m' then 9900 end
$$;
create or replace function public._wafa_sub_months(p_product text) returns int
language sql immutable as $$
  select case p_product when 'wafa_1m' then 1 when 'wafa_3m' then 3 when 'wafa_6m' then 6 when 'wafa_12m' then 12 end
$$;
create or replace function public._wafa_sub_tx(p_store text, p_tx text, p_user uuid, p_expires timestamptz) returns text
language sql immutable as $$
  select 'sub:' || coalesce(p_store, '') || ':' || coalesce(nullif(p_tx, ''), p_user::text) || '@' || to_char(p_expires at time zone 'UTC', 'YYYYMMDDHH24')
$$;

create or replace function public.wafa_sub_apply(p_user uuid, p_product text, p_status text, p_expires timestamptz,
                                                 p_auto boolean, p_store text, p_tx text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare o wafa_subs; v_price int := _wafa_sub_price(p_product);
begin
  select * into o from wafa_subs where user_id = p_user;

  insert into wafa_subs(user_id, product, status, auto_renew, expires_at, store, original_tx, updated_at)
  values (p_user, p_product, p_status, p_auto, p_expires, p_store, p_tx, now())
  on conflict (user_id) do update set product = excluded.product, status = excluded.status, auto_renew = excluded.auto_renew,
     expires_at = excluded.expires_at, store = excluded.store, original_tx = coalesce(excluded.original_tx, wafa_subs.original_tx), updated_at = now();
  insert into wafa_accounts(user_id) values (p_user) on conflict do nothing;

  -- 💰 2026-11-22 결제 기록: 기간이 새로 늘어났으면(첫 결제 · 갱신) 한 줄 · 환불이면 마이너스 한 줄
  begin
    if v_price is not null and p_store in ('google', 'apple') then
      if p_status = 'active' and (o.user_id is null or p_expires > o.expires_at + interval '1 day') then
        insert into wafa_pay_log(tx, user_id, sku, amount, store, at)
        values (_wafa_sub_tx(p_store, p_tx, p_user, p_expires), p_user, p_product, v_price, p_store, now())
        on conflict (tx) do nothing;
      elsif p_status = 'refunded' and coalesce(o.status, '') <> 'refunded' then
        insert into wafa_pay_log(tx, user_id, sku, amount, store, at)
        values ('refund:' || _wafa_sub_tx(p_store, p_tx, p_user, coalesce(o.expires_at, p_expires)), p_user, p_product, -v_price, p_store, now())
        on conflict (tx) do nothing;
      end if;
    end if;
  exception when others then null;   -- 기록이 실패해도 구독은 그대로
  end;

  return jsonb_build_object('ok', true, 'active', _wafa_active(p_user));
end $$;

-- 이미 구독 중인 분: 지금 기간의 결제 1번(기간 시작일로 · 추정). 같은 열쇠라 다시 돌려도 한 번만.
insert into wafa_pay_log(tx, user_id, sku, amount, store, at)
select _wafa_sub_tx(s.store, s.original_tx, s.user_id, s.expires_at), s.user_id, s.product, _wafa_sub_price(s.product), s.store,
       least(now(), s.expires_at - make_interval(months => _wafa_sub_months(s.product)))
  from wafa_subs s
 where s.store in ('google', 'apple') and s.status <> 'refunded' and _wafa_sub_price(s.product) is not null
on conflict (tx) do nothing;

-- ② 매출 집계 ---------------------------------------------------------------
create or replace function public.weave_sales(p_from date, p_to date, p_usd_krw numeric default 1400)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_to   date := coalesce(p_to, (now() at time zone 'Asia/Seoul')::date);
  v_from date := coalesce(p_from, v_to - 29);
  v_rows jsonb;
begin
  if not coalesce(stats_is_admin(), false) then raise exception 'not_admin'; end if;
  if v_from > v_to then raise exception 'bad_range'; end if;
  if v_to - v_from > 800 then v_from := v_to - 800; end if;

  with p as (
    select (coalesce(x.completed_at, x.created_at) at time zone 'Asia/Seoul')::date as day,
           x.status::text as st,
           lower(coalesce(x.google_product_id, '')) as pid,
           lower(coalesce(x.method::text, '')) as m,
           upper(trim(coalesce(x.currency_code::text, 'KRW'))) as cur,
           coalesce(x.amount_minor_units, 0)::numeric as amt,
           coalesce(x.purpose, '') as purpose,
           x.plan_months as months
      from payments x
     where x.status::text in ('completed', 'refunded')
       and (coalesce(x.completed_at, x.created_at) at time zone 'Asia/Seoul')::date between v_from and v_to
  ), q as (
    select day, st,
           case when pid like 'baronu%' then 'baronu'
                when pid like 'nureum%' or purpose = 'nureum' then 'nureum'
                else 'burum' end as app,
           case when m like '%google%' then 'google'
                when m like '%app_store%' or m like '%apple%' then 'apple'
                when m like '%bank%' then 'bank'
                else 'pg' end as channel,
           coalesce(nullif(regexp_replace(pid, '_nr$', ''), ''),
                    case purpose when 'plan' then '이용권 ' || coalesce(months::text, '?') || '개월'
                                 when 'storage' then '추가 저장공간' else nullif(purpose, '') end, '기타') as product,
           round(case when cur = 'USD' then amt / 100.0 * coalesce(p_usd_krw, 1400) else amt end) as krw,
           (st = 'refunded') as is_ref
      from p
    union all
    -- 와파 (구독 · 보충권 · 번호). 금액이 비어 있는 옛 번호 기록은 상품 값으로
    select (w.at at time zone 'Asia/Seoul')::date, case when coalesce(w.amount, 0) < 0 then 'refunded' else 'completed' end,
           'wafa',
           case when coalesce(w.store, '') = 'apple' or w.tx like 'apple:%' then 'apple' else 'google' end,
           case when w.sku like 'number:%' then 'wafa_number_' || split_part(w.sku, ':', 2) else w.sku end,
           abs(coalesce(w.amount, case split_part(w.sku, ':', 2) when '5' then 110000 when '4' then 55000 when '3' then 11000
                                                                   when 'extra' then 3300 else 0 end)),
           coalesce(w.amount, 0) < 0
      from wafa_pay_log w
     where (w.at at time zone 'Asia/Seoul')::date between v_from and v_to
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'day', day, 'app', app, 'product', product, 'channel', channel,
           'orders', n, 'gross', g, 'refunds', rn, 'refund', r) order by day, app, product), '[]'::jsonb)
    into v_rows
    from (select day, app, product, channel,
                 count(*) filter (where not is_ref or st = 'refunded' and app <> 'wafa') n,
                 coalesce(sum(krw) filter (where not is_ref or app <> 'wafa'), 0) g,
                 count(*) filter (where is_ref) rn,
                 coalesce(sum(krw) filter (where is_ref), 0) r
            from q group by 1, 2, 3, 4) t;

  return jsonb_build_object('server', 'burum', 'from', v_from, 'to', v_to, 'rows', v_rows);
end $$;
revoke all on function public.weave_sales(date, date, numeric) from public, anon;
grant execute on function public.weave_sales(date, date, numeric) to authenticated;

select 'weave sales burum ok' as result;
