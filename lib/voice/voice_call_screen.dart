import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/dm_service.dart';
import '../services/friend_service.dart';
import '../services/supabase_client.dart';
import '../theme/app_theme.dart';
import 'voice_call_agora.dart';

// =========================================================================
// FORMATO DO CONVITE DE CHAMADA
// =========================================================================
// Um convite Ã© sÃ³ uma mensagem de DM com um formato especial no
// conteÃºdo. Quem recebe (na lista de conversas privadas) reconhece
// esse prefixo e mostra um cartÃ£o com botÃ£o "Entrar na chamada" em vez
// do balÃ£o de texto normal â€” ver o trecho correspondente em
// cord_home_page.dart (_DmMessagesList).
const String kVoiceInvitePrefix = 'VOICE_CALL_INVITE::';
const Duration kVoiceInviteLifetime = Duration(hours: 24);

bool isVoiceInviteExpired(DateTime expiresAt, {DateTime? now}) =>
    !expiresAt.isAfter(now ?? DateTime.now());

String buildVoiceInviteMessage(
        {required String roomId, required String channelName}) =>
    '$kVoiceInvitePrefix$roomId::$channelName';

/// Faz o caminho inverso: separa `roomId` e `channelName` de dentro do
/// conteÃºdo da mensagem. Retorna `null` se nÃ£o for um convite vÃ¡lido.
///
/// IMPORTANTE: usamos o ÃšLTIMO "::" como separador (nÃ£o um split
/// simples em 2 partes), porque o prÃ³prio `roomId` jÃ¡ contÃ©m "::"
/// dentro dele (Ã© `servidorId::nomeDoCanal`) â€” um split ingÃªnuo
/// contaria 3 pedaÃ§os em vez de 2 e falharia sempre que o roomId
/// tivesse mais de um "::".
({String roomId, String channelName})? parseVoiceInviteMessage(String content) {
  if (!content.startsWith(kVoiceInvitePrefix)) return null;
  final remainder = content.substring(kVoiceInvitePrefix.length);
  final separatorIndex = remainder.lastIndexOf('::');
  if (separatorIndex == -1) return null;

  final roomId = remainder.substring(0, separatorIndex);
  final channelName = remainder.substring(separatorIndex + 2);
  if (roomId.isEmpty || channelName.isEmpty) return null;

  return (roomId: roomId, channelName: channelName);
}

String? serverIdFromVoiceRoomId(String roomId) {
  final separatorIndex = roomId.indexOf('::');
  if (separatorIndex <= 0) return null;
  return roomId.substring(0, separatorIndex);
}

// =========================================================================
// PALETA (mesmo esquema usado no resto do app)
// =========================================================================
class _C {
  // Adaptativo: lÃª o tema global (AppTheme.isDark) para acompanhar o resto
  // do app. No claro: superfÃ­cies off-white; no escuro: slate navy.
  static bool get _dark => AppTheme.isDark;
  static Color get bg =>
      _dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  static Color get card => _dark
      ? const Color(0xFF1E293B).withValues(alpha: 0.85)
      : Colors.white.withValues(alpha: 0.85);
  static Color get darker =>
      _dark ? const Color(0xFF0B0F1A) : const Color(0xFFFFFFFF);
  static Color get divider =>
      _dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  static Color get blurple =>
      _dark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
  static Color get green =>
      _dark ? const Color(0xFF38BDF8) : const Color(0xFF0EA5E9);
  static const red = Color(0xFFE11D48);
  static Color get textMuted =>
      _dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color get textHeader =>
      _dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

  static List<BoxShadow> get softShadow => _dark
      ? [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ];
}

/// Um participante na chamada, com os dados reais vindos do Presence do
/// Supabase (nome/avatar) â€” nÃ£o apenas o `uid` numÃ©rico que o Agora usa
/// internamente pra identificar cada stream de Ã¡udio/vÃ­deo.
class _VoiceParticipant {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool micMuted;
  final bool cameraOn;
  final bool screenSharing;
  final int? agoraUid;
  final int? screenAgoraUid;
  final bool isLocal;

