-- =====================================================================
-- 부름 서버 — 지금 관리자 계정 찾기 (읽기만 합니다. 표 · 계정은 바꾸지 않습니다)
--   부름 Supabase SQL Editor 에서 Run → 결과(login · how)를 캡처해 보내 주세요.
--   login 이 닉네임입니다(매출 센터 「부름 서버」 칸에 그대로 넣으면 됩니다).
-- =====================================================================
drop table if exists _weave_admins;
create temp table _weave_admins(login text, how text);
do $$
declare u record; v boolean;
begin
  for u in select x.id, x.email from auth.users x where coalesce((to_jsonb(x) ->> 'is_anonymous')::boolean, false) = false loop
    perform set_config('request.jwt.claims', json_build_object('sub', u.id, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', u.id::text, true);
    v := false;
    begin execute 'select coalesce(public.stats_is_admin(), false)' into v; exception when others then v := false; end;
    if v then insert into _weave_admins values (u.email, '매출 · 통계 관리자'); end if;
  end loop;
end $$;
select coalesce((select convert_from(string_agg(case when t.m[1] is not null then decode(substr(t.m[1], 2), 'hex') else convert_to(t.m[2], 'UTF8') end, ''::bytea order by t.o), 'UTF8')
                   from regexp_matches(replace(a.login, '@u.alias.internal', ''), '(%[0-9A-Fa-f]{2})|([^%]+)', 'g') with ordinality as t(m, o)), a.login) as login, a.how
  from _weave_admins a
union all
select '-- 관리자 판정 규칙 --', pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'stats_is_admin';
