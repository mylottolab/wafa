-- =====================================================================
-- 와파 관리 화면 (2026-11-22) · 부름 Supabase(azredlrnvsssfjytaotb) SQL Editor 에서 Run
--   burum.kr/wafa_admin.html (위브앱 통합 관리 → 📶 와파) 이 읽는 함수 하나. 관리자만(is_admin).
--   새 표 없음 · 읽기만 합니다. 다시 돌려도 안전합니다. 맨 아래 'wafa admin ok'
-- =====================================================================
create or replace function public.admin_wafa_report(p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Seoul')::date - 29);
        t date := coalesce(p_to, (now() at time zone 'Asia/Seoul')::date);
        v_ym text := to_char(now() at time zone 'Asia/Seoul', 'YYYY-MM');
        r jsonb;
begin
  if not coalesce(public.is_admin(), false) then raise exception 'not_admin'; end if;
  with acc as (
    select a.user_id, a.created_at, a.last_seen, a.main_line, u.email,
           (select n.number from wafa_numbers n where n.owner = a.user_id order by n.is_main desc, n.acquired_at limit 1) as num,
           (select count(*) from wafa_numbers n where n.owner = a.user_id) as nums,
           s.product, s.status, s.expires_at, s.store, s.auto_renew,
           coalesce(g.voice_sec, 0) as vs, coalesce(g.video_sec, 0) as ds
      from wafa_accounts a
      left join auth.users u on u.id = a.user_id
      left join wafa_subs s on s.user_id = a.user_id
      left join wafa_usage g on g.user_id = a.user_id and g.ym = v_ym
  ), pays as (
    select p.*, u.email from wafa_pay_log p left join auth.users u on u.id = p.user_id
     where (p.at at time zone 'Asia/Seoul')::date between f and t
  )
  select jsonb_build_object(
    'from', f, 'to', t, 'ym', v_ym,
    'totals', jsonb_build_object(
       'accounts', (select count(*) from acc),
       'new', (select count(*) from acc where (created_at at time zone 'Asia/Seoul')::date between f and t),
       'today', (select count(*) from acc where (created_at at time zone 'Asia/Seoul')::date = (now() at time zone 'Asia/Seoul')::date),
       'subs', (select count(*) from acc where status in ('active','grace') and expires_at > now()),
       'renew_off', (select count(*) from acc where status in ('active','grace') and expires_at > now() and not auto_renew),
       'numbers', (select count(*) from wafa_numbers),
       'pays', (select count(*) from pays), 'krw', (select coalesce(sum(amount), 0) from pays),
       'voice_min', (select (coalesce(sum(vs), 0) / 60)::bigint from acc), 'video_min', (select (coalesce(sum(ds), 0) / 60)::bigint from acc),
       'seen7', (select count(*) from acc where last_seen > now() - interval '7 days')),
    'by_product', (select coalesce(jsonb_object_agg(product, n), '{}') from (select product, count(*) n from acc where status in ('active','grace') and expires_at > now() group by product) x),
    'by_store', (select coalesce(jsonb_object_agg(store, n), '{}') from (select store, count(*) n from acc where status in ('active','grace') and expires_at > now() group by store) x),
    'by_kind', (select coalesce(jsonb_object_agg(kind, n), '{}') from (select kind, count(*) n from wafa_numbers group by kind) x),
    'by_sku', (select coalesce(jsonb_agg(jsonb_build_object('sku', sku, 'n', n, 'krw', krw) order by n desc), '[]') from (select sku, count(*) n, coalesce(sum(amount), 0) krw from pays group by sku) x),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'new', (select count(*) from acc where (created_at at time zone 'Asia/Seoul')::date = d),
                                                           'pays', (select count(*) from pays where (at at time zone 'Asia/Seoul')::date = d),
                                                           'krw', (select coalesce(sum(amount), 0) from pays where (at at time zone 'Asia/Seoul')::date = d)) order by d desc), '[]')
                from generate_series(f, t, interval '1 day') d),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('login', email, 'at', created_at, 'seen', last_seen, 'main', main_line, 'num', num, 'nums', nums,
                     'product', product, 'status', status, 'until', expires_at, 'store', store, 'renew', auto_renew, 'vmin', vs / 60, 'dmin', ds / 60) order by created_at desc), '[]')
                from (select * from acc order by created_at desc limit 500) z),
    'pay_list', (select coalesce(jsonb_agg(jsonb_build_object('at', at, 'login', email, 'sku', sku, 'amount', amount) order by at desc), '[]')
                 from (select * from pays order by at desc limit 300) z)
  ) into r;
  return r;
end $$;
revoke all on function public.admin_wafa_report(date, date) from public, anon;
grant execute on function public.admin_wafa_report(date, date) to authenticated;
select 'wafa admin ok' as result;
