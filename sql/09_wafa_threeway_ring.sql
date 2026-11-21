-- =====================================================================
-- 와파 WAFA — 3자 통화 초대를 「전화벨」로 (2026-11-21) · 부름 Supabase 에서 Run (07 다음)
--
--   전에는 새로 부른 사람에게 일반 알림만 갔습니다. 이제 진짜 전화처럼 울립니다(잠금 화면 · 아이폰 기본 전화 화면).
--   · 서버가 부른 사람 ↔ 새 사람 1:1 대화방에 「전화 한 통」(calls)을 만들고, 그 표(session_token)를
--     'w3' + 3자 통화 방 번호로 둡니다. 받는 화면이 이 표를 보면 곧바로 3자 통화 방으로 들어갑니다.
--   · wafa_three_way_ring_end(통화) — 45초 안에 안 받았으면 그 전화를 끝냄(부른 사람 화면이 부름)
--   · wafa_three_way_answered(통화) — 받은 사람 화면이 부름(받음 · 끝남 표시)
--   ⚠ 새 표 없음. 다시 돌려도 안전합니다. 맨 아래 'wafa threeway ring ok'
-- =====================================================================

create or replace function public.wafa_three_way(p_link uuid, p_number text, p_kind text default 'voice')
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_me uuid := auth.uid(); n text := regexp_replace(coalesce(p_number, ''), '[^0-9]', '', 'g');
        my_s link_sides; peer_s link_sides; w wafa_numbers; a wafa_accounts; c jsonb; v_room uuid; v_tp uuid;
        d jsonb; v_pair uuid; v_side uuid; v_call uuid; v_tok text;
begin
  if v_me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if coalesce(p_kind, '') not in ('voice', 'video') then p_kind := 'voice'; end if;

  select s.* into my_s from link_sides s join links l on l.id = s.link_id
   where s.link_id = p_link and s.account_id = v_me and l.status = 'active' and coalesce(l.kind, 'pair') = 'pair';
  if my_s.id is null then return jsonb_build_object('ok', false, 'error', 'not_pair'); end if;
  select * into peer_s from link_sides where link_id = p_link and account_id <> v_me limit 1;
  if peer_s.id is null then return jsonb_build_object('ok', false, 'error', 'not_pair'); end if;

  select * into w from wafa_numbers where number = n;
  if w.number is null then
    if (select count(*) from burum_dial_log where account_id = v_me and not hit and at > now() - interval '1 minute') >= 5
       or (select count(*) from burum_dial_log where account_id = v_me and not hit and at > now() - interval '1 day') >= 30 then
      return jsonb_build_object('ok', false, 'error', 'slow_down'); end if;
    insert into burum_dial_log(account_id, hit) values (v_me, false);
    return jsonb_build_object('ok', false, 'error', 'none'); end if;
  if w.owner = v_me then return jsonb_build_object('ok', false, 'error', 'self'); end if;
  if w.owner = peer_s.account_id then return jsonb_build_object('ok', false, 'error', 'already'); end if;
  select * into a from wafa_accounts where user_id = w.owner;
  if a.user_id is not null and not a.open_on then return jsonb_build_object('ok', false, 'error', 'off'); end if;
  if exists (select 1 from nick_blocks where account_id = w.owner and blocked_id = v_me) then
    return jsonb_build_object('ok', false, 'error', 'off'); end if;

  c := wafa_can_call(p_kind = 'video');
  if not coalesce((c->>'ok')::boolean, false) then return c; end if;

  /* 나 ↔ 새 사람 1:1 대화방(없으면 만듦) — 착신전환은 하지 않음 */
  d := wafa_dial(n, 'chat', null, true);
  if not coalesce((d->>'ok')::boolean, false) then return d; end if;
  v_pair := (d->>'link_id')::uuid;
  select id into v_side from link_sides where link_id = v_pair and account_id = v_me;

  v_tp := _wafa_persona(w.owner);
  insert into links (kind, room_name, max_people, status, room_mode)
  values ('group', '3자 통화', 4, 'active', 'wafa3') returning id into v_room;
  insert into link_sides (link_id, account_id, persona_id) values
    (v_room, v_me, my_s.persona_id),
    (v_room, peer_s.account_id, peer_s.persona_id),
    (v_room, w.owner, v_tp);

  /* 새 사람에게 울릴 전화 한 통 — 표가 'w3' + 방 번호 */
  v_tok := 'w3' || replace(v_room::text, '-', '');
  insert into calls (link_id, caller_side_id, session_token, call_type, is_group)
  values (v_pair, v_side, v_tok, p_kind, false) returning id into v_call;

  return jsonb_build_object('ok', true, 'room', v_room, 'number', n,
                            'ring', jsonb_build_object('link', v_pair, 'call', v_call, 'token', v_tok));
end $$;

/* 부른 사람 화면 — 45초 뒤: 아직 안 받았으면 끝냄. 받았는지 돌려줌 */
create or replace function public.wafa_three_way_ring_end(p_call uuid) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare c calls;
begin
  select k.* into c from calls k join link_sides s on s.id = k.caller_side_id
   where k.id = p_call and s.account_id = auth.uid() and k.session_token like 'w3%';
  if c.id is null then return jsonb_build_object('ok', false); end if;
  if c.answered_at is null and c.ended_at is null then
    update calls set ended_at = now(), ended_reason = 'no_answer' where id = p_call;
    return jsonb_build_object('ok', true, 'answered', false);
  end if;
  return jsonb_build_object('ok', true, 'answered', c.answered_at is not null);
end $$;

/* 받은 사람 화면 — 3자 통화 방에 들어오면서 "받음" 표시 */
create or replace function public.wafa_three_way_answered(p_call uuid) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
begin
  update calls k set answered_at = coalesce(k.answered_at, now()), ended_at = coalesce(k.ended_at, now()),
                     ended_reason = coalesce(k.ended_reason, 'completed')
   where k.id = p_call and k.session_token like 'w3%'
     and exists (select 1 from link_sides s where s.link_id = k.link_id and s.account_id = auth.uid() and s.id <> k.caller_side_id);
  return jsonb_build_object('ok', found);
end $$;

grant execute on function public.wafa_three_way(uuid, text, text), public.wafa_three_way_ring_end(uuid), public.wafa_three_way_answered(uuid) to authenticated;

select 'wafa threeway ring ok' as result;
