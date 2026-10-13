import { createClient } from 'npm:@supabase/supabase-js@2';
import { RoomServiceClient } from 'npm:livekit-server-sdk@2.19.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function getEnvironmentKey(name: string): string | null {
  const value = Deno.env.get(name);
  if (!value) return null;

  try {
    const parsed = JSON.parse(value) as Record<string, string>;
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch (_) {
    return value;
  }
}

function getLiveKitHttpUrl(url: string): string {
  return url.replace(/^wss:\/\//i, 'https://').replace(/^ws:\/\//i, 'http://');
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authorization = request.headers.get('Authorization');
    if (!authorization) {
      return Response.json(
        { error: 'Authentication is required.' },
        { status: 401, headers: corsHeaders },
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const publishableKey =
      getEnvironmentKey('SUPABASE_PUBLISHABLE_KEYS') ??
      Deno.env.get('SUPABASE_ANON_KEY');
    const secretKey =
      getEnvironmentKey('SUPABASE_SECRET_KEYS') ??
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const livekitUrl = Deno.env.get('LIVEKIT_URL');
    const livekitApiKey = Deno.env.get('LIVEKIT_API_KEY');
    const livekitApiSecret = Deno.env.get('LIVEKIT_API_SECRET');

    if (
      !supabaseUrl ||
      !publishableKey ||
      !secretKey ||
      !livekitUrl ||
      !livekitApiKey ||
      !livekitApiSecret
    ) {
      throw new Error('The call service is not configured.');
    }

    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return Response.json(
        { error: 'Your session has expired. Please sign in again.' },
        { status: 401, headers: corsHeaders },
      );
    }

    const body = await request.json().catch(() => ({}));
    const mergeId = body.mergeOperationId ?? body.mergeOpId;
    const reason = body.reason ?? 'client_aborted';

    if (typeof mergeId !== 'string' || !/^[0-9a-f-]{36}$/i.test(mergeId)) {
      return Response.json(
        { error: 'Invalid merge operation ID.' },
        { status: 400, headers: corsHeaders },
      );
    }

    const admin = createClient(supabaseUrl, secretKey);

    const { data: op, error: opErr } = await admin
      .from('call_merge_operations')
      .select('*')
      .eq('id', mergeId)
      .maybeSingle();

    if (opErr || !op) {
      return Response.json(
        { error: 'Merge operation not found.' },
        { status: 404, headers: corsHeaders },
      );
    }

    // Committed merge cannot be cancelled
    if (op.status === 'committed') {
      return Response.json(
        {
          error: 'Cannot cancel an already committed merge operation.',
          result: 'rejected',
          reason: 'already_committed',
          conferenceCallId: op.primary_call_id,
        },
        { status: 400, headers: corsHeaders },
      );
    }

    // Verify requester is merge initiator
    if (op.initiated_by !== user.id) {
      return Response.json(
        { error: 'Unauthorized: only merge initiator may cancel operation.' },
        { status: 403, headers: corsHeaders },
      );
    }

    // Execute cancel_call_merge RPC through trusted backend
    const { data: rpcResult, error: rpcError } = await admin.rpc(
      'cancel_call_merge',
      {
        p_merge_operation_id: op.id,
        p_reason: reason,
      },
    );

    if (rpcError) {
      console.error('cancel_call_merge RPC error:', rpcError);
      return Response.json(
        { error: 'Database cancellation failed.', details: rpcError.message },
        { status: 500, headers: corsHeaders },
      );
    }

    // Remove provisional joining participant from primary LiveKit room if present
    const roomName = `voryn-call-${op.primary_call_id}`;
    try {
      const roomService = new RoomServiceClient(
        getLiveKitHttpUrl(livekitUrl),
        livekitApiKey,
        livekitApiSecret,
      );
      await roomService.removeParticipant(roomName, op.joining_user_uid);
    } catch (_) {
      // Non-fatal if participant was not connected to primary room
    }

    return Response.json(
      {
        result: 'cancelled',
        mergeOperationId: op.id,
        status: 'cancelled',
        reason,
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    console.error(error);
    return Response.json(
      { error: 'Unable to cancel merge operation.' },
      { status: 500, headers: corsHeaders },
    );
  }
});

