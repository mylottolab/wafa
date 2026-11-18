-- WAFA 서버 기본 (2026-11-18 회의 결정판)
--   번호 전화(Open Line) 4-3-3 번호(부름과 같은 체계) · 좋은 번호(5/4/3 Stars = 부름 플래티넘/골드/실버 기준) · 회사 소장(SOLD OUT) · 가족 예약
--   구독(1·3·6·12개월 자동결제) · 달마다 한도(음성 300분 · 영상 100분 · 보관 1GB)
--   남은 음성·영상은 다음 달 한정 쿠폰 · 보충권 1,100원 = 100원 단위 11칸 나눠 담기
--   ⚠ 부름 Supabase 프로젝트(azredlrnvsssfjytaotb)에 통째로 Run. 다시 돌려도 안전합니다.
--   ⚠ 부름 표는 바꾸지 않습니다. 부름 번호 표 두 곳(burum_numbers · burum_number_holds)에
--     "WAFA 에서 이미 쓰는 번호는 못 들어가게" 하는 확인(트리거)만 하나씩 붙습니다.
--   ⚠ 등급은 부름의 bn_grade 를 그대로 불러 씁니다 → 부름 기준이 바뀌면 WAFA 도 함께 바뀜
--   ⚠ 표마다 GRANT 를 꼭 넣었습니다(새 표는 GRANT 가 없으면 앱에서 안 보입니다).

create extension if not exists pgcrypto;

-- ───────────────────────── 1. 번호 등급 ─────────────────────────
-- 번호 = 10자리 숫자, 맨 앞은 1~9.  보이는 모양 = 4829-051-318 (부름 bn_fmt 와 같음 · 화면에서는 띄어 쓰기로도 표시)
create or replace function public.wafa_shown(p text) returns text
language sql immutable as $$ select substr(p,1,4)||'-'||substr(p,5,3)||'-'||substr(p,8,3) $$;

-- 같은 숫자 반복 · 연속(오름/내림)
create or replace function public._wafa_same(p text) returns boolean
language sql immutable as $$ select p = repeat(substr(p,1,1), length(p)) $$;
create or replace function public._wafa_run(p text) returns boolean
language sql immutable as $$ select strpos('0123456789', p) > 0 or strpos('9876543210', p) > 0 $$;

-- 등급 — 부름 bn_grade 를 그대로 씀 (platinum=5 Stars · gold=4 Stars · silver=3 Stars)
--   'S' = 회사 특별(10자리 같음 · 맨 앞자리만 다름 · 맨 뒷자리만 다름) → 5 Stars 로 보이고 SOLD OUT
create or replace function public.wafa_grade(p text) returns text
language plpgsql immutable as $$
begin
  if p is null or p !~ '^[1-9][0-9]{9}$' then return null; end if;
  if public._wafa_same(substr(p,2,9)) or public._wafa_same(substr(p,1,9)) then return 'S'; end if;
  return case public.bn_grade(p) when 'platinum' then '5' when 'gold' then '4' when 'silver' then '3' else 'N' end;
end $$;

-- 회사 소장: 특별 번호 전부 + 좋은 번호의 10%(번호마다 늘 같은 결과 — 해시)
create or replace function public.wafa_is_company(p text) returns boolean
language sql immutable as $$
  select case public.wafa_grade(p)
    when 'S' then true
    when 'N' then false
    when null then false
    else abs(hashtext('wafa-hold:'||p)) % 10 = 0 end $$;

create or replace function public.wafa_price(g text) returns int
language sql immutable as $$ select case g when '5' then 110000 when '4' then 55000 when '3' then 11000 else 0 end $$;

