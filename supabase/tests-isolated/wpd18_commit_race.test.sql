-- WP-D18 isolated concurrent-commit verification (AUTH-007 Amendment 3, F4).
--
-- Runs ONLY inside the disposable database built by scripts/wpd18-isolated-commit-test.sh
-- (a scoped, allow-listed restore of the package-scope objects). It lives outside
-- supabase/tests, so `supabase test db` and `pnpm test:db` never run it against the shared
-- database. Two real sessions COMMIT two versions of one package; nothing is ever rolled back
-- by hand, no trigger is disabled, and the whole database is dropped afterwards by the script.
-- Output: TAP, a fixed plan; the script requires exactly the planned "ok" lines and no
-- "not ok" or "# SKIP".
\set ON_ERROR_STOP 1
set statement_timeout = '60s';

-- Refuse to run anywhere but a disposable copy, and only over TCP (dblink needs a password
-- connection to this server's own network address).
do $$
begin
  if current_database() !~ '^wpd18_iso_' then
    raise exception 'wpd18_commit_race.test.sql runs only in a wpd18_iso_* disposable database, not in %', current_database();
  end if;
  if inet_server_addr() is null then
    raise exception 'wpd18_commit_race.test.sql needs a TCP connection';
  end if;
end;
$$;

create temp table tap (n serial primary key, ok boolean not null, description text not null);
create function pg_temp.ok(p_ok boolean, p_description text) returns void language sql as $$
  insert into tap (ok, description) values (coalesce(p_ok, false), p_description);
$$;
create function pg_temp.conn() returns text language sql stable as $$
  select format('dbname=%s user=postgres password=postgres host=%s port=%s',
                current_database(), host(inet_server_addr()), inet_server_port());
$$;
create function pg_temp.canonical_sha(p_key text, p_version integer) returns text language sql stable as $$
  -- Independent recomputation of the canonical, length-prefixed serialization (AUTH-007).
  select encode(extensions.digest(convert_to('spotlight.package_scope.v1'
    || '|k' || octet_length(p_key) || ':' || p_key || '|v' || p_version || '|n' || count(*)
    || string_agg('|p' || position || ':' || octet_length(item_text) || ':' || item_text, '' order by position),
    'UTF8'), 'sha256'), 'hex')
  from private.billing_package_scope where package_key = p_key and scope_version = p_version;
$$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'no error';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end;
$$;

-- 1-5: no API role can use the objects (no privilege widening in the copy)
select pg_temp.ok(not has_function_privilege(r, 'private.create_package_scope_version(text,text[],boolean)', 'execute')
  and not has_function_privilege(r, 'private.current_package_scope(text)', 'execute')
  and not has_table_privilege(r, 'private.billing_package_scope', 'select,insert,update,delete,truncate')
  and not has_table_privilege(r, 'private.billing_package_scope_versions', 'select,insert,update,delete,truncate'),
  r || ' has no execute on the constructor or resolver and no privilege on either table')
from unnest(array['anon', 'authenticated', 'service_role', 'public']) r;
select pg_temp.ok((select string_agg(tgname::text || ':' || tgenabled::text, ',' order by tgname) from pg_trigger
  where tgrelid in ('private.billing_package_scope'::regclass, 'private.billing_package_scope_versions'::regclass) and not tgisinternal)
  = 'billing_package_scope_append_only:O,billing_package_scope_construction_guard:O,billing_package_scope_fixture_guard:O,billing_package_scope_no_truncate:O,billing_package_scope_versions_append_only:O,billing_package_scope_versions_construction_guard:O,billing_package_scope_versions_no_truncate:O',
  'all seven protection triggers are present and enabled before the race');

-- 6-13: A creates version 2 and holds; B waits; A commits; B commits version 3
do $$
declare
  v_a text;
  v_b text;
  v_b_pid integer;
  v_other_pid integer;
  v_headers integer;
  v_items integer;
  v_resolved text;
  v_waited boolean := false;
  v_busy integer;
begin
  perform extensions.dblink_connect('wpd18_a', pg_temp.conn());
  perform extensions.dblink_connect('wpd18_b', pg_temp.conn());
  perform extensions.dblink_connect('wpd18_o', pg_temp.conn());
  perform extensions.dblink_exec(c, 'set statement_timeout = ''20s''; set lock_timeout = ''15s''')
    from unnest(array['wpd18_a', 'wpd18_b', 'wpd18_o']) c;
  select pid into v_b_pid from extensions.dblink('wpd18_b', 'select pg_backend_pid()') t(pid integer);
  select pid into v_other_pid from extensions.dblink('wpd18_o', 'select pg_backend_pid()') t(pid integer);
  perform pg_temp.ok(v_b_pid is not null and v_b_pid <> pg_backend_pid() and v_other_pid <> v_b_pid,
    'real second and third sessions answer from their own backends');

  perform extensions.dblink_exec('wpd18_a', 'begin');
  select v into v_a from extensions.dblink('wpd18_a',
    $q$select (private.create_package_scope_version('advanced',
      array['TEST FIXTURE — NOT A DELIVERABLE (isolated commit a)'], true)) ->> 'scope_version'$q$) t(v text);

  -- Uncommitted version 2 is invisible to an independent session.
  select h, i, r into v_headers, v_items, v_resolved from extensions.dblink('wpd18_o',
    $q$select (select count(*) from private.billing_package_scope_versions where package_key = 'advanced' and scope_version = 2)::integer,
              (select count(*) from private.billing_package_scope where package_key = 'advanced' and scope_version = 2)::integer,
              (select string_agg(scope_version || ':' || item_position, ',' order by item_position) from private.current_package_scope('advanced'))$q$)
    t(h integer, i integer, r text);
  perform pg_temp.ok(v_headers = 0, 'an independent session sees no header of the uncommitted version 2');
  perform pg_temp.ok(v_items = 0, 'an independent session sees no item of the uncommitted version 2');
  perform pg_temp.ok(v_resolved = '1:1,1:2,1:3', 'an independent session still resolves version 1 (3 items) while version 2 is uncommitted');

  perform extensions.dblink_exec('wpd18_b', 'begin');
  perform extensions.dblink_send_query('wpd18_b',
    $q$select (private.create_package_scope_version('advanced',
      array['TEST FIXTURE — NOT A DELIVERABLE (isolated commit b1)', 'TEST FIXTURE — NOT A DELIVERABLE (isolated commit b2)'], true)) ->> 'scope_version'$q$);
  -- Deterministic, bounded observation: B's backend has an ungranted advisory-lock request.
  for i in 1..100 loop
    if exists (select 1 from pg_locks where pid = v_b_pid and locktype = 'advisory' and not granted) then
      v_waited := true;
      exit;
    end if;
    perform pg_sleep(0.05);
  end loop;
  v_busy := extensions.dblink_is_busy('wpd18_b');
  perform pg_temp.ok(v_waited, 'session B waits on the per-package advisory lock (ungranted in pg_locks, bounded poll)');
  perform pg_temp.ok(v_busy = 1, 'session B is still busy while A holds version 2');
  perform pg_temp.ok(v_a = '2', 'session A built version 2');

  perform extensions.dblink_exec('wpd18_a', 'commit');
  select v into v_b from extensions.dblink_get_result('wpd18_b') t(v text);
  perform count(*) from extensions.dblink_get_result('wpd18_b') t(v text);
  perform extensions.dblink_exec('wpd18_b', 'commit');
  perform pg_temp.ok(v_b = '3', 'after A commits, session B builds and commits version 3');
  perform extensions.dblink_disconnect(c) from unnest(array['wpd18_a', 'wpd18_b', 'wpd18_o']) c;
end;
$$;

-- 14-17: committed state
select pg_temp.ok((select string_agg(scope_version || ':' || item_count || ':' || is_test_fixture, ',' order by scope_version)
  from private.billing_package_scope_versions where package_key = 'advanced') = '1:3:true,2:1:true,3:2:true',
  'headers are exactly versions 1, 2 and 3 (3, 1 and 2 items), all fixtures: no duplicate, gap or extra version');
select pg_temp.ok((select bool_and(n = h.item_count and lo = 1 and hi = h.item_count)
  from private.billing_package_scope_versions h
  join (select scope_version, count(*)::integer n, min(position)::integer lo, max(position)::integer hi
          from private.billing_package_scope where package_key = 'advanced' group by scope_version) s using (scope_version)
  where h.package_key = 'advanced') and (select count(distinct scope_version) from private.billing_package_scope where package_key = 'advanced') = 3,
  'every version has contiguous positions 1..n and the item count of its header');
select pg_temp.ok((select bool_and(h.content_sha256 = pg_temp.canonical_sha(h.package_key, h.scope_version))
  from private.billing_package_scope_versions h where h.package_key = 'advanced'),
  'every header hash equals an independent recomputation of the canonical serialization');
select pg_temp.ok((select string_agg(scope_version || ':' || item_position || ':' || item_text, '|' order by item_position)
  from private.current_package_scope('advanced'))
  = '3:1:TEST FIXTURE — NOT A DELIVERABLE (isolated commit b1)|3:2:TEST FIXTURE — NOT A DELIVERABLE (isolated commit b2)',
  'the resolver returns version 3, positions 1 and 2, with the exact item texts');

-- 18-23: sealed-version immutability after the commits (every attempt fails; nothing persists)
do $$
declare
  v_error text := 'no error';
begin
  perform set_config('wpd18.scope_construction', 'advanced:2', true);
  begin
    insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture)
    values ('advanced', 2, 2, 'TEST FIXTURE — NOT A DELIVERABLE (late)', true);
  exception when others then
    v_error := sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('wpd18.scope_construction', '', true);
  perform pg_temp.ok(v_error = '42501 package scope version advanced:2 is sealed',
    'a forged-marker addition to committed version 2 is rejected (sealed)');
