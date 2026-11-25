-- WP-D18 isolated concurrent-commit verification (AUTH-007 Amendment 3, F3).
-- Read-only. Run unchanged against the source database and the disposable copy; the output
-- must be byte-identical. Section "fp" is the catalog fingerprint of the tested objects
-- (exactly 67 lines; ACLs normalized with acldefault(), because pg_dump omits an ACL equal to
-- the default). Section "state" is the package-scope state (headers, items, resolved scope,
-- totals and classification). scripts/wpd18-isolated-commit-test.sh checks both.
with t(rel) as (values ('private.billing_packages'::regclass), ('private.billing_package_scope'::regclass),
                       ('private.billing_package_scope_versions'::regclass), ('private.environment_settings'::regclass)),
f(fn) as (select p.oid from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname in
  ('create_package_scope_version','current_package_scope','billing_package_scope_construction_guard',
   'billing_package_scope_fixture_guard','app_environment','insert_only','audit_events_immutable'))
select 'fp' s, 'schema' k, n.nspname || ' owner=' || pg_get_userbyid(n.nspowner) || ' acl=' || coalesce(n.nspacl, acldefault('n', n.nspowner))::text from pg_namespace n where n.nspname = 'private'
union all select 'fp', 'table', c.oid::regclass::text || ' owner=' || pg_get_userbyid(c.relowner) || ' acl=' || coalesce(c.relacl, acldefault('r', c.relowner))::text || ' rls=' || c.relrowsecurity from pg_class c join t on t.rel = c.oid
union all select 'fp', 'column', a.attrelid::regclass::text || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' notnull=' || a.attnotnull || ' default=' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-') || ' acl=' || coalesce(a.attacl::text, '-')
  from pg_attribute a join t on t.rel = a.attrelid left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attnum > 0 and not a.attisdropped
union all select 'fp', 'constraint', k.conrelid::regclass::text || ' ' || k.conname || ' ' || pg_get_constraintdef(k.oid) from pg_constraint k join t on t.rel = k.conrelid
union all select 'fp', 'index', pg_get_indexdef(i.indexrelid) from pg_index i join t on t.rel = i.indrelid
union all select 'fp', 'trigger', pg_get_triggerdef(g.oid) || ' enabled=' || g.tgenabled::text from pg_trigger g join t on t.rel = g.tgrelid where not g.tgisinternal
union all select 'fp', 'function', p.oid::regprocedure::text || ' owner=' || pg_get_userbyid(p.proowner) || ' secdef=' || p.prosecdef || ' config=' || coalesce(p.proconfig::text, '-') || ' acl=' || coalesce(p.proacl, acldefault('f', p.proowner))::text || ' def_md5=' || md5(pg_get_functiondef(p.oid)) from pg_proc p join f on f.fn = p.oid
union all select 'fp', 'privilege', r || ' exec_constructor=' || has_function_privilege(r, 'private.create_package_scope_version(text,text[],boolean)', 'execute') || ' exec_resolver=' || has_function_privilege(r, 'private.current_package_scope(text)', 'execute') || ' sel_items=' || has_table_privilege(r, 'private.billing_package_scope', 'select') || ' ins_items=' || has_table_privilege(r, 'private.billing_package_scope', 'insert') || ' sel_headers=' || has_table_privilege(r, 'private.billing_package_scope_versions', 'select') || ' ins_headers=' || has_table_privilege(r, 'private.billing_package_scope_versions', 'insert') from unnest(array['anon', 'authenticated', 'service_role', 'public']) r
union all select 'fp', 'classification', private.app_environment()
order by 1, 2, 3;
select 'state', 'header', package_key || '|' || scope_version || '|' || item_count || '|' || content_sha256 || '|' || is_test_fixture
  from private.billing_package_scope_versions
union all select 'state', 'item', package_key || '|' || scope_version || '|' || position || '|' || is_test_fixture || '|'
  || encode(extensions.digest(convert_to(item_text, 'UTF8'), 'sha256'), 'hex')
  from private.billing_package_scope
union all select 'state', 'resolved', r.package_key || '|' || r.v || '|' || r.n || '|' || r.d
  from (select p.package_key, s.scope_version v, count(*) n,
               md5(string_agg(s.item_position || ':' || s.item_text, '|' order by s.item_position)) d
          from private.billing_packages p cross join lateral private.current_package_scope(p.package_key) s
         group by p.package_key, s.scope_version) r
union all select 'state', 'totals', (select count(*) from private.billing_packages) || '|'
  || (select count(*) from private.billing_package_scope_versions) || '|' || (select count(*) from private.billing_package_scope)
order by 1, 2, 3;
