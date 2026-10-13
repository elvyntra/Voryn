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
      return Response.json(
        { error: 'The meeting service is not configured.' },
        { status: 500, headers: corsHeaders },
      );
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
    const { meetingId, action } = body;

    if (!meetingId || typeof meetingId !== 'string' || !/^[0-9a-f-]{36}$/i.test(meetingId)) {
      return Response.json(
        { error: 'Invalid meeting ID.' },
        { status: 400, headers: corsHeaders },
      );
    }

    const admin = createClient(supabaseUrl, secretKey);

    // =========================================================================
    // 1. AUTHORITATIVE MEETING RECORD INSPECTION
    // =========================================================================
    const { data: meeting, error: meetingError } = await admin
      .from('meetings')
      .select('id, title, status, host_uid, ended_at')
      .eq('id', meetingId)
      .maybeSingle();

    if (meetingError || !meeting) {
      return Response.json(
        { error: 'Meeting not found.' },
        { status: 404, headers: corsHeaders },
      );
    }

    if (meeting.status === 'cancelled') {
      return Response.json(
        { error: 'Cancelled meeting cannot be ended.' },
        { status: 400, headers: corsHeaders },
      );
    }

    const isHost = meeting.host_uid === user.id;
    const isCleanupAction = action === 'cleanup';

    // =========================================================================
    // 2. SEPARATE CODE PATHS: HOST TERMINATION VS POST-END CLEANUP
    // =========================================================================
    const wasAlreadyEnded = meeting.status === 'ended';

    if (isCleanupAction) {
      // -----------------------------------------------------------------------
      // PATH A: POST-END CLEANUP
      // -----------------------------------------------------------------------
      // Invariant: Cleanup CANNOT change an active meeting to ended.
      if (meeting.status !== 'ended') {
        return Response.json(
          { error: 'Cannot clean up an active meeting. Host must end it first.' },
          { status: 400, headers: corsHeaders },
        );
      }

      // Invariant: Caller must be a legitimate participant or host of this meeting.
      const { data: participant, error: pError } = await admin
        .from('meeting_participants')
        .select('meeting_id')
        .eq('meeting_id', meeting.id)
        .eq('user_uid', user.id)
        .maybeSingle();

      if (!isHost && (pError || !participant)) {
        return Response.json(
          { error: 'Unauthorized: not a participant of this meeting.' },
          { status: 403, headers: corsHeaders },
        );
      }

      // Invariant: Meeting active participant count in DB must be zero.
      const { count: activeCount, error: countError } = await admin
        .from('meeting_participants')
        .select('*', { count: 'exact', head: true })
        .eq('meeting_id', meeting.id)
        .not('joined_at', 'is', null)
        .is('left_at', null);

      if (countError || (activeCount !== null && activeCount > 0)) {
        return Response.json(
          { error: 'Cannot clean up room: active participants still remain in meeting.' },
          { status: 400, headers: corsHeaders },
        );
      }
    } else {
      // -----------------------------------------------------------------------
      // PATH B: HOST TERMINATION (Default / action='host_end')
      // -----------------------------------------------------------------------
      // Invariant: Only the authoritative host can end an active meeting for everyone.
      // Client-supplied reasons (e.g. 'last_participant_left') are NEVER trusted as authority.
      if (!isHost) {
        // If non-host didn't ask for cleanup, but meeting is active -> strictly forbidden
        if (meeting.status !== 'ended') {
          return Response.json(
            { error: 'Only the meeting host can end an active meeting for everyone.' },
            { status: 403, headers: corsHeaders },
          );
        }

        // If meeting is already ended, non-host must follow cleanup prerequisites:
        const { data: participant, error: pError } = await admin
          .from('meeting_participants')
          .select('meeting_id')
          .eq('meeting_id', meeting.id)
          .eq('user_uid', user.id)
          .maybeSingle();

        if (pError || !participant) {
          return Response.json(
            { error: 'Unauthorized: not a participant of this meeting.' },
            { status: 403, headers: corsHeaders },
          );
        }

        const { count: activeCount, error: countError } = await admin
          .from('meeting_participants')
          .select('*', { count: 'exact', head: true })
          .eq('meeting_id', meeting.id)
          .not('joined_at', 'is', null)
          .is('left_at', null);

        if (countError || (activeCount !== null && activeCount > 0)) {
          return Response.json(
            { error: 'Cannot clean up room: active participants still remain in meeting.' },
            { status: 400, headers: corsHeaders },
          );
        }
      }

      // If meeting is active/ready and caller is host, execute authoritative database transition
      if (!wasAlreadyEnded && isHost) {
        // Use userClient so Postgres auth.uid() reflects the authenticated host UID
        const { error: endError } = await userClient.rpc(
          'end_voryn_meeting_for_everyone',
          { p_meeting_id: meeting.id },
        );

        if (endError) {
          console.error('end_voryn_meeting_for_everyone RPC error:', endError);
          return Response.json(
            {
              ok: false,
              status: 'failed_before_db',
              error: `Database failed to end meeting: ${endError.message}`,
              dbEnded: false,
              roomDeleted: false,
            },
            { status: 500, headers: corsHeaders },
          );
        }
      }
    }

    // =========================================================================
    // 3. SECURE LIVEKIT ROOM DELETION
    // Canonical room name is ALWAYS derived strictly server-side
    // =========================================================================
    const roomName = `voryn-meeting-${meeting.id}`;

    const roomService = new RoomServiceClient(
      getLiveKitHttpUrl(livekitUrl),
      livekitApiKey,
      livekitApiSecret,
    );

    let roomDeleted = false;
    let livekitCleanupPending = false;
    let livekitErrorMsg: string | null = null;

    try {
      await roomService.deleteRoom(roomName);
      roomDeleted = true;
    } catch (lkErr: any) {
      const errMsg = String(lkErr?.message || lkErr).toLowerCase();
      // Idempotency: If room does not exist, it was already deleted/absent -> success!
      if (
        errMsg.includes('not found') ||
        errMsg.includes('404') ||
        errMsg.includes('does not exist')
      ) {
        roomDeleted = true;
      } else {
        console.warn(`Failed to delete LiveKit room ${roomName}:`, lkErr);
        livekitCleanupPending = true;
        livekitErrorMsg = lkErr?.message || String(lkErr);
      }
    }

    if (livekitCleanupPending) {
      return Response.json(
        {
          ok: false,
          status: 'db_ended_livekit_pending',
          meetingId: meeting.id,
          dbEnded: true,
          roomDeleted: false,
          livekitCleanupPending: true,
          error: `Meeting ended in database, but LiveKit room cleanup is pending: ${livekitErrorMsg}`,
        },
        { status: 502, headers: corsHeaders },
      );
    }

    return Response.json(
      {
        ok: true,
        status: wasAlreadyEnded
          ? (isHost && !isCleanupAction ? 'already_ended' : 'cleaned_up')
          : 'ended',
        meetingId: meeting.id,
        roomName,
        dbEnded: true,
        roomDeleted,
        livekitCleanupPending: false,
      },
      { status: 200, headers: corsHeaders },
    );
  } catch (err: any) {
    console.error('Unexpected error in end-voryn-meeting:', err);
    return Response.json(
      { error: err?.message || 'Internal server error' },
      { status: 500, headers: corsHeaders },
    );
  }
});
