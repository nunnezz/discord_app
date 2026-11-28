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
import { RtcTokenBuilder, RtcRole } from 'npm:agora-token@2.0.7';

// TTL do token E dos privilégios, em SEGUNDOS (duração — não timestamp
// absoluto). A builder da lib 2.x espera durações nesses dois
// parâmetros: passar um timestamp absoluto (agora+3600) faz o token
// valer ~57 anos, e o Agora o rejeita (invalidToken).
const TOKEN_TTL_SECONDS = 3600;

// Variáveis do SERVIDOR (Dashboard → Edge Functions → Secrets). O App
// Certificate nunca vai para o app cliente — a função só devolve tokens.
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

    // Se o App Certificate não estiver configurado no servidor, o projeto
    // Agora está em Testing mode — nesse modo o Agora rejeita QUALQUER
    // token (mesmo assinado com "") e o correto é entrar SEM token.
    // Devolvemos token vazio; o app já trata isso (envia '').
    if (!AGORA_APP_CERTIFICATE) {
      return new Response(JSON.stringify({ token: '', testingMode: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Builder da lib 2.x: tokenExpire e privilegeExpire são
    // DURAÇÕES em segundos a partir de agora (não timestamps absolutos).
    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channelName,
      uid ?? 0,
      RtcRole.PUBLISHER,
      TOKEN_TTL_SECONDS,
      TOKEN_TTL_SECONDS,
    );

    return new Response(
      JSON.stringify({
        token,
        appId: AGORA_APP_ID,
        uid: uid ?? 0,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
