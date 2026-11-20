-- =====================================================================
-- 와파 WAFA — 3자 통화 (2026-11-21) · 부름 Supabase 에서 Run (04 · 06 다음)
--
--   1:1 통화 중 [＋ 추가] → 와파 번호 10자리 → 세 사람이 함께 통화
--   · 서버가 세 사람만 들어간 작은 방(links.kind = 'group', room_mode = 'wafa3')을 만들고
--     세 사람 모두 그 방의 단체 통화(부름 방 통화와 같은 길 · join_call)로 옮깁니다
--   · 통화 중이던 상대는 화면이 알아서 넘어가고, 새로 부른 사람에게는 「3자 통화 초대」 알림
--   · 부른 사람(나)의 구독 · 남은 시간이 있어야 합니다(wafa_can_call). 통화 시간도 부른 사람에게만 셉니다
--   · 새 표는 없습니다. 다시 돌려도 안전합니다. 맨 아래 'wafa threeway ok'
-- =====================================================================

create or replace function public.wafa_three_way(p_link uuid, p_number text, p_kind text default 'voice')
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_me uuid := auth.uid(); n text := regexp_replace(coalesce(p_number, ''), '[^0-9]', '', 'g');
        my_s link_sides; peer_s link_sides; w wafa_numbers; a wafa_accounts; c jsonb; v_room uuid; v_tp uuid;
begin
  if v_me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if coalesce(p_kind, '') not in ('voice', 'video') then p_kind := 'voice'; end if;

  select s.* into my_s from link_sides s join links l on l.id = s.link_id
   where s.link_id = p_link and s.account_id = v_me and l.status = 'active' and coalesce(l.kind, 'pair') = 'pair';
  if my_s.id is null then return jsonb_build_object('ok', false, 'error', 'not_pair'); end if;
  select * into peer_s from link_sides where link_id = p_link and account_id <> v_me limit 1;
  if peer_s.id is null then return jsonb_build_object('ok', false, 'error', 'not_pair'); end if;

  /* 번호 훑어보기 막기 — wafa_dial 과 같은 기록 */
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
  if w.owner = peer_s.account_id then return jsonb_build_object('ok', false, 'error', 'already'); end if;
  select * into a from wafa_accounts where user_id = w.owner;
  if a.user_id is not null and not a.open_on then return jsonb_build_object('ok', false, 'error', 'off'); end if;
  if exists (select 1 from nick_blocks where account_id = w.owner and blocked_id = v_me) then
    return jsonb_build_object('ok', false, 'error', 'off'); end if;

  c := wafa_can_call(p_kind = 'video');
  if not coalesce((c->>'ok')::boolean, false) then return c; end if;

  v_tp := _wafa_persona(w.owner);
  insert into links (kind, room_name, max_people, status, room_mode)
  values ('group', '3자 통화', 4, 'active', 'wafa3') returning id into v_room;
  insert into link_sides (link_id, account_id, persona_id) values
    (v_room, v_me, my_s.persona_id),
    (v_room, peer_s.account_id, peer_s.persona_id),
    (v_room, w.owner, v_tp);

  return jsonb_build_object('ok', true, 'room', v_room, 'number', n);
end $$;

/* 통화 중이던 상대 화면이 3초마다 / 상대가 끊었을 때 묻습니다 — "우리 둘이 들어간 3자 통화 방이 방금 생겼나?" */
create or replace function public.wafa_three_way_room(p_link uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select l.id from links l
   where l.kind = 'group' and l.room_mode = 'wafa3' and l.status = 'active'
     and l.created_at > now() - interval '3 minutes'
     and exists (select 1 from link_sides s where s.link_id = l.id and s.account_id = auth.uid())
     and exists (select 1 from link_sides s join link_sides o on o.link_id = s.link_id and o.account_id <> s.account_id
                  where s.link_id = p_link and s.account_id = auth.uid()
                    and exists (select 1 from link_sides x where x.link_id = l.id and x.account_id = o.account_id))
   order by l.created_at desc limit 1
$$;

grant execute on function public.wafa_three_way(uuid, text, text), public.wafa_three_way_room(uuid) to authenticated;

select 'wafa threeway ok' as result;
