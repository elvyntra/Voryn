import { GoogleAuth } from 'npm:google-auth-library@9.15.1';
import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-internal-secret',
};

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

function environmentKey(name: string): string | null {
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
    const authorization = request.headers.get('Authorization') ?? '';
    const incomingSecret =
      request.headers.get('x-internal-secret') ??
      request.headers.get('X-Internal-Secret') ??
      '';

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const secretKey =
      environmentKey('SUPABASE_SECRET_KEYS') ??
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    const expectedInternalSecret = Deno.env.get('INTERNAL_TRIGGER_SECRET');

    if (!supabaseUrl || !secretKey) {
      return Response.json({ error: 'Push service unavailable.' }, {
        status: 503,
        headers: corsHeaders,
      });
    }

    // Verify authentication: internal secret header OR service role authorization
    const isInternalAuth =
      expectedInternalSecret &&
      incomingSecret.trim().length > 0 &&
      incomingSecret.trim() === expectedInternalSecret.trim();
    const isServiceRoleAuth =
      authorization.length > 0 && authorization.includes(secretKey);

    if (!isInternalAuth && !isServiceRoleAuth) {
      console.warn('[MESSAGE_PUSH_SERVER] unauthorized attempt');
      return Response.json({ error: 'Unauthorized.' }, {
        status: 401,
        headers: corsHeaders,
      });
    }

    if (!serviceAccountJson) {
      throw new Error('Firebase service account is not configured.');
    }

    const { messageId } = await request.json();
    if (typeof messageId !== 'string' || !/^[0-9a-f-]{36}$/i.test(messageId)) {
      return Response.json({ error: 'Invalid messageId.' }, {
        status: 400,
        headers: corsHeaders,
      });
    }

    const admin = createClient(supabaseUrl, secretKey);

    // 1. Atomic claim of the push row
    const { data: claimed, error: claimError } = await admin.rpc(
      'claim_message_push',
      { p_message_id: messageId }
    );

    if (claimError) {
      console.error(
        `[MESSAGE_PUSH_SERVER] messageId=${messageId} claim_error=${claimError.message}`
      );
    }

    if (claimed === false) {
      // Check current status in outbox
      const { data: outboxRow } = await admin
        .from('message_push_outbox')
        .select('status, attempt_count')
        .eq('message_id', messageId)
        .maybeSingle();

      const currentStatus = outboxRow?.status ?? 'unknown';
      console.log(
        `[MESSAGE_PUSH_SERVER] messageId=${messageId} claim=rejected status=${currentStatus}`
      );

      if (currentStatus === 'sent') {
        return Response.json(
          { status: 'already_processed' },
          { headers: corsHeaders }
        );
      }
      return Response.json(
        { status: 'already_processing', outboxStatus: currentStatus },
        { headers: corsHeaders }
      );
    }

    console.log(
      `[MESSAGE_PUSH_SERVER] messageId=${messageId} claim=acquired`
    );

    // 2. Load canonical message
    const { data: message, error: messageError } = await admin
      .from('call_messages')
      .select('id, thread_id, sender_uid, recipient_uid, body, remind_to_call, created_at')
      .eq('id', messageId)
      .maybeSingle();

    if (messageError || !message) {
      await admin.rpc('update_message_push_result', {
        p_message_id: messageId,
        p_status: 'failed_terminal',
        p_error: 'Canonical message not found',
      });
      return Response.json({ error: 'Message not found.' }, {
        status: 404,
        headers: corsHeaders,
      });
    }

    // 3. Load sender profile
    const { data: senderProfile } = await admin
      .from('profiles')
      .select('full_name, voryn_id')
      .eq('uid', message.sender_uid)
      .maybeSingle();

    const senderName =
      senderProfile?.full_name?.trim() ||
      senderProfile?.voryn_id ||
      'Voryn User';
    const senderVorynId = senderProfile?.voryn_id || '';

    // 4. Load recipient devices
    const { data: devices } = await admin
      .from('user_devices')
      .select('push_token, platform, installation_id')
      .eq('user_uid', message.recipient_uid)
      .not('push_token', 'is', null);

    const tokens = [
      ...new Set((devices ?? []).map((d) => d.push_token).filter(Boolean)),
    ] as string[];

    console.log(
      `[MESSAGE_PUSH_SERVER] messageId=${messageId} recipientUid=${message.recipient_uid} devicesFound=${tokens.length}`
    );

    if (tokens.length === 0) {
      await admin.rpc('update_message_push_result', {
        p_message_id: messageId,
        p_status: 'sent',
        p_error: 'no_devices',
      });
      return Response.json(
        { delivered: 0, reason: 'no_devices' },
        { headers: corsHeaders }
      );
    }

    // 5. Authorize Firebase and dispatch FCM
    const credentials = JSON.parse(serviceAccountJson) as FirebaseServiceAccount;
    const googleAuth = new GoogleAuth({
      credentials,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });
    const accessToken = await googleAuth.getAccessToken();
    if (!accessToken) throw new Error('Could not authorize Firebase messaging.');

    const endpoint = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
    let deliveredCount = 0;
    let lastError: string | null = null;

    for (const token of tokens) {
      const payload = {
        message: {
          token,
          data: {
            type: 'call_message',
            message_id: message.id,
            thread_id: message.thread_id,
            sender_uid: message.sender_uid,
            sender_name: senderName,
            sender_voryn_id: senderVorynId,
            body: message.body,
            remind_to_call: message.remind_to_call ? 'true' : 'false',
            created_at: message.created_at,
          },
          android: {
            priority: 'high',
            ttl: '86400s',
          },
          webpush: {
            headers: {
              Urgency: 'high',
            },
          },
        },
      };

      try {
        const res = await fetch(endpoint, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload),
        });

        const resJson = await res.json().catch(() => null);

        if (res.ok) {
          deliveredCount++;
          console.log(
            `[MESSAGE_PUSH_SERVER] messageId=${messageId} tokenPrefix=${token.slice(0, 8)} send_success fcmId=${resJson?.name}`
          );
        } else {
          const status = res.status;
          const errorCode = resJson?.error?.details?.[0]?.errorCode || resJson?.error?.status || '';
          lastError = `FCM status=${status} code=${errorCode}`;
          console.error(
            `[MESSAGE_PUSH_SERVER] messageId=${messageId} tokenPrefix=${token.slice(0, 8)} send_failure status=${status} error=${JSON.stringify(resJson)}`
          );

          // Prune dead/unregistered tokens
          if (
            status === 404 ||
            errorCode === 'UNREGISTERED' ||
            errorCode === 'NOT_FOUND' ||
            resJson?.error?.message?.includes('Requested entity was not found')
          ) {
            console.log(
              `[MESSAGE_PUSH_SERVER] pruning dead tokenPrefix=${token.slice(0, 8)}`
            );
            await admin
              .from('user_devices')
              .delete()
              .eq('push_token', token);
          }
        }
      } catch (err) {
        lastError = String(err);
        console.error(
          `[MESSAGE_PUSH_SERVER] messageId=${messageId} fetch_exception:`,
          err
        );
      }
    }

    // 6. Update outbox status based on delivery outcome
    if (deliveredCount > 0) {
      await admin.rpc('update_message_push_result', {
        p_message_id: messageId,
        p_status: 'sent',
        p_error: null,
      });
      console.log(
        `[MESSAGE_PUSH_SERVER] messageId=${messageId} result=sent delivered=${deliveredCount}`
      );
      return Response.json(
        { delivered: deliveredCount, status: 'sent' },
        { headers: corsHeaders }
      );
    } else {
      await admin.rpc('update_message_push_result', {
        p_message_id: messageId,
        p_status: 'retry',
        p_error: lastError ?? 'FCM delivery failed for all devices',
      });
      console.log(
        `[MESSAGE_PUSH_SERVER] messageId=${messageId} result=retry error=${lastError}`
      );
      return Response.json(
        { delivered: 0, status: 'retry', error: lastError },
        { status: 502, headers: corsHeaders }
      );
    }
  } catch (error) {
    console.error('[MESSAGE_PUSH_SERVER] unhandled_exception:', error);
    return Response.json(
      { error: 'Internal error processing message push.' },
      { status: 500, headers: corsHeaders }
    );
  }
});