end;
$$;
select pg_temp.ok(pg_temp.error_of($$ update private.billing_package_scope_versions set item_count = 9
  where package_key = 'advanced' and scope_version = 3 $$) = '42501 billing_package_scope_versions is insert-only',
  'the committed version 3 header cannot be updated');
select pg_temp.ok(pg_temp.error_of($$ delete from private.billing_package_scope_versions
  where package_key = 'advanced' and scope_version = 3 $$) = '42501 billing_package_scope_versions is insert-only',
  'the committed version 3 header cannot be deleted');
select pg_temp.ok(pg_temp.error_of($$ truncate private.billing_package_scope_versions $$) like '42501 %',
  'the headers cannot be truncated');
select pg_temp.ok(pg_temp.error_of($$ update private.billing_package_scope set item_text = 'TEST FIXTURE — NOT A DELIVERABLE (changed)'
  where package_key = 'advanced' and scope_version = 3 $$) = '42501 billing_package_scope is insert-only',
  'a committed item cannot be updated');
select pg_temp.ok((select string_agg(tgname::text || ':' || tgenabled::text, ',' order by tgname) from pg_trigger
  where tgrelid in ('private.billing_package_scope'::regclass, 'private.billing_package_scope_versions'::regclass) and not tgisinternal)
  = 'billing_package_scope_append_only:O,billing_package_scope_construction_guard:O,billing_package_scope_fixture_guard:O,billing_package_scope_no_truncate:O,billing_package_scope_versions_append_only:O,billing_package_scope_versions_construction_guard:O,billing_package_scope_versions_no_truncate:O',
  'all seven protection triggers are still enabled after the race');

