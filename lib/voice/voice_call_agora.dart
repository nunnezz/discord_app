import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';

// =========================================================================
// CHAMADA DE VOZ/VÍDEO MULTIUSUÁRIO — Agora RTC Engine
// =========================================================================
//
// POR QUE NÃO WEBRTC PURO?
// WebRTC "puro" (via package:flutter_webrtc) conecta cada participante
// diretamente aos outros (topologia mesh). Com 2 pessoas funciona bem;
// com 5+ cada dispositivo precisa enviar seu próprio áudio/vídeo N-1
// vezes, o que sobrecarrega upload e CPU rapidinho. Para "várias pessoas
// no mesmo canal de voz" como o Discord faz de verdade, você precisa de
// um SFU (Selective Forwarding Unit) — um servidor que recebe uma cópia
// de cada participante e redistribui. Montar e escalar isso do zero é um
// projeto em si; por isso a recomendação é usar um serviço gerenciado.
//
// COMO CONFIGURAR:
// 1. Crie uma conta grátis em https://console.agora.io
// 2. Crie um projeto e copie o "App ID" (NÃO é a mesma coisa que a
//    "chave" — não confunda com as credenciais do Supabase).
// 3. Para produção, você precisa de um pequeno servidor (pode ser uma
//    Supabase Edge Function!) que gera um "token" temporário de acesso
//    por chamada — nunca gere o token direto no app, isso exige o
//    "App Certificate", que é secreto. Em modo de teste, o Agora permite
//    entrar em canais SEM token (Project → Config → "Testing mode"),
//    ótimo para prototipar antes de configurar o servidor de tokens.
//
// PERMISSÕES:
// - Android: adicione no AndroidManifest.xml:
//     <uses-permission android:name="android.permission.RECORD_AUDIO" />
//     <uses-permission android:name="android.permission.CAMERA" />
//     <uses-permission android:name="android.permission.INTERNET" />
// - iOS: adicione no Info.plist as chaves NSMicrophoneUsageDescription e
//   NSCameraUsageDescription.
// - Web: funciona direto no Chrome/Edge (pede permissão do navegador).

class VoiceCallService {
  RtcEngine? _engine;

  /// Chame ao entrar no canal de voz. `channelName` pode ser, por
  /// exemplo, o nome do canal de voz do Discord-clone (ex: "Sala Geral").
  /// `uid` pode ser 0 para o Agora gerar um automaticamente.
  ///
  /// IMPORTANTE: o Future desta função resolve quando o COMANDO de
  /// entrar foi enviado, não quando a conexão de fato foi confirmada.
  /// A confirmação real chega depois, de forma assíncrona, por
  /// `onJoinSuccess` — e qualquer falha (token inválido, permissão
  /// negada, etc.) chega por `onErrorOccurred`. Sem esses dois
  /// callbacks, uma falha de conexão fica invisível: a tela mostraria
  /// "conectado" mesmo sem áudio nenhum trafegando de verdade.
  Future<void> joinChannel({
    required String channelName,
    required void Function(int uid) onUserJoined,
    required void Function(int uid) onUserLeft,
    void Function()? onJoinSuccess,
    void Function(String errorDescription)? onErrorOccurred,
    String? token, // null = modo de teste (App em "Testing mode")
  }) async {
    final appId = AppConfig.agoraAppId;
    if (appId.isEmpty) {
      throw StateError('AGORA_APP_ID is not configured');
    }

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: appId));

    await _engine!.enableAudio();
    // Comente a linha abaixo se quiser SOMENTE voz (canal de voz puro,
    // como os "CANAIS DE VOZ" do seu app) e não precisar de vídeo.
    await _engine!.enableVideo();

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          debugPrint('Entrou no canal $channelName de verdade (confirmado pelo Agora)');
          onJoinSuccess?.call();
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          onUserJoined(remoteUid);
        },
        onUserOffline: (connection, remoteUid, reason) {
          onUserLeft(remoteUid);
        },
        onError: (err, msg) {
          final description = '$err — $msg';
          debugPrint('Erro Agora: $description');
          onErrorOccurred?.call(description);
        },
        onConnectionStateChanged: (connection, state, reason) {
          debugPrint('Estado da conexão Agora: $state (motivo: $reason)');
          if (state == ConnectionStateType.connectionStateFailed) {
            onErrorOccurred?.call('Conexão falhou (motivo: $reason)');
          }
        },
      ),
    );

    await _engine!.joinChannel(
      token: token ?? '', // vazio = modo de teste
      channelId: channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
  }

  Future<void> toggleMic(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
  }

  Future<void> toggleCamera(bool enabled) async {
    await _engine?.enableLocalVideo(enabled);
  }

  Future<void> leaveChannel() async {
    await _engine?.leaveChannel();
    await _engine?.release();
    _engine = null;
  }

  /// Widget de vídeo local, para colocar no seu grid de participantes.
  Widget localVideoView() {
    if (_engine == null) return const SizedBox.shrink();
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  /// Widget de vídeo remoto de um participante específico.
  Widget remoteVideoView(int uid, String channelName) {
    if (_engine == null) return const SizedBox.shrink();
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: channelName),
      ),
    );
  }
}

// =========================================================================
// COMO INTEGRAR NA SUA VoiceCallScreen JÁ EXISTENTE
// =========================================================================
// 1. No initState() da VoiceCallScreen, crie `final _voiceService =
//    VoiceCallService();` e chame `_voiceService.joinChannel(...)`.
// 2. Nos callbacks `onUserJoined`/`onUserLeft`, dê `setState` para
//    adicionar/remover o `uid` de uma lista `List<int> _remoteUids`.
// 3. No GridView de participantes, troque o placeholder de avatar por
//    `_voiceService.remoteVideoView(uid, channelName)` para cada uid
//    remoto, e `_voiceService.localVideoView()` para o card "você".
// 4. No botão de mutar/câmera, chame `_voiceService.toggleMic(...)` /
//    `toggleCamera(...)` — a UI (ícone ficando branco/vermelho) você já
//    tem pronta no _CallActionButton.
// 5. No botão vermelho de desconectar, chame
//    `await _voiceService.leaveChannel();` ANTES de `Navigator.pop()`.