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
    const authorization = request.headers.get('Authorization');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const publishableKey =
      environmentKey('SUPABASE_PUBLISHABLE_KEYS') ??
      Deno.env.get('SUPABASE_ANON_KEY');
    const secretKey =
      environmentKey('SUPABASE_SECRET_KEYS') ??
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!authorization || !supabaseUrl || !publishableKey || !secretKey) {
      return Response.json({ error: 'Call alerts are unavailable.' }, {
        status: 503,
        headers: corsHeaders,
      });
    }
    if (!serviceAccountJson) {
      throw new Error('Firebase service account is not configured.');
    }

    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) {
      return Response.json({ error: 'Authentication is required.' }, {
        status: 401,
        headers: corsHeaders,
      });
    }

    const { callId, recipientUid } = await request.json();
    if (typeof callId !== 'string' || !/^[0-9a-f-]{36}$/i.test(callId)) {
      return Response.json({ error: 'Invalid call.' }, {
        status: 400,
        headers: corsHeaders,
      });
    }

    const admin = createClient(supabaseUrl, secretKey);
    const { data: call, error: callError } = await admin
      .from('calls')
      .select('initiated_by, call_type, status')
      .eq('id', callId)
      .maybeSingle();

    if (callError || !call) {
      return Response.json({ error: 'Call is unavailable.' }, {
        status: 403,
        headers: corsHeaders,
      });
    }

    let targetRecipientUid: string | null = null;

    if (recipientUid && typeof recipientUid === 'string') {
      // Check caller is in call_participants and call is active
      const { data: callerPart } = await admin
        .from('call_participants')
        .select('user_uid')
        .eq('call_id', callId)
        .eq('user_uid', user.id)
        .maybeSingle();
      if (!callerPart || !['calling', 'ringing', 'connected'].includes(call.status)) {
        return Response.json({ error: 'Call is unavailable for invite.' }, {
          status: 403,
          headers: corsHeaders,
        });
      }
      targetRecipientUid = recipientUid;
    } else {
      if (call.initiated_by !== user.id || call.status !== 'calling') {
        return Response.json({ error: 'Call is unavailable.' }, {
          status: 403,
          headers: corsHeaders,
        });
      }
      const { data: recipient } = await admin
        .from('call_participants')
        .select('user_uid')
        .eq('call_id', callId)
        .neq('user_uid', user.id)
        .maybeSingle();
      targetRecipientUid = recipient?.user_uid ?? null;
    }

    if (!targetRecipientUid) {
      return Response.json({ delivered: 0 }, { headers: corsHeaders });
    }

    const { data: settings } = await admin
      .from('user_settings')
      .select('incoming_call_notifications, do_not_disturb')
      .eq('user_uid', targetRecipientUid)
      .maybeSingle();
    if (settings?.incoming_call_notifications === false || settings?.do_not_disturb === true) {
      return Response.json({ delivered: 0 }, { headers: corsHeaders });
    }

    const { data: callerProfile } = await admin
      .from('profiles')
      .select('full_name, voryn_id')
      .eq('uid', user.id)
      .maybeSingle();
    const callerName = callerProfile?.full_name?.trim() || callerProfile?.voryn_id || 'Voryn user';

    const { data: devices } = await admin
      .from('user_devices')
      .select('push_token')
      .eq('user_uid', targetRecipientUid)
      .eq('platform', 'android')
      .not('push_token', 'is', null);
    const tokens = [...new Set((devices ?? []).map((device) => device.push_token).filter(Boolean))];
    if (tokens.length === 0) {
      return Response.json({ delivered: 0 }, { headers: corsHeaders });
    }

    const credentials = JSON.parse(serviceAccountJson) as FirebaseServiceAccount;
    const auth = new GoogleAuth({
      credentials,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });
    const accessToken = await auth.getAccessToken();
    if (!accessToken) throw new Error('Could not authorize Firebase messaging.');

    const endpoint = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
    const responses = await Promise.all(tokens.map((token) => fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          data: {
            type: 'incoming_call',
            call_id: callId,
            call_type: call.call_type,
            caller_name: callerName,
          },
          android: { priority: 'high' },
        },
      }),
    })));

    return Response.json({
      delivered: responses.filter((response) => response.ok).length,
    }, { headers: corsHeaders });
  } catch (error) {
    console.error(error);
    return Response.json({ error: 'Unable to deliver the call alert.' }, {
      status: 500,
      headers: corsHeaders,
    });
  }
});