-- ───────────────────────── 2. 표 ─────────────────────────
create table if not exists public.wafa_accounts (
  user_id     uuid primary key,
  main_line   text not null default 'open' check (main_line in ('open','private')),   -- 메인: 번호 전화 / 별칭 전화
  open_on     boolean not null default true,      -- 번호 전화 켜기
  private_on  boolean not null default true,      -- 별칭 전화 켜기
  lang        text not null default 'ko' check (lang in ('ko','en')),
  quiet_unknown boolean not null default false,   -- 모르는 번호 조용히
  last_seen   timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

create table if not exists public.wafa_numbers (
  number      text primary key check (number ~ '^[1-9][0-9]{9}$'),
  owner       uuid not null,
  kind        text not null check (kind in ('free','bought','extra','given')),   -- 무료 · 좋은 번호 구매 · 하나 더 · 회사 부여
  grade       text not null,
  is_main     boolean not null default false,
  acquired_at timestamptz not null default now()
);
create index if not exists wafa_numbers_owner on public.wafa_numbers(owner);

-- 가족 예약 (7일) — 초대 코드로 가족이 가입·결제하면 그 사람 번호가 됨
create table if not exists public.wafa_holds (
  number      text primary key check (number ~ '^[1-9][0-9]{9}$'),
  holder      uuid not null,
  code        text not null unique,
  kind        text not null default 'family' check (kind in ('family','checkout')),
  expires_at  timestamptz not null
);
create index if not exists wafa_holds_holder on public.wafa_holds(holder);

-- 구독 (스토어 알림이 갱신)
create table if not exists public.wafa_subs (
  user_id     uuid primary key,
  product     text not null check (product in ('wafa_1m','wafa_3m','wafa_6m','wafa_12m')),
  status      text not null check (status in ('active','grace','canceled','expired','refunded')),
  auto_renew  boolean not null default true,
  expires_at  timestamptz not null,
  store       text not null check (store in ('apple','google','web')),
  original_tx text,
  updated_at  timestamptz not null default now()
);

-- 달마다 사용량 (ym = 한국 시간 'YYYY-MM')
create table if not exists public.wafa_usage (
  user_id   uuid not null,
  ym        text not null,
  voice_sec bigint not null default 0,
  video_sec bigint not null default 0,
  primary key (user_id, ym)
);

-- 달마다 더 받은 분: 이월 쿠폰(rollover) · 보충권(addon)
create table if not exists public.wafa_bonus (
  id        bigserial primary key,
  user_id   uuid not null,
  ym        text not null,
  source    text not null check (source in ('rollover','addon')),
  voice_min int not null default 0,
  video_min int not null default 0,
  ref       text,
  created_at timestamptz not null default now()
);
create index if not exists wafa_bonus_user on public.wafa_bonus(user_id, ym);
create unique index if not exists wafa_bonus_roll_once on public.wafa_bonus(user_id, ym) where source = 'rollover';

-- 보충권 칸(100원 = 1칸, 1장 = 11칸) · 아직 안 나눈 칸
create table if not exists public.wafa_addon_wallet (
  user_id  uuid primary key,
  units    int not null default 0 check (units >= 0),
  store_mb int not null default 0 check (store_mb >= 0)   -- 보충한 보관(구독이 이어지는 동안 유지)
);

-- 결제 기록 (같은 영수증 두 번 처리 방지)
create table if not exists public.wafa_pay_log (
  tx       text primary key,
  user_id  uuid not null,
  sku      text not null,
  amount   int,
  at       timestamptz not null default now()
);

alter table public.wafa_accounts     enable row level security;
alter table public.wafa_numbers      enable row level security;
alter table public.wafa_holds        enable row level security;
alter table public.wafa_subs         enable row level security;
alter table public.wafa_usage        enable row level security;
alter table public.wafa_bonus        enable row level security;
alter table public.wafa_addon_wallet enable row level security;
alter table public.wafa_pay_log      enable row level security;

drop policy if exists wafa_acc_me on public.wafa_accounts;
create policy wafa_acc_me on public.wafa_accounts for select to authenticated using (user_id = auth.uid());
drop policy if exists wafa_num_me on public.wafa_numbers;
create policy wafa_num_me on public.wafa_numbers for select to authenticated using (owner = auth.uid());
drop policy if exists wafa_hold_me on public.wafa_holds;
create policy wafa_hold_me on public.wafa_holds for select to authenticated using (holder = auth.uid());
drop policy if exists wafa_sub_me on public.wafa_subs;
create policy wafa_sub_me on public.wafa_subs for select to authenticated using (user_id = auth.uid());
drop policy if exists wafa_use_me on public.wafa_usage;
create policy wafa_use_me on public.wafa_usage for select to authenticated using (user_id = auth.uid());
drop policy if exists wafa_bonus_me on public.wafa_bonus;
create policy wafa_bonus_me on public.wafa_bonus for select to authenticated using (user_id = auth.uid());
drop policy if exists wafa_wallet_me on public.wafa_addon_wallet;
create policy wafa_wallet_me on public.wafa_addon_wallet for select to authenticated using (user_id = auth.uid());

grant select on public.wafa_accounts, public.wafa_numbers, public.wafa_holds, public.wafa_subs,
                public.wafa_usage, public.wafa_bonus, public.wafa_addon_wallet to authenticated;
grant all on public.wafa_accounts, public.wafa_numbers, public.wafa_holds, public.wafa_subs, public.wafa_usage,
             public.wafa_bonus, public.wafa_addon_wallet, public.wafa_pay_log to service_role;
grant usage, select on sequence public.wafa_bonus_id_seq to service_role;

-- ───────────────────────── 2-1. 부름과 번호 겹치지 않게 ─────────────────────────
-- WAFA 쪽에서 볼 때 "이미 쓰이는 번호": WAFA 번호 · WAFA 예약 · 부름 번호 · 부름 결제 중 잡아 둔 번호 · 부름 회사 보유
create or replace function public._wafa_busy(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from wafa_numbers where number = p)
      or exists (select 1 from wafa_holds where number = p and expires_at > now())
      or exists (select 1 from burum_numbers where number = p)
      or exists (select 1 from burum_number_holds where number = p and until > now())
      or exists (select 1 from burum_number_reserved where number = p) $$;

-- 부름 쪽에서 번호를 쓰거나 잡으려 할 때, WAFA 가 이미 쓰는 번호면 막음
create or replace function public._wafa_guard_burum() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.number is not null and (exists (select 1 from wafa_numbers where number = new.number)
     or exists (select 1 from wafa_holds where number = new.number and expires_at > now())) then
    raise exception 'taken' using hint = 'WAFA 에서 쓰는 번호입니다';
  end if;
  return new;
end $$;
drop trigger if exists wafa_guard on public.burum_numbers;
create trigger wafa_guard before insert or update of number on public.burum_numbers
  for each row execute function public._wafa_guard_burum();
drop trigger if exists wafa_guard on public.burum_number_holds;
create trigger wafa_guard before insert or update of number on public.burum_number_holds
  for each row execute function public._wafa_guard_burum();

-- ───────────────────────── 3. 번호 보기 · 고르기 ─────────────────────────
-- 번호 하나의 상태: free(고를 수 있음) · mine · taken · held · company(SOLD OUT)
create or replace function public.wafa_number_info(p_number text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g text := wafa_grade(p_number); o uuid; h record;
begin
  if g is null then return jsonb_build_object('ok', false, 'error', 'bad_number'); end if;
  select owner into o from wafa_numbers where number = p_number;
  select * into h from wafa_holds where number = p_number and expires_at > now();
  return jsonb_build_object('ok', true, 'number', p_number, 'shown', wafa_shown(p_number),
    'grade', case when g = 'S' then '5' else g end, 'price', wafa_price(case when g = 'S' then '5' else g end),
    'status', case when o = auth.uid() then 'mine' when o is not null then 'taken'
                   when exists (select 1 from burum_numbers where number = p_number)
                     or exists (select 1 from burum_number_holds where number = p_number and until > now()) then 'taken'
                   when exists (select 1 from burum_number_reserved where number = p_number) then 'company'
                   when wafa_is_company(p_number) then 'company'
                   when h.number is not null and h.holder = auth.uid() then 'held_mine'
                   when h.number is not null then 'held' else 'free' end);
end $$;

-- 무작위 후보 하나 만들기 (등급별로 무늬를 직접 조립 → 빠름). 맞는지는 wafa_grade 가 다시 확인
create or replace function public._wafa_candidate(g text) returns text
language plpgsql volatile as $$
declare a text := (1000 + floor(random()*9000))::int::text; d text; x text; i int;
  runs6 text[] := array['012345','123456','234567','345678','456789','987654','876543','765432','654321','543210'];
  runs4 text[] := array['0123','1234','2345','3456','4567','5678','6789','9876','8765','7654','6543','5432','4321','3210'];
  runs4a text[] := array['1234','2345','3456','4567','5678','6789','9876','8765','7654','6543','5432','4321','3210'];
begin
  if g = '5' then
    return a || repeat(floor(random()*10)::int::text, 6);
  elsif g = '4' then
    i := floor(random()*4)::int;
    if i = 0 then d := (1 + floor(random()*9))::int::text; return repeat(d,4) || lpad(floor(random()*1e6)::int::text,6,'0'); end if;
    if i = 1 then x := lpad(floor(random()*1000)::int::text,3,'0'); return a || x || x; end if;
    if i = 2 then return a || repeat(floor(random()*10)::int::text,3) || repeat(floor(random()*10)::int::text,3); end if;
    return a || runs6[1 + floor(random()*10)::int];
  elsif g = '3' then
    i := floor(random()*3)::int;
    if i = 0 then return a || lpad(floor(random()*1000)::int::text,3,'0') || repeat((array['7','8','9','0'])[1 + floor(random()*4)::int],3); end if;
    if i = 1 then return a || lpad(floor(random()*100)::int::text,2,'0') || runs4[1 + floor(random()*14)::int]; end if;
    return runs4a[1 + floor(random()*13)::int] || lpad(floor(random()*1e6)::int::text,6,'0');
  else
    return a || lpad(floor(random()*1e6)::int::text,6,'0');
  end if;
end $$;

-- 좋은 번호 가게: 등급('5','4','3','N')을 고르면 무작위 n개. 회사 소장은 SOLD OUT 으로 섞여 보임
create or replace function public.wafa_number_shop(p_grade text default 'N', p_limit int default 12)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; c text; g text; tries int := 0; seen text[] := '{}'; st text;
begin
  if p_grade not in ('5','4','3','N') then return jsonb_build_object('ok', false, 'error', 'bad_grade'); end if;
  p_limit := least(greatest(coalesce(p_limit, 12), 1), 30);
  while jsonb_array_length(out) < p_limit and tries < p_limit * 40 loop
    tries := tries + 1;
    c := _wafa_candidate(p_grade); g := wafa_grade(c);
    if c = any(seen) then continue; end if;
    seen := seen || c;
    if g = 'S' then g := '5'; end if;
    if g <> p_grade then continue; end if;               -- 더 높은 등급으로 넘어간 것은 제외
    if _wafa_busy(c) then continue; end if;
    st := case when wafa_is_company(c) then 'company' else 'free' end;
    if p_grade = 'N' and st = 'company' then continue; end if;
    out := out || jsonb_build_object('number', c, 'shown', wafa_shown(c), 'grade', g, 'price', wafa_price(g), 'status', st);
  end loop;
  return jsonb_build_object('ok', true, 'items', out);
end $$;

-- 가족 번호 찾기: 같은 가운데 3자리(pos='mid') 또는 끝 3자리(pos='last')를 나눠 가진 빈 번호 n개
create or replace function public.wafa_family_find(p_part text, p_pos text, p_count int)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; c text; g text; tries int := 0; seen text[] := '{}';
begin
  if not (p_pos in ('mid','last') and p_part ~ '^[0-9]{3}$') then
    return jsonb_build_object('ok', false, 'error', 'bad_part'); end if;
  p_count := least(greatest(coalesce(p_count, 2), 2), 6);
  while jsonb_array_length(out) < p_count and tries < 400 loop
    tries := tries + 1;
    c := (1000 + floor(random()*9000))::int::text ||
         case when p_pos = 'mid' then p_part || lpad(floor(random()*1000)::int::text, 3, '0')
              else lpad(floor(random()*1000)::int::text, 3, '0') || p_part end;
    if c = any(seen) then continue; end if;
    seen := seen || c;
    g := wafa_grade(c);
    if g = 'S' or wafa_is_company(c) then continue; end if;
    if _wafa_busy(c) then continue; end if;
    out := out || jsonb_build_object('number', c, 'shown', wafa_shown(c), 'grade', g, 'price', wafa_price(g));
  end loop;
  return jsonb_build_object('ok', true, 'items', out);
end $$;

-- 가족 예약: 고른 번호들을 7일간 잡아 두고 번호마다 초대 코드. 한 사람 최대 6개
create or replace function public.wafa_family_hold(p_numbers text[])
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me uuid := auth.uid(); n text; codes jsonb := '[]'::jsonb; k text; have int;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  delete from wafa_holds where expires_at <= now();
  select count(*) into have from wafa_holds where holder = me;
  if have + coalesce(array_length(p_numbers, 1), 0) > 6 then return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
  foreach n in array p_numbers loop
    if wafa_grade(n) is null or wafa_grade(n) = 'S' or wafa_is_company(n)
       or _wafa_busy(n) or exists (select 1 from wafa_holds where number = n) then
      raise exception 'not_free:%', n;          -- 하나라도 안 되면 전부 취소
    end if;
    k := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8));
    insert into wafa_holds(number, holder, code, kind, expires_at) values (n, me, k, 'family', now() + interval '7 days');
    codes := codes || jsonb_build_object('number', n, 'shown', wafa_shown(n), 'code', k, 'grade', wafa_grade(n), 'price', wafa_price(wafa_grade(n)));
  end loop;
  return jsonb_build_object('ok', true, 'holds', codes, 'expires_at', now() + interval '7 days');
