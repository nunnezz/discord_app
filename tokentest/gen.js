// Gera token LOCALMENTE com os MESMOS valores do console (passados por
// variáveis de ambiente) e os MESMOS parâmetros da Edge Function.
// Só imprime COMPRIMENTOS e prefixos — nunca o certificado.
const { RtcTokenBuilder, RtcRole } = require('agora-token');

const appId = process.env.T_APPID;
const cert = process.env.T_CERT;
const channel = 'x';
const uid = 1;
const expire = Math.floor(Date.now() / 1000) + 3600;

const token7 = RtcTokenBuilder.buildTokenWithUid(
  appId, cert, channel, uid, RtcRole.PUBLISHER, expire, expire
);

console.log('LIB   :', require('agora-token/package.json').version);
console.log('len(7 args):', token7.length, '| prefixo:', token7.slice(0, 4));
console.log('appid (32):', appId.length === 32 ? 'OK 32 chars' : 'ERR ' + appId.length);
console.log('cert  (32):', cert.length === 32 ? 'OK 32 chars' : 'ERR ' + cert.length);
