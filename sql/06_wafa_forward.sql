-- =====================================================================
-- 와파 WAFA — 착신전환 (2026-11-21) · 부름 Supabase 에서 Run (04 · 05 다음)
--
--   내 와파 번호로 온 전화를 다른 와파 번호로 넘깁니다.
--     · 'always'   항상 — 걸자마자 넘긴 번호로 바로 연결
--     · 'noanswer' 안 받을 때 — 40초 안 받거나 거절하면 넘긴 번호로 이어서 걸림
--   ⚠ 한 번만 넘깁니다(넘긴 번호가 또 넘겨 두었어도 거기서 멈춤) — 빙빙 도는 일 없음
--   ⚠ 문자는 넘기지 않습니다(원래 번호 주인에게 그대로)
--   ⚠ 넘긴 번호로의 통화도 건 사람의 구독 · 남은 시간으로 셉니다(지금과 같음)
--
--   wafa_set_forward(mode, number) · wafa_get_forward() · wafa_forward_noanswer(link, kind)
--   wafa_dial 은 4번째 칸(p_nofwd)이 생겨 다시 만듭니다 — 앱 화면은 그대로 3칸으로 불러도 됩니다.
--   다시 돌려도 안전합니다. 맨 아래 'wafa forward ok'
-- =====================================================================

alter table public.wafa_accounts add column if not exists fwd_mode text not null default 'off';
alter table public.wafa_accounts add column if not exists fwd_to   text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'wafa_accounts_fwd_mode_chk') then
    alter table public.wafa_accounts add constraint wafa_accounts_fwd_mode_chk check (fwd_mode in ('off','always','noanswer'));
  end if;
end $$;

/* 설정 */
create or replace function public.wafa_set_forward(p_mode text, p_number text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me uuid := auth.uid(); n text := regexp_replace(coalesce(p_number, ''), '[^0-9]', '', 'g'); w wafa_numbers;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if coalesce(p_mode, '') not in ('off','always','noanswer') then return jsonb_build_object('ok', false, 'error', 'bad_mode'); end if;
  insert into wafa_accounts(user_id) values (me) on conflict do nothing;
  if p_mode = 'off' then
    update wafa_accounts set fwd_mode = 'off' where user_id = me;
    return jsonb_build_object('ok', true, 'mode', 'off');
  end if;
  if not exists (select 1 from wafa_numbers where owner = me) then return jsonb_build_object('ok', false, 'error', 'no_number'); end if;
  select * into w from wafa_numbers where number = n;
  if w.number is null then return jsonb_build_object('ok', false, 'error', 'none'); end if;
  if w.owner = me then return jsonb_build_object('ok', false, 'error', 'self'); end if;
  update wafa_accounts set fwd_mode = p_mode, fwd_to = n where user_id = me;
  return jsonb_build_object('ok', true, 'mode', p_mode, 'number', n);
end $$;

create or replace function public.wafa_get_forward() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('mode', fwd_mode, 'number', fwd_to) from wafa_accounts where user_id = auth.uid()),
                  jsonb_build_object('mode', 'off', 'number', null))
$$;