-- 24-25: bounded failure. A holds and never commits; B must fail with a lock timeout.
do $$
declare
  t0 timestamptz := clock_timestamp();
  v_error text := 'no error';
begin
  perform extensions.dblink_connect('wpd18_ta', pg_temp.conn());
  perform extensions.dblink_connect('wpd18_tb', pg_temp.conn());
  perform extensions.dblink_exec('wpd18_ta', 'set statement_timeout = ''20s''');
  perform extensions.dblink_exec('wpd18_ta', 'begin');
  perform * from extensions.dblink('wpd18_ta',
    $q$select private.create_package_scope_version('prestige', array['TEST FIXTURE — NOT A DELIVERABLE (held)'], true)::text$q$) t(v text);
  perform extensions.dblink_exec('wpd18_tb', 'set lock_timeout = ''2s''');
  begin
    perform * from extensions.dblink('wpd18_tb',
      $q$select private.create_package_scope_version('prestige', array['TEST FIXTURE — NOT A DELIVERABLE (blocked)'], true)::text$q$) t(v text);
  exception when others then
    v_error := sqlstate || ' ' || sqlerrm;
  end;
  perform pg_temp.ok(v_error like '%lock timeout%' and clock_timestamp() - t0 < interval '5 seconds',
    'a creation blocked by a transaction that never commits fails with a lock timeout within 5 s (' || v_error || ')');
  perform extensions.dblink_disconnect('wpd18_ta');
  perform extensions.dblink_disconnect('wpd18_tb');
end;
$$;
select pg_sleep(0.2);
select pg_temp.ok((select string_agg(scope_version::text, ',' order by scope_version)
  from private.billing_package_scope_versions where package_key = 'prestige') = '1',
  'the held, uncommitted prestige version rolled back when its session ended');

-- TAP output
select '1..25';
select case when ok then 'ok ' else 'not ok ' end || n || ' - ' || description from tap order by n;
select case when count(*) = 25 then '# 25 assertions recorded' else 'not ok 0 - expected 25 recorded assertions, got ' || count(*) end from tap;
