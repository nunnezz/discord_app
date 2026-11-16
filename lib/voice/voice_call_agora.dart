import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
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
  RtcEngineEx? _engine;
  bool _screenCaptureActive = false;
  String? _screenChannelName;
  int? _screenUid;

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
    int? screenShareUid,
    String? screenShareToken,
    required void Function(int uid) onUserJoined,
    required void Function(int uid) onUserLeft,
    void Function(int uid)? onJoinSuccess,
    void Function(String errorDescription)? onErrorOccurred,
    void Function(bool sharing)? onScreenShareStateChanged,
    String? token, // null = modo de teste (App em "Testing mode")
  }) async {
    final appId = AppConfig.agoraAppId;
    if (appId.isEmpty) {
      throw StateError('AGORA_APP_ID is not configured');
    }
    _screenChannelName = channelName;
    _screenUid = kIsWeb ? null : screenShareUid;

    _engine = createAgoraRtcEngineEx();
    await _engine!.initialize(RtcEngineContext(appId: appId));

    await _engine!.enableAudio();
    await _engine!.enableVideo();

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          debugPrint(
              'Entrou no canal $channelName de verdade (confirmado pelo Agora)');
          final uid = connection.localUid;
          if (uid != null) {
            if (kIsWeb) _screenUid = uid;
            onJoinSuccess?.call(uid);
          }
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
        onLocalVideoStateChanged: (source, state, reason) async {
          debugPrint(
            'Estado do vídeo local Agora: fonte=$source, estado=$state, motivo=$reason',
          );
          if (source != VideoSourceType.videoSourceScreen &&
              source != VideoSourceType.videoSourceScreenPrimary) {
            return;
          }
          if (state == LocalVideoStreamState.localVideoStreamStateCapturing ||
              state == LocalVideoStreamState.localVideoStreamStateEncoding) {
            onScreenShareStateChanged?.call(true);
          } else if (state ==
                  LocalVideoStreamState.localVideoStreamStateStopped ||
              state == LocalVideoStreamState.localVideoStreamStateFailed) {
            onScreenShareStateChanged?.call(false);
            _screenCaptureActive = false;
            try {
              await _updateScreenPublishing(false);
            } catch (error) {
              onErrorOccurred?.call(
                'Não foi possível encerrar a transmissão de tela: $error',
              );
            }
          }
        },
      ),
    );

    await _engine!.joinChannel(
      token: token ?? '', // vazio = modo de teste
      channelId: channelName,
      uid: 0,
      options: kIsWeb
          ? const ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleBroadcaster,
              channelProfile: ChannelProfileType.channelProfileCommunication,
              publishCameraTrack: false,
              publishScreenTrack: true,
              publishSecondaryScreenTrack: true,
              publishScreenCaptureVideo: true,
              publishScreenCaptureAudio: false,
            )
          : const ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleBroadcaster,
              channelProfile: ChannelProfileType.channelProfileCommunication,
              publishCameraTrack: false,
            ),
    );
    if (!kIsWeb) {
      if (screenShareUid == null || screenShareToken == null) {
        throw ArgumentError(
          'A conexão de compartilhamento exige UID e token nas plataformas nativas.',
        );
      }
      await _engine!.joinChannelEx(
        token: screenShareToken,
        connection: RtcConnection(
          channelId: channelName,
          localUid: screenShareUid,
        ),
        options: const ChannelMediaOptions(
          autoSubscribeAudio: false,
          autoSubscribeVideo: false,
          publishMicrophoneTrack: false,
          publishCameraTrack: false,
          publishScreenTrack: true,
          publishSecondaryScreenTrack: true,
          publishScreenCaptureVideo: true,
          publishScreenCaptureAudio: false,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
    }
  }

  Future<void> toggleMic(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
  }

  Future<void> toggleCamera(bool enabled) async {
    final engine = _engine;
    if (engine == null) return;
    if (enabled) {
      await engine.enableLocalVideo(true);
      await engine.startPreview();
      await engine.updateChannelMediaOptions(
        const ChannelMediaOptions(publishCameraTrack: true),
      );
    } else {
      await engine.updateChannelMediaOptions(
        const ChannelMediaOptions(publishCameraTrack: false),
      );
      await engine.stopPreview();
    }
  }

  Future<List<ScreenCaptureSourceInfo>> getScreenCaptureSources() async {
    final engine = _engine;
    if (engine == null) throw StateError('A chamada ainda não foi iniciada.');
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.windows &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return const [];
    }
    return engine.getScreenCaptureSources(
      thumbSize: const SIZE(width: 120, height: 68),
      iconSize: const SIZE(width: 48, height: 48),
      includeScreen: true,
    );
  }

  Future<void> startScreenShare({
    required int uid,
    ScreenCaptureSourceInfo? source,
  }) async {
    final engine = _engine;
    if (engine == null) throw StateError('A chamada ainda não foi iniciada.');

    if (kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      throw UnsupportedError(
        'Compartilhamento de tela não funciona na versão web do Cord no iPhone. '
        'Use um computador; para compartilhar no iPhone, é necessário um app iOS nativo com ReplayKit.',
      );
    }

    if (kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      throw UnsupportedError(
        'O navegador Android não oferece a captura de tela exigida pela versão web do Cord. '
        'Use um computador ou um app Android nativo com suporte a compartilhamento.',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
      throw UnsupportedError(
        'Compartilhamento no app iOS exige a extensão Broadcast Upload do Agora, que ainda não está configurada.',
      );
    }

    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await engine.startScreenCapture(
        const ScreenCaptureParameters2(captureAudio: false, captureVideo: true),
      );
    } else if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      if (source?.sourceId == null) {
        throw StateError('Selecione uma janela ou uma tela para compartilhar.');
      }
      const captureParams = ScreenCaptureParameters(
        captureMouseCursor: true,
        frameRate: 15,
      );
      final sourceId = source!.sourceId!;
      if (source.type ==
          ScreenCaptureSourceType.screencapturesourcetypeScreen) {
        await engine.startScreenCaptureByDisplayId(
          displayId: sourceId,
          regionRect: const Rectangle(x: 0, y: 0, width: 0, height: 0),
          captureParams: captureParams,
        );
      } else if (source.type ==
          ScreenCaptureSourceType.screencapturesourcetypeWindow) {
        await engine.startScreenCaptureByWindowId(
          windowId: sourceId,
          regionRect: const Rectangle(x: 0, y: 0, width: 0, height: 0),
          captureParams: captureParams,
        );
      } else {
        throw UnsupportedError('Esse tipo de compartilhamento não é aceito.');
      }
    } else {
      throw UnsupportedError(
        'Compartilhamento de tela não disponível nesta plataforma.',
      );
    }

    if (_screenUid != uid) {
      await engine.stopScreenCapture();
      throw StateError('A conexão de compartilhamento não está preparada.');
    }
    try {
      await _updateScreenPublishing(true);
    } catch (_) {
      await engine.stopScreenCapture();
      rethrow;
    }
    _screenCaptureActive = true;
  }

  Future<void> stopScreenShare() async {
    final engine = _engine;
    if (engine == null || !_screenCaptureActive) return;
    await engine.stopScreenCapture();
    await _updateScreenPublishing(false);
    _screenCaptureActive = false;
  }

  Future<void> _updateScreenPublishing(bool publish) async {
    final engine = _engine;
    final uid = _screenUid;
    final channelName = _screenChannelName;
    if (engine == null || uid == null || channelName == null) {
      throw StateError('A conexão de compartilhamento não está ativa.');
    }
    final options = ChannelMediaOptions(
      publishScreenTrack: publish,
      publishSecondaryScreenTrack: publish,
      publishScreenCaptureVideo: publish,
      publishScreenCaptureAudio: false,
      clientRoleType: ClientRoleType.clientRoleBroadcaster,
    );
    if (kIsWeb) {
      await engine.updateChannelMediaOptions(options);
    } else {
      await engine.updateChannelMediaOptionsEx(
        options: ChannelMediaOptions(
          autoSubscribeAudio: false,
          autoSubscribeVideo: false,
          publishMicrophoneTrack: false,
          publishCameraTrack: false,
          publishScreenTrack: publish,
          publishSecondaryScreenTrack: publish,
          publishScreenCaptureVideo: publish,
          publishScreenCaptureAudio: false,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
        connection: RtcConnection(channelId: channelName, localUid: uid),
      );
    }
  }

  Future<void> leaveChannel() async {
    final engine = _engine;
    if (engine == null) return;
    if (_screenCaptureActive) {
      await stopScreenShare();
    }
    await engine.leaveChannel();
    await engine.release();
    _engine = null;
    _screenUid = null;
    _screenCaptureActive = false;
  }

  /// Widget de vídeo local, para colocar no seu grid de participantes.
  Widget localVideoView({bool screenShare = false}) {
    if (_engine == null) return const SizedBox.shrink();
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: VideoCanvas(
          uid: 0,
          sourceType: screenShare
              ? VideoSourceType.videoSourceScreen
              : VideoSourceType.videoSourceCamera,
        ),
      ),
    );
  }

  /// Widget de vídeo remoto de um participante específico.
  Widget remoteVideoView(
    int uid,
    String channelName, {
    required int localUid,
    bool screenShare = false,
  }) {
    if (_engine == null) return const SizedBox.shrink();
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(
          uid: uid,
          sourceType: screenShare
              ? VideoSourceType.videoSourceScreen
              : VideoSourceType.videoSourceCamera,
        ),
        connection: RtcConnection(channelId: channelName, localUid: localUid),
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
