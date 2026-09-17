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

    const { callId } = await request.json();
    if (typeof callId !== 'string' || !/^[0-9a-f-]{36}$/i.test(callId)) {
      return Response.json(
        { error: 'Invalid call.' },
        { status: 400, headers: corsHeaders },
      );
    }

    const admin = createClient(supabaseUrl, secretKey);
    const { data: participant, error: participantError } = await admin
      .from('call_participants')
      .select('call_id')
      .eq('call_id', callId)
      .eq('user_uid', user.id)
      .maybeSingle();
    if (participantError || !participant) {
      return Response.json(
        { error: 'This call is unavailable.' },
        { status: 403, headers: corsHeaders },
      );
    }

    const roomName = `voryn-call-${callId}`;
    const token = new AccessToken(livekitApiKey, livekitApiSecret, {
      identity: user.id,
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
      { url: livekitUrl, token: await token.toJwt(), roomName },
      { headers: corsHeaders },
    );
  } catch (error) {
    console.error(error);
    return Response.json(
      { error: 'Unable to prepare the call room.' },
      { status: 500, headers: corsHeaders },
    );
  }
});
