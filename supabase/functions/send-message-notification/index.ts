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

    const bodyJson = await request.json().catch(() => ({}));
    let outboxId = bodyJson.outboxId;

    const admin = createClient(supabaseUrl, secretKey);

    // Backward compatibility: if messageId passed instead of outboxId, find latest pending row
    if (!outboxId && bodyJson.messageId) {
      const { data: fallbackRow } = await admin
        .from('message_push_outbox')
        .select('id')
        .eq('message_id', bodyJson.messageId)
        .in('status', ['pending', 'retry'])
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (fallbackRow) {
        outboxId = fallbackRow.id;
      }
    }

    if (typeof outboxId !== 'string' || !/^[0-9a-f-]{36}$/i.test(outboxId)) {
      return Response.json({ error: 'Invalid outboxId.' }, {
        status: 400,
        headers: corsHeaders,
      });
    }

    // 1. Atomic claim of the push event
    const { data: claimed, error: claimError } = await admin.rpc(
      'claim_message_push_event',
      { p_outbox_id: outboxId }
    );

    if (claimError) {
      console.error(
        `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} claim_error=${claimError.message}`
      );
    }

    if (claimed === false) {
      const { data: outboxRow } = await admin
        .from('message_push_outbox')
        .select('status, attempt_count')
        .eq('id', outboxId)
        .maybeSingle();

      const currentStatus = outboxRow?.status ?? 'unknown';
      console.log(
        `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} claim=rejected status=${currentStatus}`
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

    console.log(`[MESSAGE_PUSH_SERVER] outboxId=${outboxId} claim=acquired`);

    // 2. Load outbox event row
    const { data: outboxRow, error: outboxError } = await admin
      .from('message_push_outbox')
      .select('id, message_id, event_type, message_version, recipient_uid')
      .eq('id', outboxId)
      .maybeSingle();

    if (outboxError || !outboxRow) {
      await admin.rpc('update_message_push_result', {
        p_outbox_id: outboxId,
        p_status: 'failed_terminal',
        p_error: 'Outbox row not found',
      });
      return Response.json({ error: 'Outbox row not found.' }, {
        status: 404,
        headers: corsHeaders,
      });
    }

    // 3. Load canonical message
    const { data: message, error: messageError } = await admin
      .from('call_messages')
      .select('id, thread_id, sender_uid, recipient_uid, body, remind_to_call, created_at, edited_at, deleted_at, message_version')
      .eq('id', outboxRow.message_id)
      .maybeSingle();

    if (messageError || !message) {
      await admin.rpc('update_message_push_result', {
        p_outbox_id: outboxId,
        p_status: 'failed_terminal',
        p_error: 'Canonical message not found',
      });
      return Response.json({ error: 'Message not found.' }, {
        status: 404,
        headers: corsHeaders,
      });
    }

    // 4. Canonical state reconciliation
    let payloadType = 'call_message';
    let pushVersion = String(outboxRow.message_version || 1);
    let pushBody = '';

    if (outboxRow.event_type === 'created') {
      if (message.deleted_at) {
        console.log(
          `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} messageId=${message.id} obsolete_created_deleted`
        );
        await admin.rpc('update_message_push_result', {
          p_outbox_id: outboxId,
          p_status: 'sent',
          p_error: 'obsolete_created_deleted',
        });
        return Response.json(
          { status: 'obsolete_created_deleted' },
          { headers: corsHeaders }
        );
      }
      payloadType = 'call_message';
      pushVersion = String(message.message_version);
      pushBody = message.body ?? '';
    } else if (outboxRow.event_type === 'edited') {
      if (message.deleted_at) {
        console.log(
          `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} messageId=${message.id} obsolete_edit_deleted`
        );
        await admin.rpc('update_message_push_result', {
          p_outbox_id: outboxId,
          p_status: 'sent',
          p_error: 'obsolete_edit_deleted',
        });
        return Response.json(
          { status: 'obsolete_edit_deleted' },
          { headers: corsHeaders }
        );
      }
      if (Number(outboxRow.message_version) < Number(message.message_version)) {
        console.log(
          `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} messageId=${message.id} stale_edit_superseded outboxVer=${outboxRow.message_version} canonicalVer=${message.message_version}`
        );
        await admin.rpc('update_message_push_result', {
          p_outbox_id: outboxId,
          p_status: 'sent',
          p_error: 'stale_edit_superseded',
        });
        return Response.json(
          { status: 'stale_edit_superseded' },
          { headers: corsHeaders }
        );
      }
      payloadType = 'call_message_edited';
      pushVersion = String(message.message_version);
      pushBody = message.body ?? '';
    } else if (outboxRow.event_type === 'deleted') {
      payloadType = 'call_message_deleted';
      pushVersion = String(message.message_version);
      pushBody = ''; // Never send deleted body
    }

    // 5. Load sender profile
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

    // 6. Load recipient devices
    const targetRecipient = outboxRow.recipient_uid || message.recipient_uid;
    const { data: devices } = await admin
      .from('user_devices')
      .select('push_token, platform, installation_id')
      .eq('user_uid', targetRecipient)
      .not('push_token', 'is', null);

    const tokens = [
      ...new Set((devices ?? []).map((d) => d.push_token).filter(Boolean)),
    ] as string[];

    console.log(
      `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} messageId=${message.id} eventType=${outboxRow.event_type} recipientUid=${targetRecipient} devicesFound=${tokens.length}`
    );

    if (tokens.length === 0) {
      await admin.rpc('update_message_push_result', {
        p_outbox_id: outboxId,
        p_status: 'sent',
        p_error: 'no_devices',
      });
      return Response.json(
        { delivered: 0, reason: 'no_devices' },
        { headers: corsHeaders }
      );
    }

    // 7. Authorize Firebase and dispatch FCM
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
            type: payloadType,
            message_id: String(message.id),
            thread_id: String(message.thread_id),
            sender_uid: String(message.sender_uid),
            sender_name: senderName,
            sender_voryn_id: senderVorynId,
            body: pushBody,
            remind_to_call: message.remind_to_call ? 'true' : 'false',
            message_version: pushVersion,
            created_at: String(message.created_at ?? ''),
            edited_at: String(message.edited_at ?? ''),
            deleted_at: String(message.deleted_at ?? ''),
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
            `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} type=${payloadType} tokenPrefix=${token.slice(0, 8)} send_success fcmId=${resJson?.name}`
          );
        } else {
          const status = res.status;
          const errorCode = resJson?.error?.details?.[0]?.errorCode || resJson?.error?.status || '';
          lastError = `FCM status=${status} code=${errorCode}`;
          console.error(
            `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} tokenPrefix=${token.slice(0, 8)} send_failure status=${status} error=${JSON.stringify(resJson)}`
          );

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
          `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} fetch_exception:`,
          err
        );
      }
    }

    // 8. Update outbox status based on delivery outcome
    if (deliveredCount > 0) {
      await admin.rpc('update_message_push_result', {
        p_outbox_id: outboxId,
        p_status: 'sent',
        p_error: null,
      });
      console.log(
        `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} result=sent delivered=${deliveredCount}`
      );
      return Response.json(
        { delivered: deliveredCount, status: 'sent' },
        { headers: corsHeaders }
      );
    } else {
      await admin.rpc('update_message_push_result', {
        p_outbox_id: outboxId,
        p_status: 'retry',
        p_error: lastError ?? 'FCM delivery failed for all devices',
      });
      console.log(
        `[MESSAGE_PUSH_SERVER] outboxId=${outboxId} result=retry error=${lastError}`
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
