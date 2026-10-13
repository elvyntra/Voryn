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

    const roomName = `voryn-call-${op.primary_call_id}`;
    const roomService = new RoomServiceClient(
      getLiveKitHttpUrl(livekitUrl),
      livekitApiKey,
      livekitApiSecret,
    );

    // =========================================================================
    // 1. IDEMPOTENT RETRY & POST-COMMIT PROMOTION RECOVERY
    // =========================================================================
    if (op.status === 'committed') {
      try {
        await roomService.updateParticipant(
          roomName,
          op.joining_user_uid,
          undefined,
          {
            canPublish: true,
            canSubscribe: true,
            canPublishData: true,
          },
        );
      } catch (_) {}

      return Response.json(
        {
          result: 'already_committed',
          conferenceCallId: op.primary_call_id,
          committedAt: op.committed_at,
        },
        { headers: corsHeaders },
      );
    }

    // =========================================================================
    // 2. EXPIRY & CANCELLATION CLEANUP
    // =========================================================================
    const now = new Date();
    if (
      op.status === 'cancelled' ||
      op.status === 'expired' ||
      new Date(op.expires_at) <= now
    ) {
      if (op.status !== 'cancelled' && op.status !== 'expired') {
        await admin
          .from('call_merge_operations')
          .update({ status: 'expired' })
          .eq('id', op.id);
      }

      // Eject provisional participant from primary LiveKit room on expiry/cancel
      try {
        await roomService.removeParticipant(roomName, op.joining_user_uid);
      } catch (_) {}

      return Response.json(
        {
          error: 'Merge operation has expired or was cancelled.',
          result: 'rejected',
          reason: 'merge_op_expired_or_cancelled',
        },
        { status: 400, headers: corsHeaders },
      );
    }

    // Authenticate initiator
    if (op.initiated_by !== user.id) {
      return Response.json(
        { error: 'Unauthorized: only initiator may finalize merge.' },
        { status: 403, headers: corsHeaders },
      );
    }

    // Validate operation state
    if (!['prepared', 'joining'].includes(op.status)) {
      return Response.json(
        {
          error: 'Invalid merge operation state.',
          result: 'rejected',
          reason: 'invalid_status',
        },
        { status: 400, headers: corsHeaders },
      );
    }

    // Validate active call states
    const { data: pCall } = await admin
      .from('calls')
      .select('id, status')
      .eq('id', op.primary_call_id)
      .maybeSingle();
    const { data: sCall } = await admin
      .from('calls')
      .select('id, status')
      .eq('id', op.secondary_call_id)
      .maybeSingle();

    if (
      !pCall ||
      !sCall ||
      !['connected', 'on_hold'].includes(pCall.status) ||
      !['connected', 'on_hold'].includes(sCall.status)
    ) {
      return Response.json(
        {
          error: 'Calls are no longer active.',
          result: 'rejected',
          reason: 'calls_not_active',
        },
        { status: 400, headers: corsHeaders },
      );
    }

    // =========================================================================
    // 3. SERVER-VERIFIED LIVEKIT ADMISSION
    // =========================================================================
    // Confirm C is physically present in the PRIMARY room and identity strictly matches joining_user_uid
    let participant = null;
    try {
      participant = await roomService.getParticipant(
        roomName,
        op.joining_user_uid,
      );
    } catch (lkErr) {
      console.warn(
        `Participant lookup failed for ${op.joining_user_uid} in ${roomName}:`,
        lkErr,
      );
    }

    if (!participant || participant.identity !== op.joining_user_uid) {
      return Response.json(
        {
          error:
            'Joining participant has not connected to the surviving LiveKit room.',
          result: 'rejected',
          reason: 'participant_not_in_livekit_room',
        },
        { status: 400, headers: corsHeaders },
      );
    }

    // =========================================================================
    // 4. ATOMIC DATABASE COMMIT
    // =========================================================================
    const { data: rpcResult, error: rpcError } = await admin.rpc(
      'commit_call_merge',
      {
        p_merge_operation_id: op.id,
      },
    );

    if (rpcError) {
      console.error('commit_call_merge RPC error:', rpcError);
      // Rollback: Eject provisional participant from primary room
      try {
        await roomService.removeParticipant(roomName, op.joining_user_uid);
      } catch (_) {}

      return Response.json(
        {
          error: 'Database commit failed.',
          details: rpcError.message,
        },
        { status: 500, headers: corsHeaders },
      );
    }

    if (
      rpcResult?.result !== 'committed' &&
      rpcResult?.result !== 'already_committed'
    ) {
      // Eject provisional participant from primary room
      try {
        await roomService.removeParticipant(roomName, op.joining_user_uid);
      } catch (_) {}

      return Response.json(
        {
          error: `Merge rejected: ${rpcResult?.reason ?? 'unknown'}`,
          result: rpcResult?.result ?? 'rejected',
          reason: rpcResult?.reason,
        },
        { status: 400, headers: corsHeaders },
      );
    }

    // =========================================================================
    // 5. POST-COMMIT PERMISSION PROMOTION
    // =========================================================================
    try {
      await roomService.updateParticipant(
        roomName,
        op.joining_user_uid,
        undefined,
        {
          canPublish: true,
          canSubscribe: true,
          canPublishData: true,
        },
      );
    } catch (permErr) {
      console.error(
        'LiveKit permission promotion error (non-fatal, commit completed):',
        permErr,
      );
    }

    return Response.json(
      {
        result: 'committed',
        conferenceCallId: op.primary_call_id,
        secondaryCallId: op.secondary_call_id,
        joiningUserUid: op.joining_user_uid,
        committedAt: rpcResult?.committed_at ?? new Date().toISOString(),
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    console.error(error);
    return Response.json(
      { error: 'Unable to finalize merge operation.' },
      { status: 500, headers: corsHeaders },
    );
  }
});
