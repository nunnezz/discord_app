// =========================================================================
// SUPABASE EDGE FUNCTION: gera tokens do Agora sob demanda.
//
// O App Certificate (a parte secreta) fica só aqui, como variável de
// ambiente do servidor — NUNCA no código do app Flutter. Isso resolve
// de vez o problema de "cada canal precisa de um token diferente":
// o app pede um token pra QUALQUER canal, na hora que for entrar nele,
// e essa função gera na hora, sempre válido.
// =========================================================================
import { serve } from 'https://deno.land/std@0.203.0/http/server.ts';
import { RtcTokenBuilder, RtcRole } from 'npm:agora-token@2.0.4';

const AGORA_APP_ID = Deno.env.get('AGORA_APP_ID')!;
const AGORA_APP_CERTIFICATE = Deno.env.get('AGORA_APP_CERTIFICATE')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Requisição de "preflight" do navegador (CORS) — só responde OK.
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { channelName, uid } = await req.json();

    if (!channelName || typeof channelName !== 'string') {
      return new Response(JSON.stringify({ error: 'channelName é obrigatório' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Token válido por 1 hora — tempo de sobra pra uma chamada de voz
    // normal. Se quiser chamadas mais longas, aumente esse valor.
    const expirationTimeInSeconds = 3600;
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;

    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channelName,
      uid ?? 0,
      RtcRole.PUBLISHER,
      privilegeExpiredTs,
    );

    return new Response(JSON.stringify({ token }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
