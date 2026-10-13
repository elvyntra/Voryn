-- Migration: 202610080002_restrict_cancel_call_merge_to_service_role
-- Description: Restrict cancel_call_merge RPC execution to service_role to guarantee
-- all cancellations pass through the canonical cancel-call-merge Edge Function for LiveKit cleanup.
-- Checkpoint: MC-2B.1

revoke execute on function public.cancel_call_merge(uuid, text) from authenticated;
grant execute on function public.cancel_call_merge(uuid, text) to service_role;

