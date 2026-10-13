import { createClient } from 'npm:@supabase/supabase-js@2';
import { AccessToken } from 'npm:livekit-server-sdk@2.19.0';

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
    const { callId, meetingId, mergeOperationId, mergeOpId } = body;
    const mergeId = mergeOperationId ?? mergeOpId;

    if (!callId && !meetingId) {
      return Response.json(
        { error: 'Invalid request: callId or meetingId is required.' },
        { status: 400, headers: corsHeaders },
      );
    }

    const admin = createClient(supabaseUrl, secretKey);

    // =========================================================================
    // 1. ACTIVE MEETING PARTICIPANT
    // =========================================================================
    if (meetingId) {
      if (typeof meetingId !== 'string' || !/^[0-9a-f-]{36}$/i.test(meetingId)) {
        return Response.json(
          { error: 'Invalid meeting.' },
          { status: 400, headers: corsHeaders },
        );
      }

      const { data: meeting, error: meetingError } = await admin
        .from('meetings')
        .select('id, status, host_uid')
        .eq('id', meetingId)
        .maybeSingle();

      if (meetingError || !meeting) {
        return Response.json(
          { error: 'Meeting not found.' },
          { status: 404, headers: corsHeaders },
        );
      }

      if (meeting.status !== 'active') {
        if (meeting.status === 'ready') {
          return Response.json(
            { error: 'Meeting has not started yet.' },
            { status: 403, headers: corsHeaders },
          );
        }
        return Response.json(
          { error: `Meeting has ${meeting.status}.` },
          { status: 403, headers: corsHeaders },
        );
      }

      const { data: participant, error: participantError } = await admin
        .from('meeting_participants')
        .select('meeting_id, user_uid, role, joined_at, left_at')
        .eq('meeting_id', meetingId)
        .eq('user_uid', user.id)
        .maybeSingle();

      if (participantError || !participant) {
        return Response.json(
          { error: 'Unauthorized: not a participant of this meeting.' },
          { status: 403, headers: corsHeaders },
        );
      }

      if (!participant.joined_at) {
        return Response.json(
          { error: 'Unauthorized: participant has not joined this meeting.' },
          { status: 403, headers: corsHeaders },
        );
      }

      if (participant.left_at) {
        return Response.json(
          { error: 'Unauthorized: participant has left this meeting.' },
          { status: 403, headers: corsHeaders },
        );
      }

      const roomName = `voryn-meeting-${meeting.id}`;
      const meetingTtl = Deno.env.get('LIVEKIT_MEETING_TOKEN_TTL') ?? '2h';
      const token = new AccessToken(livekitApiKey, livekitApiSecret, {
        identity: user.id, // Strict invariant: identity == authenticated user UID
        ttl: meetingTtl,
      });
      token.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
      });

      return Response.json(
        {
          url: livekitUrl,
          token: await token.toJwt(),
          roomName,
          tokenType: 'meeting',
          meetingId: meeting.id,
          role: participant.role,
          ttl: meetingTtl,
        },
        { headers: corsHeaders },
      );
    }

    // =========================================================================
    // 2. STANDARD ACTIVE CALL PARTICIPANT
    // =========================================================================
    if (typeof callId !== 'string' || !/^[0-9a-f-]{36}$/i.test(callId)) {
      return Response.json(
        { error: 'Invalid call.' },
        { status: 400, headers: corsHeaders },
      );
    }

    const { data: participant, error: participantError } = await admin
      .from('call_participants')
      .select('call_id')
      .eq('call_id', callId)
      .eq('user_uid', user.id)
      .is('left_at', null)
      .maybeSingle();

    if (participant && !participantError) {
      const roomName = `voryn-call-${callId}`;
      const token = new AccessToken(livekitApiKey, livekitApiSecret, {
        identity: user.id, // Strict invariant: identity == authenticated user UID
        ttl: '10m',
      });
      token.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
      });

      return Response.json(
        {
          url: livekitUrl,
          token: await token.toJwt(),
          roomName,
          provisional: false,
        },
        { headers: corsHeaders },
      );
    }

    // =========================================================================
    // 2. PROVISIONAL MERGE PARTICIPANT
    // =========================================================================
    let opQuery = admin
      .from('call_merge_operations')
      .select('*')
      .eq('primary_call_id', callId)
      .eq('joining_user_uid', user.id); // Strict invariant: joining_user_uid == authenticated user UID

    if (mergeId) {
      if (typeof mergeId !== 'string' || !/^[0-9a-f-]{36}$/i.test(mergeId)) {
        return Response.json(
          { error: 'Invalid merge operation ID.' },
          { status: 400, headers: corsHeaders },
        );
      }
      opQuery = opQuery.eq('id', mergeId);
    }

    const { data: mergeOp, error: mergeErr } = await opQuery
      .in('status', ['prepared', 'joining'])
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (mergeErr || !mergeOp) {
      return Response.json(
        { error: 'This call is unavailable.' },
        { status: 403, headers: corsHeaders },
      );
    }

    // Validate token lifetime: token must NEVER outlive the merge operation!
    const remainingMs =
      new Date(mergeOp.expires_at).getTime() - Date.now();
    const remainingSeconds = Math.floor(remainingMs / 1000);

    // If remaining time is too small to safely complete handshake, reject
    if (remainingSeconds < 5) {
      return Response.json(
        {
          error: 'Merge operation is expiring; please retry prepare.',
          reason: 'merge_op_expiring',
        },
        { status: 400, headers: corsHeaders },
      );
    }

    const effectiveTtl = Math.min(30, remainingSeconds);

    // Verify User C is an active participant of the secondary call
    const { data: secondaryPart } = await admin
      .from('call_participants')
      .select('call_id')
      .eq('call_id', mergeOp.secondary_call_id)
      .eq('user_uid', user.id)
      .is('left_at', null)
      .maybeSingle();

    if (!secondaryPart) {
      return Response.json(
        { error: 'Unauthorized: not an active participant of secondary call.' },
        { status: 403, headers: corsHeaders },
      );
    }

    // Verify initiator participates in both calls
    const { data: initPart1 } = await admin
      .from('call_participants')
      .select('call_id')
      .eq('call_id', mergeOp.primary_call_id)
      .eq('user_uid', mergeOp.initiated_by)
      .is('left_at', null)
      .maybeSingle();

    const { data: initPart2 } = await admin
      .from('call_participants')
      .select('call_id')
      .eq('call_id', mergeOp.secondary_call_id)
      .eq('user_uid', mergeOp.initiated_by)
      .is('left_at', null)
      .maybeSingle();

    if (!initPart1 || !initPart2) {
      return Response.json(
        {
          error:
            'Merge initiator is not an active participant in both calls.',
        },
        { status: 403, headers: corsHeaders },
      );
    }

    // Verify both calls remain active
    const { data: pCall } = await admin
      .from('calls')
      .select('id, status')
      .eq('id', mergeOp.primary_call_id)
      .maybeSingle();
    const { data: sCall } = await admin
      .from('calls')
      .select('id, status')
      .eq('id', mergeOp.secondary_call_id)
      .maybeSingle();

    if (
      !pCall ||
      !sCall ||
      !['connected', 'on_hold'].includes(pCall.status) ||
      !['connected', 'on_hold'].includes(sCall.status)
    ) {
      return Response.json(
        { error: 'Calls are no longer active.' },
        { status: 400, headers: corsHeaders },
      );
    }

    // Verify conference participant capacity (limit: 8)
    const { data: pParts } = await admin
      .from('call_participants')
      .select('user_uid')
      .eq('call_id', mergeOp.primary_call_id)
      .is('left_at', null);
    const { data: sParts } = await admin
      .from('call_participants')
      .select('user_uid')
      .eq('call_id', mergeOp.secondary_call_id)
      .is('left_at', null);

    const distinctUids = new Set([
      ...(pParts ?? []).map((p: { user_uid: string }) => p.user_uid),
      ...(sParts ?? []).map((p: { user_uid: string }) => p.user_uid),
    ]);

    if (distinctUids.size > 8) {
      return Response.json(
        { error: 'Conference capacity limit exceeded.' },
        { status: 400, headers: corsHeaders },
      );
    }

    // Advance merge operation to 'joining'
    if (mergeOp.status === 'prepared') {
      await admin
        .from('call_merge_operations')
        .update({ status: 'joining' })
        .eq('id', mergeOp.id);
    }

    // Issue short-lived provisional token with media restrictions
    // canPublish: false, canSubscribe: false prevents echo and privacy leaks
    const roomName = `voryn-call-${mergeOp.primary_call_id}`;
    const token = new AccessToken(livekitApiKey, livekitApiSecret, {
      identity: user.id, // Strict invariant: identity == authenticated user UID == joining_user_uid
      ttl: `${effectiveTtl}s`, // Exactly bounded by remaining merge operation TTL
    });
    token.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: false,
      canPublishSources: [],
      canSubscribe: false,
      canPublishData: false,
    });

    return Response.json(
      {
        url: livekitUrl,
        token: await token.toJwt(),
        roomName,
        provisional: true,
        mergeOperationId: mergeOp.id,
        ttlSeconds: effectiveTtl,
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    console.error(error);
    return Response.json(
      { error: 'Unable to process call authorization request.' },
      { status: 500, headers: corsHeaders },
    );
  }
});
