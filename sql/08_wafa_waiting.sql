-- =====================================================================
-- 와파 WAFA — 통화 중 대기 (2026-11-21) · 부름 Supabase 에서 Run
--
--   통화 중에 다른 사람이 걸면, 통화 화면 위에 "○○ 님 전화 대기 중" 띠가 뜹니다.
--     [끊고 받기] [거절] [💬 통화 중이라고 문자]
--   wafa_waiting_call(지금 통화 id) — 나에게 걸려 와서 아직 아무도 안 받은 1:1 전화(최근 45초) 하나
--   ⚠ 읽기만 하는 함수 하나. 새 표 없음. 다시 돌려도 안전합니다. 맨 아래 'wafa waiting ok'
-- =====================================================================

create or replace function public.wafa_waiting_call(p_except uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object('id', c.id, 'link_id', c.link_id, 'token', c.session_token, 'type', coalesce(c.call_type, 'voice'),
                              'name', coalesce(nullif(me.peer_label, ''), p.display_name, ''))
      from calls c
      join link_sides me on me.link_id = c.link_id and me.account_id = auth.uid()
      left join link_sides cs on cs.id = c.caller_side_id
      left join personas p on p.id = cs.persona_id
     where c.ended_at is null and c.answered_at is null and not coalesce(c.is_group, false)
       and c.created_at > now() - interval '45 seconds'
       and c.caller_side_id is distinct from me.id
       and (p_except is null or c.id <> p_except)
     order by c.created_at desc limit 1), 'null'::jsonb)
$$;

grant execute on function public.wafa_waiting_call(uuid) to authenticated;

select 'wafa waiting ok' as result;
