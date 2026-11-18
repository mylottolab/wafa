-- WAFA 결제 준비 (2026-11-18) — 부름 프로젝트에 01 다음으로 Run. 다시 돌려도 안전합니다.
--   · 좋은 번호 · 번호 하나 더 를 사기 전에 고른 번호를 15분 잡아 둠(결제창이 떠 있는 동안 남이 못 가져가게)
--   · 결제 확인 함수(wafa-verify)가 영수증이 진짜일 때 그 번호를 붙여 줌
--   · 첫 구독이 시작되면 일반 번호 하나를 무료로 붙여 줌

-- 1) 결제 전 잡아 두기 (손님이 부름)
--    p_kind: '5' · '4' · '3' (좋은 번호) | 'extra' (일반 번호 하나 더)
create or replace function public.wafa_checkout_hold(p_number text, p_kind text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me uuid := auth.uid(); g text := wafa_grade(p_number); sku text; price int;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if g is null then return jsonb_build_object('ok', false, 'error', 'bad_number'); end if;
  if g = 'S' or wafa_is_company(p_number) then return jsonb_build_object('ok', false, 'error', 'company'); end if;
  if p_kind in ('5','4','3') then
    if g <> p_kind then return jsonb_build_object('ok', false, 'error', 'grade_mismatch', 'grade', g); end if;
    sku := 'wafa_number_' || p_kind; price := wafa_price(g);
  elsif p_kind = 'extra' then
    if g <> 'N' then return jsonb_build_object('ok', false, 'error', 'premium', 'grade', g); end if;
    if not exists (select 1 from wafa_numbers where owner = me) then return jsonb_build_object('ok', false, 'error', 'use_free'); end if;
    sku := 'wafa_number_extra'; price := 3300;
  else
    return jsonb_build_object('ok', false, 'error', 'bad_kind');
  end if;
  perform pg_advisory_xact_lock(hashtext('wafa:' || p_number));
  delete from wafa_holds where expires_at <= now();
  delete from wafa_holds where holder = me and kind = 'checkout';          -- 한 사람은 결제 중 번호 하나만
  if _wafa_busy(p_number) then return jsonb_build_object('ok', false, 'error', 'taken'); end if;
  insert into wafa_holds(number, holder, code, kind, expires_at)
  values (p_number, me, 'CO-' || upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10)), 'checkout', now() + interval '15 minutes');
  return jsonb_build_object('ok', true, 'sku', sku, 'price', price, 'number', p_number, 'shown', wafa_shown(p_number));
end $$;

-- 2) 결제 확인 뒤 번호 붙이기 (서버 전용 — wafa-verify 가 부름)
--    잡아 둔 번호가 있으면 붙이고, 없거나 시간이 지났으면 "번호 고르기권"으로 남김 → 돈 받고 번호 못 드리는 일 없음
create table if not exists public.wafa_number_credits (
  id         uuid primary key default gen_random_uuid(),
  owner      uuid not null,
  kind       text not null check (kind in ('5','4','3','extra')),
  tx         text not null unique,
  used_number text,
  created_at timestamptz not null default now(),
  used_at    timestamptz
);
alter table public.wafa_number_credits enable row level security;
drop policy if exists wafa_credit_me on public.wafa_number_credits;
create policy wafa_credit_me on public.wafa_number_credits for select to authenticated using (owner = auth.uid());
grant select on public.wafa_number_credits to authenticated;
grant all on public.wafa_number_credits to service_role;

