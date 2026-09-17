-- Migration: Robust start_direct_call supporting Voryn ID and UUID candidates
CREATE OR REPLACE FUNCTION public.start_direct_call(candidate text, requested_type text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  target_uid uuid;
  new_call_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF requested_type NOT IN ('audio', 'video') THEN
    RAISE EXCEPTION 'Invalid call type';
  END IF;

  -- Match either by Voryn ID or by user UUID
  SELECT uid INTO target_uid FROM public.profiles
  WHERE lower(voryn_id) = lower(trim(leading '@' from candidate))
     OR uid::text = candidate;

  IF target_uid IS NULL OR target_uid = auth.uid() THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_blocks b
    WHERE (b.owner_uid = auth.uid() AND b.blocked_uid = target_uid)
       OR (b.owner_uid = target_uid AND b.blocked_uid = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Calling unavailable';
  END IF;

  INSERT INTO public.calls (initiated_by, call_type, status)
  VALUES (auth.uid(), requested_type, 'calling')
  RETURNING id INTO new_call_id;

  INSERT INTO public.call_participants (call_id, user_uid)
  VALUES (new_call_id, auth.uid()), (new_call_id, target_uid);

  RETURN new_call_id;
END;
$$;
