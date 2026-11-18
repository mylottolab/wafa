-- WAFA 앱 화면용 (2026-11-19) — 부름 프로젝트에 01 · 02 다음으로 Run. 다시 돌려도 안전합니다.
--   · wafa_me()          와파 홈 · 번호 · 요금 · 사용량 화면이 한 번에 읽는 "내 정보"
--   · wafa_set_prefs()   처음 설정(메인 고르기 · 언어 · 모르는 번호 조용히)
--   · wafa_usage_history() 지난 6개월 사용량

alter table public.wafa_accounts add column if not exists setup_done boolean not null default false;   -- 처음 설정(메인 고르기)을 마쳤나

create or replace function public.wafa_set_prefs(p_main text default null, p_lang text default null, p_quiet boolean default null,
                                                 p_open boolean default null, p_private boolean default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if p_main is not null and p_main not in ('open','private') then return jsonb_build_object('ok', false, 'error', 'bad_main'); end if;
  if p_lang is not null and p_lang not in ('ko','en') then return jsonb_build_object('ok', false, 'error', 'bad_lang'); end if;
  insert into wafa_accounts(user_id) values (me) on conflict do nothing;
  update wafa_accounts set
    main_line = coalesce(p_main, main_line), lang = coalesce(p_lang, lang), quiet_unknown = coalesce(p_quiet, quiet_unknown),
    open_on = coalesce(p_open, open_on), private_on = coalesce(p_private, private_on), last_seen = now(),
    setup_done = setup_done or p_main is not null
  where user_id = me;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.wafa_me()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me uuid := auth.uid(); a record; s record;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  update wafa_accounts set last_seen = now() where user_id = me;            -- 2년 안 열면 일반 번호 회수 규칙용
  select * into a from wafa_accounts where user_id = me;
  select * into s from wafa_subs where user_id = me;
  return jsonb_build_object('ok', true,
    'setup', coalesce(a.setup_done, false),
    'prefs', case when a.user_id is null then null else jsonb_build_object('main', a.main_line, 'lang', a.lang,
              'quiet', a.quiet_unknown, 'open', a.open_on, 'private', a.private_on) end,
    'sub', case when s.user_id is null then null else jsonb_build_object('product', s.product, 'status', s.status,
              'auto', s.auto_renew, 'until', s.expires_at, 'store', s.store) end,
    'quota', wafa_quota(me),
    'numbers', coalesce((select jsonb_agg(jsonb_build_object('number', number, 'shown', wafa_shown(number), 'kind', kind,
                 'grade', grade, 'main', is_main) order by is_main desc, acquired_at) from wafa_numbers where owner = me), '[]'::jsonb),
    'credits', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind) order by created_at)
                 from wafa_number_credits where owner = me and used_at is null), '[]'::jsonb),
    'free_used', exists (select 1 from wafa_numbers where owner = me and kind = 'free'),
    'units', coalesce((select units from wafa_addon_wallet where user_id = me), 0),
    'holds', coalesce((select jsonb_agg(jsonb_build_object('number', number, 'shown', wafa_shown(number), 'code', code,
                 'kind', kind, 'until', expires_at) order by expires_at) from wafa_holds where holder = me and expires_at > now()), '[]'::jsonb));
end $$;

create or replace function public.wafa_usage_history()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('ym', ym, 'voice_min', ceil(voice_sec/60.0), 'video_min', ceil(video_sec/60.0)) order by ym desc), '[]'::jsonb)
  from (select * from wafa_usage where user_id = auth.uid() order by ym desc limit 6) x $$;

grant execute on function public.wafa_set_prefs(text,text,boolean,boolean,boolean), public.wafa_me(), public.wafa_usage_history() to authenticated;

select 'wafa me ok' as result;