exception when raise_exception then
  return jsonb_build_object('ok', false, 'error', 'not_free', 'detail', sqlerrm);
end $$;

-- 번호 주기 (서버 전용: 결제 확인 · 첫 구독 · 가족 코드 · 회사 부여)
create or replace function public.wafa_grant_number(p_user uuid, p_number text, p_kind text, p_tx text default null, p_code text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare g text := wafa_grade(p_number); h record;
begin
  if g is null then return jsonb_build_object('ok', false, 'error', 'bad_number'); end if;
  if p_tx is not null then
    if exists (select 1 from wafa_pay_log where tx = p_tx) then return jsonb_build_object('ok', true, 'dup', true); end if;
  end if;
  if exists (select 1 from wafa_numbers where number = p_number)
     or exists (select 1 from burum_numbers where number = p_number)
     or exists (select 1 from burum_number_holds where number = p_number and until > now())
     or exists (select 1 from burum_number_reserved where number = p_number) then
    return jsonb_build_object('ok', false, 'error', 'taken'); end if;
  if p_kind <> 'given' and wafa_is_company(p_number) then return jsonb_build_object('ok', false, 'error', 'company'); end if;
  select * into h from wafa_holds where number = p_number and expires_at > now();
  if h.number is not null and h.holder <> p_user and coalesce(h.code, '') <> coalesce(p_code, '') then
    return jsonb_build_object('ok', false, 'error', 'held'); end if;
  if p_kind = 'free' and g <> 'N' then return jsonb_build_object('ok', false, 'error', 'not_free_grade'); end if;
  if p_kind = 'free' and exists (select 1 from wafa_numbers where owner = p_user and kind = 'free') then
    return jsonb_build_object('ok', false, 'error', 'free_used'); end if;
  insert into wafa_numbers(number, owner, kind, grade, is_main)
    values (p_number, p_user, p_kind, case when g = 'S' then '5' else g end,
            not exists (select 1 from wafa_numbers where owner = p_user));
  delete from wafa_holds where number = p_number;
  if p_tx is not null then insert into wafa_pay_log(tx, user_id, sku) values (p_tx, p_user, 'number:' || p_kind); end if;
  return jsonb_build_object('ok', true, 'number', p_number, 'shown', wafa_shown(p_number));
end $$;

-- ───────────────────────── 4. 구독 · 한도 ─────────────────────────
create or replace function public._wafa_ym(t timestamptz default now()) returns text
language sql stable as $$ select to_char(t at time zone 'Asia/Seoul', 'YYYY-MM') $$;

create or replace function public._wafa_active(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from wafa_subs where user_id = p_user and status in ('active','grace','canceled') and expires_at > now()) $$;

-- 이번 달 한도와 남은 양 (분 단위). 쓰는 순서: 이월 쿠폰 → 기본 → 보충
create or replace function public.wafa_quota(p_user uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid := coalesce(auth.uid(), p_user); v_ym text := _wafa_ym(); act boolean;   -- 로그인한 사람은 자기 것만
  rv int; rd int; av int; ad int; uv bigint; ud bigint; smb int;
begin
  act := _wafa_active(u);
  select coalesce(sum(voice_min) filter (where source='rollover'),0), coalesce(sum(video_min) filter (where source='rollover'),0),
         coalesce(sum(voice_min) filter (where source='addon'),0),    coalesce(sum(video_min) filter (where source='addon'),0)
    into rv, rd, av, ad from wafa_bonus where user_id = u and wafa_bonus.ym = v_ym;
  select coalesce(voice_sec,0), coalesce(video_sec,0) into uv, ud from wafa_usage where user_id = u and wafa_usage.ym = v_ym;
  uv := coalesce(uv,0); ud := coalesce(ud,0);
  select coalesce(store_mb,0) into smb from wafa_addon_wallet where user_id = u;
  return jsonb_build_object('active', act, 'ym', v_ym,
    'voice', jsonb_build_object('base', case when act then 300 else 0 end, 'rollover', rv, 'addon', av,
             'used', ceil(uv/60.0), 'left', greatest(0, (case when act then 300 else 0 end) + rv + av - ceil(uv/60.0))),
    'video', jsonb_build_object('base', case when act then 100 else 0 end, 'rollover', rd, 'addon', ad,
             'used', ceil(ud/60.0), 'left', greatest(0, (case when act then 100 else 0 end) + rd + ad - ceil(ud/60.0))),
    'store_mb', (case when act then 1024 else 0 end) + coalesce(smb,0),
    'text', true);                                         -- 문자는 구독이 끝나도 늘 됨
end $$;

-- 전화 걸기 가능? (받기 · 문자는 언제나 됨)
create or replace function public.wafa_can_call(p_video boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q jsonb := wafa_quota(auth.uid()); left_min int;
begin
  if not (q->>'active')::boolean then return jsonb_build_object('ok', false, 'error', 'need_plan'); end if;
  left_min := (q -> case when p_video then 'video' else 'voice' end ->> 'left')::int;
  if left_min <= 0 then return jsonb_build_object('ok', false, 'error', 'need_addon'); end if;
  return jsonb_build_object('ok', true, 'left_min', left_min);
end $$;

-- 통화가 끝나면 사용량 더하기 (서버 전용 — 통화 기록 처리에서 부름)
create or replace function public.wafa_add_usage(p_user uuid, p_video boolean, p_sec int)
returns void language sql volatile security definer set search_path = public as $$
  insert into wafa_usage(user_id, ym, voice_sec, video_sec)
  values (p_user, _wafa_ym(), case when p_video then 0 else greatest(p_sec,0) end, case when p_video then greatest(p_sec,0) else 0 end)
  on conflict (user_id, ym) do update set voice_sec = wafa_usage.voice_sec + excluded.voice_sec,
                                          video_sec = wafa_usage.video_sec + excluded.video_sec $$;

-- 스토어 알림 반영 (서버 전용: 구독 시작 · 갱신 · 변경 · 해지 · 환불 · 만료)
create or replace function public.wafa_sub_apply(p_user uuid, p_product text, p_status text, p_expires timestamptz,
                                                 p_auto boolean, p_store text, p_tx text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
begin
  insert into wafa_subs(user_id, product, status, auto_renew, expires_at, store, original_tx, updated_at)
  values (p_user, p_product, p_status, p_auto, p_expires, p_store, p_tx, now())
  on conflict (user_id) do update set product = excluded.product, status = excluded.status, auto_renew = excluded.auto_renew,
     expires_at = excluded.expires_at, store = excluded.store, original_tx = coalesce(excluded.original_tx, wafa_subs.original_tx), updated_at = now();
  insert into wafa_accounts(user_id) values (p_user) on conflict do nothing;
  return jsonb_build_object('ok', true, 'active', _wafa_active(p_user));
end $$;

-- 보충권 1장(1,100원) 결제 확인 → 11칸 (서버 전용, 같은 영수증은 한 번만)
create or replace function public.wafa_addon_paid(p_user uuid, p_tx text, p_count int default 1)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
begin
  if exists (select 1 from wafa_pay_log where tx = p_tx) then return jsonb_build_object('ok', true, 'dup', true); end if;
  insert into wafa_pay_log(tx, user_id, sku, amount) values (p_tx, p_user, 'wafa_addon', 1100 * p_count);
  insert into wafa_addon_wallet(user_id, units) values (p_user, 11 * p_count)
    on conflict (user_id) do update set units = wafa_addon_wallet.units + 11 * p_count;
  return jsonb_build_object('ok', true, 'units', (select units from wafa_addon_wallet where user_id = p_user));
end $$;

-- 보충 칸 나눠 담기: 100원(1칸)당 음성 30분 · 영상 10분 · 보관 100MB
create or replace function public.wafa_addon_allocate(p_voice int, p_video int, p_store int)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me uuid := auth.uid(); have int; need int := coalesce(p_voice,0) + coalesce(p_video,0) + coalesce(p_store,0);
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if least(coalesce(p_voice,0), coalesce(p_video,0), coalesce(p_store,0)) < 0 or need <= 0 then
    return jsonb_build_object('ok', false, 'error', 'bad_units'); end if;
  select units into have from wafa_addon_wallet where user_id = me for update;
  if coalesce(have, 0) < need then return jsonb_build_object('ok', false, 'error', 'not_enough', 'have', coalesce(have,0)); end if;
  update wafa_addon_wallet set units = units - need, store_mb = store_mb + 100 * coalesce(p_store,0) where user_id = me;
  if coalesce(p_voice,0) + coalesce(p_video,0) > 0 then
    insert into wafa_bonus(user_id, ym, source, voice_min, video_min, ref)
    values (me, _wafa_ym(), 'addon', 30 * coalesce(p_voice,0), 10 * coalesce(p_video,0), 'alloc');
  end if;
  return jsonb_build_object('ok', true, 'quota', wafa_quota(me), 'units_left', have - need);
end $$;

-- 달이 바뀔 때 이월 (서버 전용 · 매달 1일 0시 5분 한국시간 예약 실행)
--   지난달 (기본 + 보충) 중 남은 것 → 이번 달 한정 쿠폰. 지난달 쿠폰은 먼저 쓴 것으로 보고 다시 넘기지 않음
create or replace function public.wafa_rollover(p_from_ym text default null)
returns int language plpgsql volatile security definer set search_path = public as $$
declare f text := coalesce(p_from_ym, _wafa_ym(now() - interval '1 month'));
  t text := to_char(to_date(f || '-01', 'YYYY-MM-DD') + interval '1 month', 'YYYY-MM'); n int := 0; r record;
begin
  for r in
    select s.user_id,
      coalesce((select sum(voice_min) from wafa_bonus b where b.user_id = s.user_id and b.ym = f and source = 'rollover'),0) rv,
      coalesce((select sum(video_min) from wafa_bonus b where b.user_id = s.user_id and b.ym = f and source = 'rollover'),0) rd,
      coalesce((select sum(voice_min) from wafa_bonus b where b.user_id = s.user_id and b.ym = f and source = 'addon'),0) av,
      coalesce((select sum(video_min) from wafa_bonus b where b.user_id = s.user_id and b.ym = f and source = 'addon'),0) ad,
      coalesce((select ceil(voice_sec/60.0) from wafa_usage w where w.user_id = s.user_id and w.ym = f),0) uv,
      coalesce((select ceil(video_sec/60.0) from wafa_usage w where w.user_id = s.user_id and w.ym = f),0) ud
    from wafa_subs s where s.status in ('active','grace','canceled') and s.expires_at > now()
  loop
    insert into wafa_bonus(user_id, ym, source, voice_min, video_min, ref)
    values (r.user_id, t, 'rollover',
            greatest(0, 300 + r.av - greatest(0, r.uv - r.rv)),
            greatest(0, 100 + r.ad - greatest(0, r.ud - r.rd)), 'from ' || f)
    on conflict do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ───────────────────────── 5. 권한 ─────────────────────────
revoke all on function public.wafa_grant_number(uuid,text,text,text,text), public.wafa_add_usage(uuid,boolean,int),
  public.wafa_sub_apply(uuid,text,text,timestamptz,boolean,text,text), public.wafa_addon_paid(uuid,text,int),
  public.wafa_rollover(text) from public, anon, authenticated;
grant execute on function public.wafa_grant_number(uuid,text,text,text,text), public.wafa_add_usage(uuid,boolean,int),
  public.wafa_sub_apply(uuid,text,text,timestamptz,boolean,text,text), public.wafa_addon_paid(uuid,text,int),
  public.wafa_rollover(text) to service_role;
grant execute on function public.wafa_shown(text), public.wafa_grade(text), public.wafa_price(text),
  public.wafa_number_info(text), public.wafa_number_shop(text,int), public.wafa_family_find(text,text,int),
  public.wafa_family_hold(text[]), public.wafa_quota(uuid), public.wafa_can_call(boolean), public.wafa_addon_allocate(int,int,int)
  to anon, authenticated;

select 'wafa core ok' as result;
