-- AUTH-028 (OI-134): the staff operational queue's authorization gate, tested directly.
-- public.operational_queue() returns items only to a staff member (Owner or Admin) at aal2 in a
-- live session (private.wpc_is_staff_aal2()). Every other caller gets an empty result, not an
-- error. This file proves both sides on ONE qualifying dataset in ONE transaction, so an empty
-- refusal can never pass because the dataset is empty:
--   (1) a Sales Representative assigned to the project's customer, at aal2: empty;
--   (2) a client member of the project, at aal1 and at aal2: empty;
--   (3) the Owner and an Admin, each at aal1: empty;
--   (4) positive control: an Admin and the Owner, each at aal2, see the project's items, and the
--       Admin's billing-hold item is the OI-72 `billing_related_operational_hold` form.
-- Synthetic data only, built through the seed and the existing Owner functions; the whole file
-- rolls back. No function, grant, policy or role is changed.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(14);

-- The 220 pattern: a live session at the requested assurance level (a verified factor at aal2).
create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'pgtap', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_uid, 'role', 'authenticated', 'aal', p_aal, 'session_id', v_sid,
    'amr', jsonb_build_array(jsonb_build_object('method', 'totp',
             'timestamp', extract(epoch from now() - interval '1 minute')::bigint)))::text, true);
  set local role authenticated;
end;
$$;

-- The queue as the given caller: every item, and this project's items.
create function pg_temp.queue_as(p_uid uuid, p_aal text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as(p_uid, p_aal);
  v := coalesce((select jsonb_agg(q order by o) from public.operational_queue() with ordinality t (q, o)), '[]'::jsonb);
  reset role;
  return v;
end;
$$;
create function pg_temp.project_items(p_items jsonb) returns jsonb language sql as $$
  select coalesce(jsonb_agg(i), '[]'::jsonb) from jsonb_array_elements(p_items) i
   where i ->> 'project_id' = '20000000-0000-4000-8000-0000000000a0';
$$;

-- ---------------------------------------------------------------------------
-- The qualifying dataset: seed Project A (client A is its member), with an Owner-placed manual
-- billing hold and the seed Sales Representative assigned to it, through the existing functions.
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.place_billing_hold('20000000-0000-4000-8000-0000000000a0', 'owner_manual_hold',
    'Synthetic hold for AUTH-028') ->> 'ok', 'true',
  'setup: the Owner places a manual billing hold on Project A');
select is(public.assign_sales_representative('20000000-0000-4000-8000-0000000000a0',
    '00000000-0000-4000-8000-000000000005', 'Synthetic assignment for AUTH-028') ->> 'ok', 'true',
  'setup: the seed Sales Representative is assigned to Project A');
reset role;
select ok(exists (select 1 from public.project_memberships
                   where project_id = '20000000-0000-4000-8000-0000000000a0'
                     and user_id = '00000000-0000-4000-8000-0000000000a1')
  and exists (select 1 from public.project_sales_assignments
               where project_id = '20000000-0000-4000-8000-0000000000a0'
                 and sales_user_id = '00000000-0000-4000-8000-000000000005' and active)
  and exists (select 1 from public.billing_holds
               where project_id = '20000000-0000-4000-8000-0000000000a0' and cleared_at is null),
  'setup: client A is a member, the Sales Representative is actively assigned, and the hold is active');

create temp table results (caller text primary key, items jsonb);
insert into results values
  ('admin_aal2', pg_temp.queue_as('00000000-0000-4000-8000-000000000002', 'aal2')),
  ('owner_aal2', pg_temp.queue_as('00000000-0000-4000-8000-000000000001', 'aal2')),
  ('sales_aal2', pg_temp.queue_as('00000000-0000-4000-8000-000000000005', 'aal2')),
  ('client_aal1', pg_temp.queue_as('00000000-0000-4000-8000-0000000000a1', 'aal1')),
  ('client_aal2', pg_temp.queue_as('00000000-0000-4000-8000-0000000000a1', 'aal2')),
  ('owner_aal1', pg_temp.queue_as('00000000-0000-4000-8000-000000000001', 'aal1')),
  ('admin_aal1', pg_temp.queue_as('00000000-0000-4000-8000-000000000002', 'aal1'));

-- ---------------------------------------------------------------------------
-- (4) Positive control: staff at aal2 see the qualifying project's items (same dataset, same
--     transaction), with the OI-72 forms.
-- ---------------------------------------------------------------------------
select ok(jsonb_array_length(pg_temp.project_items((select items from results where caller = 'admin_aal2'))) > 0,
  '(4) positive control: an Admin at aal2 sees Project A''s queue items');
select is((select i -> 'detail' from jsonb_array_elements(pg_temp.project_items(
             (select items from results where caller = 'admin_aal2'))) i
            where i ->> 'queue' = 'blocked_by_hold' and i -> 'detail' ->> 'kind' = 'billing'),
  '{"hold": "billing_related_operational_hold", "kind": "billing", "owner_intervention_required": true}'::jsonb,
  '(4) OI-72: the Admin''s billing-hold item is exactly the billing_related_operational_hold form (no hold type)');
select ok(jsonb_array_length(pg_temp.project_items((select items from results where caller = 'owner_aal2'))) > 0,
  '(4) positive control: the Owner at aal2 sees Project A''s queue items');
select ok((select (i -> 'detail' -> 'holds') ? 'owner_manual_hold' from jsonb_array_elements(pg_temp.project_items(
             (select items from results where caller = 'owner_aal2'))) i
            where i ->> 'queue' = 'blocked_by_hold' and i -> 'detail' ->> 'kind' = 'billing'),
  '(4) OI-72: the Owner''s billing-hold item names the hold type (owner_manual_hold)');

-- ---------------------------------------------------------------------------
-- (1) to (3): every other caller gets an empty result.
-- ---------------------------------------------------------------------------
select is((select items from results where caller = 'sales_aal2'), '[]'::jsonb,
  '(1) a Sales Representative assigned to the project, at aal2, gets an empty queue');
select is((select items from results where caller = 'client_aal1'), '[]'::jsonb,
  '(2) a client member of the project at aal1 gets an empty queue');
select is((select items from results where caller = 'client_aal2'), '[]'::jsonb,
  '(2) a client member of the project at aal2 gets an empty queue');
select is((select items from results where caller = 'owner_aal1'), '[]'::jsonb,
  '(3) the Owner at aal1 gets an empty queue');
select is((select items from results where caller = 'admin_aal1'), '[]'::jsonb,
  '(3) an Admin at aal1 gets an empty queue');

-- The refusals are a property of the caller, not of the data: after every refused call, the
-- same dataset still yields the same items for the staff callers at aal2.
select is(pg_temp.queue_as('00000000-0000-4000-8000-000000000002', 'aal2'),
  (select items from results where caller = 'admin_aal2'),
  '(4) after the refused calls, an Admin at aal2 still sees the same items');
select is(pg_temp.queue_as('00000000-0000-4000-8000-000000000001', 'aal2'),
  (select items from results where caller = 'owner_aal2'),
  '(4) after the refused calls, the Owner at aal2 still sees the same items');

select * from finish();
rollback;