/* 번호로 걸기 — 04 와 같고, 받는 사람이 「항상」 착신전환을 해 두었으면 넘긴 번호로 (전화만 · 한 번만) */
drop function if exists public.wafa_dial(text, text, text);
create or replace function public.wafa_dial(p_number text, p_kind text default 'voice', p_note text default null, p_nofwd boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_me uuid := auth.uid(); n text := regexp_replace(coalesce(p_number, ''), '[^0-9]', '', 'g');
        w wafa_numbers; a wafa_accounts; c jsonb; v_link uuid; v_my uuid; v_their uuid; v_code text; v_out jsonb; v_fwd text := null;
begin
  if v_me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if coalesce(p_kind, '') not in ('voice', 'video', 'chat') then p_kind := 'voice'; end if;

  /* 번호 훑어보기 막기 — 없는 번호 1분 5번 · 하루 30번, 모두 합쳐 하루 150번 */
  if (select count(*) from burum_dial_log where account_id = v_me and not hit and at > now() - interval '1 minute') >= 5
     or (select count(*) from burum_dial_log where account_id = v_me and not hit and at > now() - interval '1 day') >= 30
     or (select count(*) from burum_dial_log where account_id = v_me and at > now() - interval '1 day') >= 150 then
    return jsonb_build_object('ok', false, 'error', 'slow_down'); end if;

  select * into w from wafa_numbers where number = n;
  if w.number is null then
    insert into burum_dial_log(account_id, hit) values (v_me, false);
    return jsonb_build_object('ok', false, 'error', 'none'); end if;
  insert into burum_dial_log(account_id, hit) values (v_me, true);
  if w.owner = v_me then return jsonb_build_object('ok', false, 'error', 'self'); end if;

  select * into a from wafa_accounts where user_id = w.owner;

  /* 📲 착신전환(항상) — 전화만, 한 번만. 넘긴 번호가 없어졌거나 나 자신이면 원래대로 */
  if not p_nofwd and p_kind in ('voice', 'video') and a.user_id is not null and a.fwd_mode = 'always' and a.fwd_to is not null then
    declare w2 wafa_numbers; begin
      select * into w2 from wafa_numbers where number = a.fwd_to;
      if w2.number is not null and w2.owner <> v_me and w2.owner <> w.owner then
        v_fwd := n; w := w2; n := w2.number;
        select * into a from wafa_accounts where user_id = w.owner;
      end if;
    end;
  end if;

  if a.user_id is not null and not a.open_on then return jsonb_build_object('ok', false, 'error', 'off'); end if;
  if exists (select 1 from nick_blocks where account_id = w.owner and blocked_id = v_me) then
    return jsonb_build_object('ok', false, 'error', 'off'); end if;

  /* 통화는 구독 · 남은 시간이 있어야 (문자는 무료) */
  if p_kind in ('voice', 'video') then
    c := wafa_can_call(p_kind = 'video');
    if not coalesce((c->>'ok')::boolean, false) then return c; end if;
  end if;

  /* 이미 이어진 사이 */
  select l.id into v_link from links l
    join link_sides o on o.link_id = l.id and o.account_id = w.owner
    join link_sides m on m.link_id = l.id and m.account_id = v_me
   where l.status = 'active' and coalesce(l.kind, 'pair') = 'pair'
   order by l.last_activity_at desc nulls last limit 1;
  if v_link is not null then
    return jsonb_build_object('ok', true, 'state', 'linked', 'link_id', v_link, 'fwd_from', v_fwd, 'fwd_to', case when v_fwd is null then null else n end);
  end if;

  /* 새로 잇기 — 상대 별칭이 내준 1회용 초대를 내 별칭으로 바로 씀 */
  v_my := _wafa_persona(v_me);
  v_their := _wafa_persona(w.owner);
  insert into invites(code, issuer_account_id, issuer_persona_id, memo, max_uses, expires_at)
  values (substr(replace(gen_random_uuid()::text, '-', ''), 1, 16), w.owner, v_their,
          '와파 번호 ' || substr(n, 1, 4) || '-' || substr(n, 5, 3) || '-' || substr(n, 8, 3), 1, now() + interval '1 day')
  returning code into v_code;
  v_out := use_invite(v_code, v_my, null);
  if not coalesce((v_out->>'ok')::boolean, false) then return v_out; end if;
  return jsonb_build_object('ok', true, 'state', 'linked', 'link_id', v_out->>'link_id', 'new', true,
                            'fwd_from', v_fwd, 'fwd_to', case when v_fwd is null then null else n end);
end $$;

/* 안 받을 때 — 통화 화면이 "안 받음 · 거절" 뒤에 부릅니다. 상대가 「안 받을 때」로 넘겨 두었으면 그 번호로 이어 줌 */
create or replace function public.wafa_forward_noanswer(p_link uuid, p_kind text default 'voice')
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_me uuid := auth.uid(); v_peer uuid; a wafa_accounts; v_out jsonb;
begin
  if v_me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  select o.account_id into v_peer from link_sides m join link_sides o on o.link_id = m.link_id and o.account_id <> m.account_id
   where m.link_id = p_link and m.account_id = v_me limit 1;
  if v_peer is null then return jsonb_build_object('ok', false, 'error', 'none'); end if;
  select * into a from wafa_accounts where user_id = v_peer;
  if a.user_id is null or a.fwd_mode <> 'noanswer' or a.fwd_to is null then return jsonb_build_object('ok', false, 'error', 'none'); end if;
  if exists (select 1 from wafa_numbers where number = a.fwd_to and owner in (v_me, v_peer)) then
    return jsonb_build_object('ok', false, 'error', 'none'); end if;
  v_out := wafa_dial(a.fwd_to, case when p_kind = 'video' then 'video' else 'voice' end, null, true);
  if coalesce((v_out->>'ok')::boolean, false) then v_out := v_out || jsonb_build_object('fwd_to', a.fwd_to); end if;
  return v_out;
end $$;

grant execute on function public.wafa_dial(text, text, text, boolean) to authenticated;
grant execute on function public.wafa_set_forward(text, text), public.wafa_get_forward(), public.wafa_forward_noanswer(uuid, text) to authenticated;

select 'wafa forward ok' as result;