  const _VoiceParticipant({
    required this.userId,
    required this.displayName,
    required this.micMuted,
    required this.cameraOn,
    required this.screenSharing,
    required this.isLocal,
    this.agoraUid,
    this.screenAgoraUid,
    this.avatarUrl,
  });
}

// =========================================================================
// TELA DE CHAMADA DE VOZ/VÃDEO â€” funciona com vÃ¡rias pessoas ao mesmo
// tempo (via Agora, um SFU de verdade â€” ver explicaÃ§Ã£o em
// voice_call_agora.dart sobre por que isso nÃ£o Ã© WebRTC puro).
// =========================================================================
class VoiceCallScreen extends StatefulWidget {
  /// Nome exibido na tela (ex: "Sala de Voz").
  final String channelName;

  /// Identificador ÃšNICO do canal de voz para o Agora e para o
  /// Presence â€” combine servidor + canal (ex: "serverId::channelName")
  /// pra dois canais com o mesmo nome em servidores diferentes nunca
  /// caÃ­rem na mesma "sala" por engano.
  final String roomId;

  final String myUserId;
  final String myDisplayName;
  final String? myAvatarUrl;

  /// Chamado quando a chamada termina (desconectar) â€” a pÃ¡gina host remove
  /// o overlay. Substitui o Navigator.pop, porque a call agora vive como
  /// overlay interno da pÃ¡gina, nÃ£o como rota.
  final VoidCallback? onExit;

