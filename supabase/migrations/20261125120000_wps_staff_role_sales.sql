-- WP-S migration A: the Sales Representative staff role value.
-- Specification: 03 §3, §4.1 (v0.5.8); decisions OI-77, OI-78, OI-84. Authorization: AUTH-005
-- (Phase 2 object (1)). WP-S directive item 2 (CURRENT-STATE §9).
--
-- A new enum value cannot be used in the transaction that adds it, so this statement is the
-- only content of this migration; migration B (20261125120100) uses the value.
-- Forward-only. Never edit this file after it is merged (T-MIG-02).

alter type public.staff_role add value if not exists 'sales';
