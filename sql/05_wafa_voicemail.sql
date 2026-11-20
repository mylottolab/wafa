-- =====================================================================
-- 와파 WAFA — 음성사서함 (2026-11-21) · 부름 Supabase 에서 Run
--
--   걸었는데 상대가 안 받거나 거절하면, 건 사람 화면에 [🎙 음성 메시지 남기기] 가 나옵니다.
--   남긴 메시지는 두 사람 대화방에 「📮 음성사서함」 음성 메시지로 들어갑니다(보관은 대화방과 같음).
--   wafa_voicemails() — 나에게 온 음성사서함 목록(연락처 화면 맨 위 📮)
--   ⚠ 새 표는 만들지 않습니다. 읽기만 하는 함수 하나. 다시 돌려도 안전합니다. 맨 아래 'wafa voicemail ok'
-- =====================================================================

create or replace function public.wafa_voicemails(p_limit int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by at desc), '[]'::jsonb) from (
    select jsonb_build_object(
             'id', m.id, 'link_id', m.link_id, 'path', m.media_path, 'ms', m.duration_ms,
             'at', coalesce(m.sent_at, m.created_at),
             'name', coalesce(nullif(me.peer_label, ''), p.display_name, ''),
             'number', (select wn.number from wafa_numbers wn where wn.owner = o.account_id
                         order by wn.is_main desc, wn.acquired_at limit 1)) as x,
           coalesce(m.sent_at, m.created_at) as at
      from link_sides me
      join messages m on m.link_id = me.link_id and m.sender_side_id <> me.id
      join link_sides o on o.id = m.sender_side_id
      left join personas p on p.id = o.persona_id
     where me.account_id = auth.uid()
       and m.message_type = 'audio' and m.content like '📮%'
       and m.deleted_at is null
       and (m.expires_at is null or m.expires_at > now())
     order by coalesce(m.sent_at, m.created_at) desc
     limit least(greatest(coalesce(p_limit, 30), 1), 100)) z
$$;

revoke all on function public.wafa_voicemails(int) from public, anon;
grant execute on function public.wafa_voicemails(int) to authenticated;

select 'wafa voicemail ok' as result;