create or replace function public.wafa_number_paid(p_user uuid, p_kind text, p_tx text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare h record; r jsonb; c record;
begin
  select * into c from wafa_number_credits where tx = p_tx;
  if found then return jsonb_build_object('ok', true, 'dup', true, 'number', c.used_number); end if;
  select * into h from wafa_holds where holder = p_user and kind = 'checkout' and expires_at > now()
    and (case when p_kind = 'extra' then wafa_grade(number) = 'N' else wafa_grade(number) = p_kind end)
    order by expires_at desc limit 1;
  insert into wafa_number_credits(owner, kind, tx) values (p_user, p_kind, p_tx);
  if h.number is not null then
    r := wafa_grant_number(p_user, h.number, case when p_kind = 'extra' then 'extra' else 'bought' end);
    if coalesce((r->>'ok')::boolean, false) then
      update wafa_number_credits set used_number = h.number, used_at = now() where tx = p_tx;
      return jsonb_build_object('ok', true, 'number', h.number, 'shown', wafa_shown(h.number));
    end if;
  end if;
  return jsonb_build_object('ok', true, 'credit', true);       -- 나중에 wafa_use_credit 으로 고름
end $$;

-- 3) 고르기권으로 번호 고르기 (손님이 부름)
create or replace function public.wafa_use_credit(p_credit uuid, p_number text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me uuid := auth.uid(); c record; g text := wafa_grade(p_number); r jsonb;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  select * into c from wafa_number_credits where id = p_credit and owner = me and used_at is null for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_credit'); end if;
  if (c.kind = 'extra' and g is distinct from 'N') or (c.kind <> 'extra' and g is distinct from c.kind) then
    return jsonb_build_object('ok', false, 'error', 'grade_mismatch', 'grade', g); end if;
  perform pg_advisory_xact_lock(hashtext('wafa:' || p_number));
  if _wafa_busy(p_number) and not exists (select 1 from wafa_holds where number = p_number and holder = me and expires_at > now()) then
    return jsonb_build_object('ok', false, 'error', 'taken'); end if;
  r := wafa_grant_number(me, p_number, case when c.kind = 'extra' then 'extra' else 'bought' end);
  if coalesce((r->>'ok')::boolean, false) then
    update wafa_number_credits set used_number = p_number, used_at = now() where id = c.id;
  end if;
  return r;
end $$;

-- 4) 첫 구독 때 일반 번호 무료로 (손님이 부름 — 구독 중일 때만, 한 사람 한 번)
create or replace function public.wafa_claim_free(p_number text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if not _wafa_active(me) then return jsonb_build_object('ok', false, 'error', 'need_plan'); end if;
  perform pg_advisory_xact_lock(hashtext('wafa:' || p_number));
  if _wafa_busy(p_number) and not exists (select 1 from wafa_holds where number = p_number and holder = me and expires_at > now()) then
    return jsonb_build_object('ok', false, 'error', 'taken'); end if;
  return wafa_grant_number(me, p_number, 'free');
end $$;

-- 5) 가족 초대 코드로 가입 · 결제한 사람이 예약 번호 받기 (손님이 부름 — 구독 중일 때)
create or replace function public.wafa_claim_family(p_code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me uuid := auth.uid(); h record; g text;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if not _wafa_active(me) then return jsonb_build_object('ok', false, 'error', 'need_plan'); end if;
  select * into h from wafa_holds where code = upper(trim(p_code)) and kind = 'family' and expires_at > now();
  if not found then return jsonb_build_object('ok', false, 'error', 'no_code'); end if;
  g := wafa_grade(h.number);
  if g <> 'N' then    -- 좋은 번호면 그 등급 값을 내야 함 → 결제 전 잡아 두기로 넘김
    update wafa_holds set holder = me, kind = 'checkout', expires_at = now() + interval '15 minutes' where number = h.number;
    return jsonb_build_object('ok', true, 'pay', true, 'sku', 'wafa_number_' || g, 'price', wafa_price(g),
                              'number', h.number, 'shown', wafa_shown(h.number));
  end if;
  return wafa_grant_number(me, h.number, 'free', null, h.code);
end $$;

-- 6) 스토어 영수증 ↔ 사람 (구독 갱신 알림이 올 때 누구 것인지 찾기)
create table if not exists public.wafa_sub_tokens (
  token    text primary key,          -- 구글 purchaseToken 또는 'apple:<originalTransactionId>'
  user_id  uuid not null,
  created_at timestamptz not null default now()
);
alter table public.wafa_sub_tokens enable row level security;
grant all on public.wafa_sub_tokens to service_role;

revoke all on function public.wafa_number_paid(uuid,text,text) from public, anon, authenticated;
grant execute on function public.wafa_number_paid(uuid,text,text) to service_role;
grant execute on function public.wafa_checkout_hold(text,text), public.wafa_use_credit(uuid,text),
  public.wafa_claim_free(text), public.wafa_claim_family(text) to authenticated;

select 'wafa checkout ok' as result;
