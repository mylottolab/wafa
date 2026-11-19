-- =====================================================================
-- 와파 WAFA — 번호로 걸기 (2026-11-20) · 부름 Supabase 에서 Run
--
--   wafa_dial(번호, 'voice'|'video'|'chat')
--     · 와파 번호 주인을 찾아 바로 이어 줍니다(번호 전화 = 연결 요청 없이 바로) — 부름번호 「모두 받기」(bn_dial)와 같은 길:
--       이미 이어진 사이면 그 대화방, 아니면 1회용 초대(invites) → use_invite 로 대화방(links)을 만듭니다
--     · 통화(음성 · 영상)는 구독과 남은 시간이 있어야(wafa_can_call). 문자는 무료
--     · 없는 번호를 자꾸 누르면 잠시 쉼 — 부름과 같은 기록(burum_dial_log)을 함께 씁니다
--     · 상대가 [번호 전화]를 꺼 두었거나 나를 막아 두었으면 'off'
--   wafa_contacts() — 와파 번호로 이어진 사람(연락처 화면)
--   ⚠ 01 · 02 · 03 다음에 통째로 Run. 다시 돌려도 안전합니다. 맨 아래 'wafa dial ok'
-- =====================================================================

/* 이 사람의 별칭 하나(없으면 기본 별칭을 만들어 둠) — 대화방은 별칭끼리 이어집니다 */
create or replace function public._wafa_persona(p_user uuid) returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare v uuid; nm text;
begin
  select id into v from personas where account_id = p_user order by is_default desc nulls last, created_at limit 1;
  if v is not null then return v; end if;
  select split_part(email, '@', 1) into nm from auth.users where id = p_user;
  insert into personas(account_id, display_name, is_default) values (p_user, coalesce(nullif(nm, ''), 'WAFA'), true) returning id into v;
  return v;
end $$;

create or replace function public.wafa_dial(p_number text, p_kind text default 'voice', p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_me uuid := auth.uid(); n text := regexp_replace(coalesce(p_number, ''), '[^0-9]', '', 'g');
        w wafa_numbers; a wafa_accounts; c jsonb; v_link uuid; v_my uuid; v_their uuid; v_code text; v_out jsonb;
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
  if v_link is not null then return jsonb_build_object('ok', true, 'state', 'linked', 'link_id', v_link); end if;

  /* 새로 잇기 — 상대 별칭이 내준 1회용 초대를 내 별칭으로 바로 씀 */
  v_my := _wafa_persona(v_me);
  v_their := _wafa_persona(w.owner);
  insert into invites(code, issuer_account_id, issuer_persona_id, memo, max_uses, expires_at)
  values (substr(replace(gen_random_uuid()::text, '-', ''), 1, 16), w.owner, v_their,
          '와파 번호 ' || substr(n, 1, 4) || '-' || substr(n, 5, 3) || '-' || substr(n, 8, 3), 1, now() + interval '1 day')
  returning code into v_code;
  v_out := use_invite(v_code, v_my, null);
  if not coalesce((v_out->>'ok')::boolean, false) then return v_out; end if;
  return jsonb_build_object('ok', true, 'state', 'linked', 'link_id', v_out->>'link_id', 'new', true);
end $$;

/* 연락처 — 와파 번호를 가진 사람과 이어진 대화방 (최근 순) */
create or replace function public.wafa_contacts() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by at desc nulls last), '[]'::jsonb) from (
    select distinct on (o.account_id)
           jsonb_build_object('link_id', l.id, 'number', wn.number,
                              'name', coalesce(nullif(m.peer_label, ''), p.display_name, ''), 'photo', p.avatar_url) as x,
           l.last_activity_at as at
      from link_sides m
      join links l on l.id = m.link_id and l.status = 'active' and coalesce(l.kind, 'pair') = 'pair'
      join link_sides o on o.link_id = l.id and o.account_id <> m.account_id
      join lateral (select number from wafa_numbers where owner = o.account_id order by is_main desc, acquired_at limit 1) wn on true
      left join personas p on p.id = o.persona_id
     where m.account_id = auth.uid()
     order by o.account_id, l.last_activity_at desc nulls last) z
$$;

/* 통화가 끝나면 건 사람의 이번 달 사용량에 더함 (받은 통화는 무료) — 한 통화 최대 4시간으로 자름 */
create or replace function public.wafa_call_used(p_video boolean, p_sec int) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if not exists (select 1 from wafa_accounts where user_id = auth.uid()) then return jsonb_build_object('ok', true, 'skip', true); end if;
  perform wafa_add_usage(auth.uid(), coalesce(p_video, false), least(greatest(coalesce(p_sec, 0), 0), 14400));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public._wafa_persona(uuid) from public, anon, authenticated;
grant execute on function public.wafa_call_used(boolean, int) to authenticated;
grant execute on function public.wafa_dial(text, text, text), public.wafa_contacts() to authenticated;

select 'wafa dial ok' as result;
