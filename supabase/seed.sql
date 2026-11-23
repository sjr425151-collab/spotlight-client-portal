-- Synthetic local/CI seed only (spec 03 §15). Never real customer data.
-- Reserved example.test addresses. Applied by `supabase start` and `supabase db reset`.
-- Users are inserted directly, so the before-user-created hook does not run here.

create function pg_temp.seed_user(p_id uuid, p_email text) returns void language sql as $$
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, reauthentication_token, phone_change, phone_change_token
  ) values (
    '00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email, '',
    now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(),
    '', '', '', '', '', '', '', ''
  );
  insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), p_id::text, p_id,
          jsonb_build_object('sub', p_id::text, 'email', p_email, 'email_verified', true),
          'email', now(), now(), now());
$$;

select pg_temp.seed_user('00000000-0000-4000-8000-000000000001', 'owner@example.test');
select pg_temp.seed_user('00000000-0000-4000-8000-000000000002', 'admin@example.test');
select pg_temp.seed_user('00000000-0000-4000-8000-0000000000a1', 'client.a@example.test');
select pg_temp.seed_user('00000000-0000-4000-8000-0000000000b1', 'client.b@example.test');

insert into public.profiles (id, email, full_name) values
  ('00000000-0000-4000-8000-000000000001', 'owner@example.test', 'Synthetic Owner'),
  ('00000000-0000-4000-8000-000000000002', 'admin@example.test', 'Synthetic Admin'),
  ('00000000-0000-4000-8000-0000000000a1', 'client.a@example.test', 'Synthetic Client A'),
  ('00000000-0000-4000-8000-0000000000b1', 'client.b@example.test', 'Synthetic Client B');

insert into public.staff_roles (user_id, role) values
  ('00000000-0000-4000-8000-000000000001', 'owner'),
  ('00000000-0000-4000-8000-000000000002', 'admin');

-- created_by is forced to auth.uid() by trigger; act as the Owner for these inserts.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);

insert into public.client_businesses (id, legal_name, display_name) values
  ('10000000-0000-4000-8000-0000000000a0', 'Synthetic Business A LLC', 'Business A'),
  ('10000000-0000-4000-8000-0000000000b0', 'Synthetic Business B LLC', 'Business B');
insert into public.projects (id, client_business_id, name) values
  ('20000000-0000-4000-8000-0000000000a0', '10000000-0000-4000-8000-0000000000a0', 'Project A website'),
  ('20000000-0000-4000-8000-0000000000b0', '10000000-0000-4000-8000-0000000000b0', 'Project B website');
insert into public.project_memberships (project_id, user_id) values
  ('20000000-0000-4000-8000-0000000000a0', '00000000-0000-4000-8000-0000000000a1'),
  ('20000000-0000-4000-8000-0000000000b0', '00000000-0000-4000-8000-0000000000b1');

select set_config('request.jwt.claims', '', true);