  const VoiceCallScreen({
    super.key,
    required this.channelName,
    required this.roomId,
    required this.myUserId,
    required this.myDisplayName,
    this.myAvatarUrl,
    this.onExit,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

/// A chamada NÃƒO Ã© mais aberta via rota â€” veja CordHomePage._activeCall.
/// A funÃ§Ã£o abaixo continua existindo sÃ³ para compatibilidade de imports.

Route<void> buildVoiceCallRoute(VoiceCallScreen screen) =>
    _TransparentCallRoute(screen: screen);

/// Rota transparente SEM ModalBarrier.
///
/// Toda PageRoute comum insere um ModalBarrier que absorve os toques da
/// tela inteira â€” mesmo com `opaque: false` e `barrierColor: null`. Com a
/// chamada minimizada, essa barreira invisÃ­vel (no topo da pilha do
/// Navigator) bloqueava TODOS os cliques no app por baixo.
///
/// Aqui a barreira nÃ£o existe: quando a call estÃ¡ aberta, o Scaffold dela
/// cobre a tela e recebe os toques naturalmente; quando minimizada, sÃ³ o
/// overlay flutuante Ã© clicÃ¡vel e o resto passa para o app por baixo.
class _TransparentCallRoute extends PageRoute<void> {
  _TransparentCallRoute({required this.screen});

  final VoiceCallScreen screen;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      screen;

  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final VoiceCallService _voiceService = VoiceCallService();
  late final RealtimeChannel _presenceChannel;

  bool _micMuted = false;
  bool _cameraOn = false;
  bool _screenSharing = false;
  bool _connecting = true;
  bool _agoraJoinConfirmed = false;
  bool _isMinimized = false;
  int? _localAgoraUid;
  int? _localScreenAgoraUid;
  String? _errorMessage;

  // Mapeia o `uid` numÃ©rico do Agora -> dados reais do participante,
  // resolvidos via Presence (que compartilha nome/avatar/estado do mic
  // entre todo mundo na "sala", sem precisar de nenhuma tabela nova no
  // banco â€” Presence Ã© efÃªmero e limpa sozinho quando alguÃ©m sai).
  final Set<int> _remoteUids = {};

  @override
  void initState() {
    super.initState();
    _joinEverything();
  }

  Future<void> _joinEverything() async {
    try {
      // 1. Entra no canal de Presence do Supabase â€” Ã© isso que dÃ¡ nome
      // e avatar reais aos participantes, em vez de sÃ³ "uid 8271".
      _presenceChannel = supabase.channel('voice:${widget.roomId}');
      _presenceChannel.onPresenceSync((_) {
        if (mounted) setState(() {});
      }).subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await _trackPresence();
        }
      });

      // 2. Busca um token de verdade na Edge Function â€” funciona pra
      // QUALQUER canal, gerado na hora, sempre vÃ¡lido. O App
      // Certificate (a parte secreta) nunca sai do servidor.
      final tokenResponse = await supabase.functions.invoke(
        'agora-token',
        body: {'channelName': widget.roomId, 'uid': 0},
      );
      final token = (tokenResponse.data as Map)['token'] as String;
      final screenUid = kIsWeb ? null : Random.secure().nextInt(0x7ffffffe) + 1;
      String? screenToken;
      if (screenUid != null) {
        final screenTokenResponse = await supabase.functions.invoke(
          'agora-token',
          body: {'channelName': widget.roomId, 'uid': screenUid},
        );
        screenToken = (screenTokenResponse.data as Map)['token'] as String;
      }
      _localScreenAgoraUid = screenUid;

      // 3. Entra no canal de voz de verdade (Agora), com esse token.
      await _voiceService.joinChannel(
        channelName: widget.roomId,
        screenShareUid: screenUid,
        screenShareToken: screenToken,
        token: token,
        onUserJoined: (uid) => setState(() => _remoteUids.add(uid)),
        onUserLeft: (uid) => setState(() {
          _remoteUids.remove(uid);
        }),
        onJoinSuccess: (uid) async {
          _localAgoraUid = uid;
          if (kIsWeb) _localScreenAgoraUid = uid;
          if (mounted) setState(() => _agoraJoinConfirmed = true);
          await _trackPresence();
        },
        onScreenShareStateChanged: (sharing) async {
          if (!mounted) return;
          if (_screenSharing != sharing) setState(() => _screenSharing = sharing);
          // ForÃ§a reconstruir o tile de preview local â€” sem isso, o Agora
          // Ã s vezes nÃ£o associa o VideoView ao stream de tela no web.
          setState(() {});
          await _trackPresence();
        },
        onErrorOccurred: (description) {
          if (mounted) {
            setState(() => _errorMessage = 'Erro do Agora: $description');
          }
        },
      );

      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _errorMessage = _friendlyVoiceError(e);
        });
      }
    }
  }

  Future<void> _trackPresence() async {
    await _presenceChannel.track({
      'user_id': widget.myUserId,
      'display_name': widget.myDisplayName,
      'avatar_url': widget.myAvatarUrl,
      'mic_muted': _micMuted,
      'camera_on': _cameraOn,
      'screen_sharing': _screenSharing,
      'agora_uid': _localAgoraUid,
      'screen_uid': _localScreenAgoraUid,
    });
  }

  /// Traduz os erros mais comuns do Agora/navegador para uma frase
  /// legÃ­vel, em vez de despejar o stack trace tÃ©cnico na tela.
  String _friendlyVoiceError(Object e) {
    final raw = e.toString();
    if (raw.contains('NotFoundError') ||
        raw.contains('Requested device not found')) {
      return 'Nenhum microfone foi encontrado neste dispositivo. '
          'VocÃª entrou na chamada, mas nÃ£o vai conseguir falar atÃ© conectar um microfone.';
    }
    if (raw.contains('NotAllowedError') || raw.contains('Permission denied')) {
      return 'PermissÃ£o de microfone negada. Libere o acesso ao microfone '
          'nas configuraÃ§Ãµes do navegador e recarregue a pÃ¡gina.';
    }
    return 'NÃ£o foi possÃ­vel conectar: $raw';
  }

  Future<void> _toggleMic() async {
    final muted = !_micMuted;
    try {
      await _voiceService.toggleMic(muted);
      if (!mounted) return;
      setState(() => _micMuted = muted);
      await _trackPresence();
    } catch (error) {
      _showCallError('NÃ£o foi possÃ­vel alterar o microfone: $error');
    }
  }

  Future<void> _toggleCamera() async {
    final enabled = !_cameraOn;
    try {
      await _voiceService.toggleCamera(enabled);
      if (!mounted) return;
      setState(() => _cameraOn = enabled);
      await _trackPresence();
    } catch (error) {
      _showCallError('NÃ£o foi possÃ­vel alterar a cÃ¢mera: $error');
    }
  }

  bool get _usesDesktopSourcePicker =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<ScreenCaptureSourceInfo?> _chooseScreenCaptureSource() async {
    final sources = await _voiceService.getScreenCaptureSources();
    if (sources.isEmpty) {
      throw StateError('NÃ£o foi encontrada nenhuma tela ou janela disponÃ­vel.');
    }
    if (!mounted) return null;

    return showDialog<ScreenCaptureSourceInfo>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _C.card,
        title: const Text('Compartilhar tela'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final source in sources)
                ListTile(
                  leading: Icon(
                    source.type ==
                            ScreenCaptureSourceType
                                .screencapturesourcetypeScreen
                        ? Icons.monitor_rounded
                        : Icons.window_rounded,
                    color: _C.blurple,
                  ),
                  title: Text(source.sourceName ?? 'Janela sem nome'),
                  subtitle: Text(
                    source.type ==
                            ScreenCaptureSourceType
                                .screencapturesourcetypeScreen
                        ? 'Tela inteira'
                        : 'Programa',
                  ),
                  onTap: () => Navigator.pop(context, source),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleScreenShare() async {
    final sharing = !_screenSharing;
    try {
      if (!sharing) {
        await _voiceService.stopScreenShare();
      } else {
        final source = _usesDesktopSourcePicker
            ? await _chooseScreenCaptureSource()
            : null;
        if (source == null && _usesDesktopSourcePicker) return;
        final screenUid = _localScreenAgoraUid;
        if (screenUid == null) {
          throw StateError('A conexÃ£o da chamada ainda nÃ£o estÃ¡ pronta.');
        }
        await _voiceService.startScreenShare(
          uid: screenUid,
          source: source,
        );
      }
      if (!mounted) return;
      setState(() => _screenSharing = sharing);
      await _trackPresence();
    } catch (error) {
      if (error is UnsupportedError) {
        _showCallError(error.message?.toString() ??
            'O compartilhamento de tela nÃ£o estÃ¡ disponÃ­vel nesta plataforma.');
      } else {
        _showCallError('NÃ£o foi possÃ­vel compartilhar a tela: $error');
      }
    }
  }

  Future<void> _showScreenShareFullscreen(_VoiceParticipant participant) async {
    final Widget streamView;
    if (participant.isLocal) {
      streamView = _voiceService.localVideoView(screenShare: true);
    } else {
      final uid = participant.screenAgoraUid;
      final localUid = _localAgoraUid;
      if (uid == null || localUid == null) return;
      streamView = _voiceService.remoteVideoView(
        uid,
        widget.roomId,
        localUid: localUid,
        screenShare: !kIsWeb,
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: streamView),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.screen_share_rounded,
                          color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'TransmissÃ£o de ${participant.displayName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Voltar Ã  chamada',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCallError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _disconnect() async {
    // Ignora falha do Agora: mesmo se leaveChannel() estourar (engine já
    // morta, ex: após o erro -1 de conexão), a UI precisa sair da call.
    try {
      await _voiceService.leaveChannel();
    } catch (_) {}
    try {
      await supabase.removeChannel(_presenceChannel);
    } catch (_) {}
    if (mounted) {
      if (widget.onExit != null) {
        widget.onExit!();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _openInviteDialog() async {
    await showDialog(
      context: context,
      builder: (_) => _InviteFriendsDialog(
        myUserId: widget.myUserId,
        roomId: widget.roomId,
        channelName: widget.channelName,
      ),
    );
  }

  @override
  void dispose() {
    // Se o host remover o overlay sem passar pelo botÃ£o de desconectar,
    // ainda assim liberamos o microfone/cÃ¢mera e saÃ­mos do Presence.
    _voiceService.leaveChannel();
    supabase.removeChannel(_presenceChannel);
    super.dispose();
  }

  List<_VoiceParticipant> _buildParticipants() {
    // Cruza os `uid`s remotos que o Agora reportou com os dados de
    // Presence mais recentes (que trazem nome/avatar/estado do mic).
    final presenceState = _presenceChannel.presenceState();
    final othersPresence = <String, Map<String, dynamic>>{};
    for (final entry in presenceState) {
      for (final p in entry.presences) {
        final payload = p.payload;
        final userId = payload['user_id'] as String?;
        if (userId != null && userId != widget.myUserId) {
          othersPresence[userId] = payload;
        }
      }
    }

    final others = othersPresence.values.map((payload) {
      final uidValue = payload['agora_uid'];
      final uid = uidValue is num
          ? uidValue.toInt()
          : int.tryParse(uidValue?.toString() ?? '');
      final screenUidValue = payload['screen_uid'];
      final screenUid = screenUidValue is num
          ? screenUidValue.toInt()
          : int.tryParse(screenUidValue?.toString() ?? '');
      return _VoiceParticipant(
        userId: payload['user_id'] as String,
        displayName: payload['display_name'] as String? ?? 'AlguÃ©m',
        avatarUrl: payload['avatar_url'] as String?,
        micMuted: payload['mic_muted'] as bool? ?? false,
        cameraOn: payload['camera_on'] as bool? ?? false,
        screenSharing: payload['screen_sharing'] as bool? ?? false,
        agoraUid: uid != null && _remoteUids.contains(uid) ? uid : null,
        screenAgoraUid: screenUid != null && _remoteUids.contains(screenUid)
            ? screenUid
            : null,
        isLocal: false,
      );
    }).toList();

    return [
      _VoiceParticipant(
        userId: widget.myUserId,
        displayName: '${widget.myDisplayName} (vocÃª)',
        avatarUrl: widget.myAvatarUrl,
        micMuted: _micMuted,
        cameraOn: _cameraOn,
        screenSharing: _screenSharing,
        agoraUid: _localAgoraUid,
        screenAgoraUid: _localScreenAgoraUid,
        isLocal: true,
      ),
      ...others,
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Sem PopScope: nÃ£o somos uma rota. O botÃ£o "minimizar" apenas troca
    // o layout â€” e, minimizado, este widget Ã© um Stack pequeno no canto,
    // deixando todo o resto do app clicÃ¡vel por baixo.
    return _isMinimized
        ? _buildMinimizedCallOverlay(context)
        : _buildCallScreen();
  }

  Widget _buildCallScreen() {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: [
            _CallTopBar(
              channelName: widget.channelName,
              // SÃ³ mostra "Conectado" quando o Agora CONFIRMOU de
              // verdade (onJoinSuccess) â€” nÃ£o apenas quando o comando
              // de entrar foi enviado sem erro. Isso evita a tela
              // mentir "Conectado" enquanto o Ã¡udio na real nunca saiu
              // do lugar (ex: token invÃ¡lido, erro de rede).
              connecting: _connecting || !_agoraJoinConfirmed,
              onInvite: _openInviteDialog,
              onMinimize: () => setState(() => _isMinimized = true),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child:
                    Text(_errorMessage!, style: TextStyle(color: _C.red)),
              ),
            Expanded(
              child: _connecting
                  ? Center(child: CircularProgressIndicator(color: _C.blurple))
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final participants = _buildParticipants();
                          final int columns = constraints.maxWidth > 900
                              ? 3
                              : constraints.maxWidth > 560
                                  ? 2
                                  : 1;
                          return GridView.builder(
                            itemCount: participants.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 16 / 10,
                            ),
                            itemBuilder: (context, index) {
                              final participant = participants[index];
                              Widget? videoView;
                              Widget? secondaryVideoView;
                              if (participant.isLocal) {
                                if (participant.screenSharing) {
                                  videoView = _voiceService.localVideoView(
                                    screenShare: true,
                                  );
                                  if (participant.cameraOn) {
                                    secondaryVideoView =
                                        _voiceService.localVideoView();
                                  }
                                } else if (participant.cameraOn) {
                                  videoView = _voiceService.localVideoView();
                                }
                              } else if (_localAgoraUid != null &&
                                  participant.screenSharing &&
                                  participant.screenAgoraUid != null) {
                                videoView = _voiceService.remoteVideoView(
                                  participant.screenAgoraUid!,
                                  widget.roomId,
                                  localUid: _localAgoraUid!,
                                );
                                if (participant.cameraOn &&
                                    participant.agoraUid != null) {
                                  secondaryVideoView =
                                      _voiceService.remoteVideoView(
                                    participant.agoraUid!,
                                    widget.roomId,
                                    localUid: _localAgoraUid!,
                                  );
                                }
                              } else if (_localAgoraUid != null &&
                                  participant.cameraOn &&
                                  participant.agoraUid != null) {
                                videoView = _voiceService.remoteVideoView(
                                  participant.agoraUid!,
                                  widget.roomId,
                                  localUid: _localAgoraUid!,
                                );
                              }
                              return _ParticipantTile(
                                key: ValueKey(participant.userId),
                                participant: participant,
                                videoView: videoView,
                                secondaryVideoView: secondaryVideoView,
                                onExpandScreenShare: participant.screenSharing
                                    ? () => _showScreenShareFullscreen(
                                          participant,
                                        )
                                    : null,
                              );
                            },
                          );
                        },
                      ),
                    ),
            ),
            _CallControlBar(
              micMuted: _micMuted,
              cameraOn: _cameraOn,
              screenSharing: _screenSharing,
              onToggleMic: _toggleMic,
              onToggleCamera: _toggleCamera,
              onToggleScreenShare: _toggleScreenShare,
              onDisconnect: _disconnect,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimizedCallOverlay(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Stack cujo ÃšNICO filho Ã© o mini-player posicionado no canto. Um Stack
    // sÃ³ ocupa (e captura cliques) na Ã¡rea dos seus filhos â€” o resto do
    // aplicativo por baixo permanece totalmente clicÃ¡vel.
    if (size.width < 600) {
      return Stack(
        children: [
          Positioned(
            right: 12,
            bottom: 12,
            child: Tooltip(
              message: '${widget.channelName} â€” voltar Ã  chamada',
              child: Material(
                color: _C.blurple,
                elevation: 12,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _isMinimized = false),
                  child: const SizedBox(
                    width: 56,
                    height: 56,
                    child:
                        Icon(Icons.call_rounded, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final width = min(360.0, size.width - 24);
    return Stack(
      children: [
        Positioned(
          right: 12,
          bottom: 12,
          width: width,
          child: Material(
            color: _C.card,
            elevation: 12,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  child: Row(
                    children: [
                      Icon(Icons.volume_up_rounded, color: _C.textMuted, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.channelName,
                          style: TextStyle(color: _C.textHeader,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Voltar Ã  chamada',
                        onPressed: () => setState(() => _isMinimized = false),
                        icon: Icon(Icons.open_in_full_rounded, color: _C.textMuted),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _C.divider),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip:
                            _micMuted ? 'Ativar microfone' : 'Mutar microfone',
                        onPressed: _toggleMic,
                        icon: Icon(
                          _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: _micMuted ? _C.red : _C.textHeader,
                        ),
                      ),
                      IconButton(
                        tooltip: _cameraOn ? 'Desligar cÃ¢mera' : 'Ligar cÃ¢mera',
                        onPressed: _toggleCamera,
                        icon: Icon(
                          _cameraOn
                              ? Icons.videocam_rounded
                              : Icons.videocam_off_rounded,
                          color: _C.textHeader,
                        ),
                      ),
                      IconButton(
                        tooltip: _screenSharing
                            ? 'Parar compartilhamento'
                            : 'Compartilhar tela',
                        onPressed: _toggleScreenShare,
                        icon: Icon(
                          _screenSharing
                              ? Icons.stop_screen_share_rounded
                              : Icons.screen_share_rounded,
                          color: _screenSharing ? _C.blurple : _C.textHeader,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Desconectar',
                        onPressed: _disconnect,
                        icon: Icon(Icons.call_end_rounded, color: _C.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CallTopBar extends StatelessWidget {
  final String channelName;
  final bool connecting;
  final VoidCallback onInvite;
  final VoidCallback onMinimize;
  const _CallTopBar(
      {required this.channelName,
      required this.connecting,
      required this.onInvite,
      required this.onMinimize});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _C.divider))),
      child: Row(
        children: [
          Icon(Icons.volume_up_rounded, color: _C.textMuted, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(channelName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _C.textHeader,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          IconButton(
            tooltip: 'Convidar amigos',
            icon:
                Icon(Icons.person_add_alt_1_rounded, color: _C.textMuted),
            onPressed: onInvite,
          ),
          IconButton(
            tooltip: 'Minimizar chamada e continuar usando o app',
            icon: Icon(Icons.picture_in_picture_alt_rounded, color: _C.textMuted),
            onPressed: onMinimize,
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (connecting ? Colors.orange : _C.green).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: connecting ? Colors.orange : _C.green),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle,
                    color: connecting ? Colors.orange : _C.green, size: 8),
                const SizedBox(width: 6),
                Text(connecting ? 'Conectando...' : 'Conectado',
                    style: TextStyle(
                        color: connecting ? Colors.orange : _C.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final _VoiceParticipant participant;
  final Widget? videoView;
  final Widget? secondaryVideoView;
  final VoidCallback? onExpandScreenShare;

  const _ParticipantTile({
    super.key,
    required this.participant,
    required this.videoView,
    required this.secondaryVideoView,
    required this.onExpandScreenShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.transparent, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: participant.cameraOn || participant.screenSharing
                ? Container(
                    color: _C.bg,
                    alignment: Alignment.center,
                    child: videoView ??
                        Icon(Icons.videocam_rounded, color: _C.textMuted, size: 42),
                  )
                : Container(
                    color: _C.card,
                    alignment: Alignment.center,
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: _C.blurple,
                      backgroundImage: participant.avatarUrl != null
                          ? NetworkImage(participant.avatarUrl!)
                          : null,
                      child: participant.avatarUrl == null
                          ? Text(
                              participant.displayName.isNotEmpty
                                  ? participant.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
          ),
          if (secondaryVideoView != null)
            Positioned(
              right: 10,
              top: 10,
              width: 112,
              height: 68,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: secondaryVideoView!,
              ),
            ),
          if (onExpandScreenShare != null)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                child: IconButton(
                  tooltip: 'Assistir transmissÃ£o em tela cheia',
                  onPressed: onExpandScreenShare,
                  icon:
                      const Icon(Icons.fullscreen_rounded, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    participant.micMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    color: participant.micMuted ? _C.red : _C.green,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(participant.displayName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                  if (participant.screenSharing) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.screen_share_rounded,
                        color: Colors.white, size: 14),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallControlBar extends StatelessWidget {
  final bool micMuted;
  final bool cameraOn;
  final bool screenSharing;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onDisconnect;

  const _CallControlBar({
    required this.micMuted,
    required this.cameraOn,
    required this.screenSharing,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onToggleScreenShare,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: _C.divider))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CallActionButton(
            icon: micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            isActive: micMuted,
            tooltip: micMuted ? 'Ativar microfone' : 'Mutar microfone',
            onTap: onToggleMic,
          ),
          const SizedBox(width: 16),
          _CallActionButton(
            icon:
                cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            isActive: !cameraOn,
            tooltip: cameraOn ? 'Desligar cÃ¢mera' : 'Ligar cÃ¢mera',
            onTap: onToggleCamera,
          ),
          const SizedBox(width: 16),
          _CallActionButton(
            icon: screenSharing
                ? Icons.stop_screen_share_rounded
                : Icons.screen_share_rounded,
            isActive: screenSharing,
            tooltip:
                screenSharing ? 'Parar compartilhamento' : 'Compartilhar tela',
            onTap: onToggleScreenShare,
          ),
          const SizedBox(width: 24),
          _CallActionButton(
            icon: Icons.call_end_rounded,
            isActive: false,
            isDisconnect: true,
            tooltip: 'Desconectar',
            onTap: onDisconnect,
          ),
        ],
      ),
    );
  }
}

class _CallActionButton extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final bool isDisconnect;
  final String tooltip;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.isActive,
    required this.tooltip,
    required this.onTap,
    this.isDisconnect = false,
  });

  @override
  State<_CallActionButton> createState() => _CallActionButtonState();
}

class _CallActionButtonState extends State<_CallActionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final Color bgColor = widget.isDisconnect
        ? _C.red
        : (widget.isActive ? Colors.white : _C.darker);
    final Color iconColor = widget.isDisconnect
        ? Colors.white
        : (widget.isActive ? Colors.black : Colors.white);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.isDisconnect ? 64 : 52,
            height: 52,
            transform: Matrix4.identity()..scale(_hovering ? 1.06 : 1.0),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius:
                  BorderRadius.circular(widget.isDisconnect ? 26 : 16),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, color: iconColor, size: 24),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// DIÃLOGO "CONVIDAR AMIGOS" â€” lista os amigos aceitos e manda um convite
// (mensagem de DM especial, ver kVoiceInvitePrefix) para cada um
// selecionado.
// =========================================================================
class _InviteFriendsDialog extends StatefulWidget {
  final String myUserId;
  final String roomId;
  final String channelName;

  const _InviteFriendsDialog({
    required this.myUserId,
    required this.roomId,
    required this.channelName,
  });

  @override
  State<_InviteFriendsDialog> createState() => _InviteFriendsDialogState();
}

class _InviteFriendsDialogState extends State<_InviteFriendsDialog> {
  late Future<List<Profile>> _friendsFuture;
  final Set<String> _invitedFriendIds = {};
  final Set<String> _sendingFriendIds = {};

  @override
  void initState() {
    super.initState();
    _friendsFuture = FriendService.fetchAcceptedFriends(widget.myUserId);
  }

  Future<void> _invite(Profile friend) async {
    setState(() => _sendingFriendIds.add(friend.id));
    try {
      final conversationId = await DmService.getOrCreateConversation(friend.id);
      await DmService.sendMessage(
        conversationId: conversationId,
        senderId: widget.myUserId,
        content: buildVoiceInviteMessage(
            roomId: widget.roomId, channelName: widget.channelName),
      );
      if (mounted) {
        setState(() {
          _invitedFriendIds.add(friend.id);
          _sendingFriendIds.remove(friend.id);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingFriendIds.remove(friend.id));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao convidar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _C.darker,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Convidar amigos',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Para "${widget.channelName}"',
                  style: TextStyle(color: _C.textMuted, fontSize: 13)),
              const SizedBox(height: 16),
              Flexible(
                child: FutureBuilder<List<Profile>>(
                  future: _friendsFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child:
                                CircularProgressIndicator()),
                      );
                    }
                    final friends = snapshot.data!;
                    if (friends.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Você ainda não tem amigos adicionados.',
                            style: TextStyle(color: _C.textMuted)),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: friends.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        final invited = _invitedFriendIds.contains(friend.id);
                        final sending = _sendingFriendIds.contains(friend.id);

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: _C.blurple,
                            backgroundImage: friend.avatarUrl != null
                                ? NetworkImage(friend.avatarUrl!)
                                : null,
                            child: friend.avatarUrl == null
                                ? Text(friend.displayName[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white))
                                : null,
                          ),
                          title: Text(friend.displayName,
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text('@${friend.username}',
                              style: TextStyle(color: _C.textMuted, fontSize: 12)),
                          trailing: invited
                              ? Icon(Icons.check_circle_rounded,
                                  color: _C.green)
                              : sending
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: _C.blurple))
                                  : OutlinedButton(
                                      onPressed: () => _invite(friend),
                                      style: OutlinedButton.styleFrom(
                                        side:
                                            BorderSide(color: _C.blurple),
                                      ),
                                      child: Text('Convidar',
                                          style: TextStyle(color: _C.blurple)),
                                    ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Fechar',
                      style: TextStyle(color: _C.textMuted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



