-- WP-C (2 of 3): storage policies for the new upload and quarantine paths (05 §4-§5;
-- AUTH-004, scoped Tier 2, local and CI).
--
-- Path layout inside the existing private bucket `project-assets`:
--   quarantine/<project_id>/<upload_id>   bytes as uploaded; never readable with a user JWT
--   <project_id>/assets/<upload_id>       released copy, written only after a clean scan
--
-- Combined-policy analysis (PostgreSQL: permissive policies are OR-ed, restrictive policies
-- are AND-ed with that result; a command with no permissive policy is denied):
--   Existing, unchanged (Phase 2):
--     project_assets_select      PERMISSIVE SELECT  bucket = project-assets and
--                                private.can_access_project_path(name)
--     project_assets_staff_aal2  RESTRICTIVE ALL    staff need aal2 and a live session
--   There is no permissive INSERT, UPDATE, or DELETE policy for `authenticated` or `anon`
--   on storage.objects, so neither role can write, copy, or move any object.
--   1. Quarantine paths start with the segment 'quarantine', which is not a project UUID,
--      so can_access_project_path() is false and project_assets_select never matches:
--      no client or staff JWT can read, list, sign, download, copy, or move them.
--   2. Released paths start with the project UUID, so project_assets_select lets active
--      members of that project (and staff at aal2) read them, exactly like any other
--      project path today. Only the server writes them, after a clean scan.
--   The two policies below are RESTRICTIVE and only narrow access. They keep 1 and 2 true
--   even if a future permissive policy is added (for example a client upload policy):
--     - nothing under quarantine/ is reachable with a user JWT, for any command;
--     - nothing under <project_id>/assets/ is writable with a user JWT.
--   They do not change the result for any existing path: quarantine/ was already
--   unreadable, and no path was writable. Neither existing policy is modified (AUTH-004).
--   The server uses the secret key (service_role, which bypasses RLS) only after the
--   database has authorized the action and recorded it (03 §9.1 rule 6).

create policy project_assets_quarantine_isolated on storage.objects as restrictive
  for all to authenticated, anon
  using (not (bucket_id = 'project-assets' and split_part(name, '/', 1) = 'quarantine'))
  with check (not (bucket_id = 'project-assets' and split_part(name, '/', 1) = 'quarantine'));

create policy project_assets_released_server_write_only on storage.objects as restrictive
  for insert to authenticated, anon
  with check (not (bucket_id = 'project-assets' and split_part(name, '/', 2) = 'assets'));

create policy project_assets_released_server_update_only on storage.objects as restrictive
  for update to authenticated, anon
  using (not (bucket_id = 'project-assets' and split_part(name, '/', 2) = 'assets'))
  with check (not (bucket_id = 'project-assets' and split_part(name, '/', 2) = 'assets'));

create policy project_assets_released_server_delete_only on storage.objects as restrictive
  for delete to authenticated, anon
  using (not (bucket_id = 'project-assets' and split_part(name, '/', 2) = 'assets'));
