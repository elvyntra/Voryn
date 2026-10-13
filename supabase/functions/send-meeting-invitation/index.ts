import { GoogleAuth } from 'npm:google-auth-library@9.15.1';
import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
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
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');

    if (!supabaseUrl || !publishableKey || !secretKey) {
      return Response.json(
        { error: 'Meeting invitation service is not configured.' },
        { status: 503, headers: corsHeaders },
      );
    }

    // 1. Authenticate the caller
    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) {
      return Response.json(
        { error: 'Authentication is required.' },
        { status: 401, headers: corsHeaders },
      );
    }

    const body = await request.json().catch(() => ({}));
    const meetingId = body.meetingId;
    let targetUserUids: string[] = [];

    if (Array.isArray(body.targetUserUids)) {
      targetUserUids = body.targetUserUids.filter(
        (id: unknown) => typeof id === 'string' && /^[0-9a-f-]{36}$/i.test(id)
      );
    } else if (typeof body.targetUserUid === 'string' && /^[0-9a-f-]{36}$/i.test(body.targetUserUid)) {
      targetUserUids = [body.targetUserUid];
    }

    if (typeof meetingId !== 'string' || !/^[0-9a-f-]{36}$/i.test(meetingId) || targetUserUids.length === 0) {
      return Response.json(
        { error: 'Invalid meetingId or targetUserUids.' },
        { status: 400, headers: corsHeaders },
      );
    }

    const adminClient = createClient(supabaseUrl, secretKey);

    // 2. Fetch meeting details
    const { data: meeting, error: meetingError } = await adminClient
      .from('meetings')
      .select('id, title, join_code, status, host_uid')
      .eq('id', meetingId)
      .maybeSingle();

    if (meetingError || !meeting) {
      return Response.json(
        { error: 'Meeting not found.' },
        { status: 404, headers: corsHeaders },
      );
    }

    if (meeting.status === 'ended' || meeting.status === 'cancelled') {
      return Response.json(
        { error: `Cannot invite participants to ${meeting.status} meeting.` },
        { status: 400, headers: corsHeaders },
      );
    }

    // 3. Verify caller authorization: must be host or participant
    const isHost = meeting.host_uid === user.id;
    if (!isHost) {
      const { data: callerParticipant } = await adminClient
        .from('meeting_participants')
        .select('user_uid')
        .eq('meeting_id', meetingId)
        .eq('user_uid', user.id)
        .maybeSingle();

      if (!callerParticipant) {
        return Response.json(
          { error: 'Unauthorized to invite participants to this meeting.' },
          { status: 403, headers: corsHeaders },
        );
      }
    }

    // 4. Fetch caller display name
    const { data: callerProfile } = await adminClient
      .from('profiles')
      .select('full_name, voryn_id')
      .eq('uid', user.id)
      .maybeSingle();
    const inviterName = callerProfile?.full_name?.trim() || callerProfile?.voryn_id || 'A VoRyn contact';

    // 5. Setup Firebase Messaging if configured
    let fcmAuth: GoogleAuth | null = null;
    let fcmEndpoint: string | null = null;
    if (serviceAccountJson) {
      try {
        const credentials = JSON.parse(serviceAccountJson) as FirebaseServiceAccount;
        fcmAuth = new GoogleAuth({
          credentials,
          scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
        });
        fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
      } catch (err) {
        console.warn('[MEETING_INVITE_FCM] Firebase service account parse failed:', err);
      }
    }

    const results: Array<{
      user_uid: string;
      success: boolean;
      already_invited: boolean;
      notification_sent: boolean;
      error?: string;
    }> = [];

    // 6. Process each invited participant
    for (const targetUid of targetUserUids) {
      try {
        // Check pre-existing invitation state for deduplication
        const { data: existingParticipant } = await adminClient
          .from('meeting_participants')
          .select('role, invited_at, joined_at')
          .eq('meeting_id', meetingId)
          .eq('user_uid', targetUid)
          .maybeSingle();

        const wasAlreadyInvited = Boolean(existingParticipant?.invited_at);

        // Authoritative RPC invocation
        const { error: rpcError } = await userClient.rpc('invite_meeting_participant', {
          p_meeting_id: meetingId,
          p_target_user_id: targetUid,
        });

        if (rpcError) {
          results.push({
            user_uid: targetUid,
            success: false,
            already_invited: wasAlreadyInvited,
            notification_sent: false,
            error: rpcError.message,
          });
          continue;
        }

        // Deduplication: Only send push notification if this is a NEW invitation
        let notificationSent = false;
        if (!wasAlreadyInvited && fcmAuth && fcmEndpoint) {
          // Resolve target user device tokens
          const { data: devices } = await adminClient
            .from('user_devices')
            .select('push_token')
            .eq('user_uid', targetUid)
            .eq('platform', 'android')
            .not('push_token', 'is', null);

          const tokens = [...new Set((devices ?? []).map((d) => d.push_token).filter(Boolean))];

          if (tokens.length > 0) {
            const accessToken = await fcmAuth.getAccessToken();
            if (accessToken) {
              const eventId = crypto.randomUUID();
              await Promise.all(
                tokens.map(async (token) => {
                  try {
                    await fetch(fcmEndpoint!, {
                      method: 'POST',
                      headers: {
                        Authorization: `Bearer ${accessToken}`,
                        'Content-Type': 'application/json',
                      },
                      body: JSON.stringify({
                        message: {
                          token,
                          data: {
                            type: 'meeting_invitation',
                            meeting_id: meetingId,
                            join_code: meeting.join_code,
                            inviter_name: inviterName,
                            meeting_title: meeting.title,
                            destination: `voryn://m/${meeting.join_code}`,
                            event_id: eventId,
                          },
                          android: {
                            priority: 'high',
                            ttl: '3600s',
                          },
                        },
                      }),
                    });
                  } catch (e) {
                    console.warn(`[MEETING_INVITE_FCM] send error for target=${targetUid}:`, e);
                  }
                })
              );
              notificationSent = true;
            }
          }

          // Record notification record in public.notifications
          try {
            await adminClient.from('notifications').insert({
              user_uid: targetUid,
              kind: 'meeting_invitation',
              title: 'VoRyn Meeting Invitation',
              body: `${inviterName} invited you to join "${meeting.title}"`,
              data: {
                meeting_id: meetingId,
                join_code: meeting.join_code,
                inviter_name: inviterName,
                meeting_title: meeting.title,
              },
            });
          } catch (_) {}
        }

        results.push({
          user_uid: targetUid,
          success: true,
          already_invited: wasAlreadyInvited,
          notification_sent: notificationSent,
        });
      } catch (err) {
        results.push({
          user_uid: targetUid,
          success: false,
          already_invited: false,
          notification_sent: false,
          error: String(err),
        });
      }
    }

    return Response.json(
      { success: results.some((r) => r.success), results },
      { headers: corsHeaders },
    );
  } catch (error) {
    console.error('[MEETING_INVITATION_ERROR]', error);
    return Response.json(
      { error: 'Internal meeting invitation error.' },
      { status: 500, headers: corsHeaders },
    );
  }
});

