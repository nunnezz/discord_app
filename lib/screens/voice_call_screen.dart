import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_client.dart';
import 'voice_call_agora.dart';

// =========================================================================
// PALETA (mesmo esquema usado no resto do app)
// =========================================================================
class _C {
  static const bg = Color(0xFF1A1B1E);
  static const card = Color(0xFF232428);
  static const darker = Color(0xFF2B2D31);
  static const divider = Color(0xFF3F4147);
  static const blurple = Color(0xFF5865F2);
  static const green = Color(0xFF23A55A);
  static const red = Color(0xFFDA373C);
  static const textMuted = Color(0xFF949BA4);
  static const textHeader = Color(0xFFF2F3F5);
}

/// Um participante na chamada, com os dados reais vindos do Presence do
/// Supabase (nome/avatar) — não apenas o `uid` numérico que o Agora usa
/// internamente pra identificar cada stream de áudio/vídeo.
class _VoiceParticipant {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool micMuted;
  final bool cameraOn;
  final bool isLocal;

  const _VoiceParticipant({
    required this.userId,
    required this.displayName,
    required this.micMuted,
    required this.cameraOn,
    required this.isLocal,
    this.avatarUrl,
  });
}

// =========================================================================
// TELA DE CHAMADA DE VOZ/VÍDEO — funciona com várias pessoas ao mesmo
// tempo (via Agora, um SFU de verdade — ver explicação em
// voice_call_agora.dart sobre por que isso não é WebRTC puro).
// =========================================================================
class VoiceCallScreen extends StatefulWidget {
  /// Nome exibido na tela (ex: "Sala de Voz").
  final String channelName;

  /// Identificador ÚNICO do canal de voz para o Agora e para o
  /// Presence — combine servidor + canal (ex: "serverId::channelName")
  /// pra dois canais com o mesmo nome em servidores diferentes nunca
  /// caírem na mesma "sala" por engano.
  final String roomId;

  final String myUserId;
  final String myDisplayName;
  final String? myAvatarUrl;

  const VoiceCallScreen({
    super.key,
    required this.channelName,
    required this.roomId,
    required this.myUserId,
    required this.myDisplayName,
    this.myAvatarUrl,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final VoiceCallService _voiceService = VoiceCallService();
  late final RealtimeChannel _presenceChannel;

  bool _micMuted = false;
  bool _cameraOn = false;
  bool _connecting = true;
  String? _errorMessage;

  // Mapeia o `uid` numérico do Agora -> dados reais do participante,
  // resolvidos via Presence (que compartilha nome/avatar/estado do mic
  // entre todo mundo na "sala", sem precisar de nenhuma tabela nova no
  // banco — Presence é efêmero e limpa sozinho quando alguém sai).
  final Map<int, Map<String, dynamic>> _remotePresenceByUid = {};
  final Set<int> _remoteUids = {};

  @override
  void initState() {
    super.initState();
    _joinEverything();
  }

  Future<void> _joinEverything() async {
    try {
      // 1. Entra no canal de Presence do Supabase — é isso que dá nome
      // e avatar reais aos participantes, em vez de só "uid 8271".
      _presenceChannel = supabase.channel('voice:${widget.roomId}');
      _presenceChannel.onPresenceSync((_) => setState(() {})).subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await _presenceChannel.track({
            'user_id': widget.myUserId,
            'display_name': widget.myDisplayName,
            'avatar_url': widget.myAvatarUrl,
            'mic_muted': _micMuted,
            'camera_on': _cameraOn,
          });
        }
      });

      // 2. Entra no canal de voz de verdade (Agora).
      await _voiceService.joinChannel(
        channelName: widget.roomId,
        onUserJoined: (uid) => setState(() => _remoteUids.add(uid)),
        onUserLeft: (uid) => setState(() {
          _remoteUids.remove(uid);
          _remotePresenceByUid.remove(uid);
        }),
      );

      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _errorMessage = 'Não foi possível conectar: $e';
        });
      }
    }
  }

  Future<void> _toggleMic() async {
    setState(() => _micMuted = !_micMuted);
    await _voiceService.toggleMic(_micMuted);
    await _presenceChannel.track({
      'user_id': widget.myUserId,
      'display_name': widget.myDisplayName,
      'avatar_url': widget.myAvatarUrl,
      'mic_muted': _micMuted,
      'camera_on': _cameraOn,
    });
  }

  Future<void> _toggleCamera() async {
    setState(() => _cameraOn = !_cameraOn);
    await _voiceService.toggleCamera(_cameraOn);
    await _presenceChannel.track({
      'user_id': widget.myUserId,
      'display_name': widget.myDisplayName,
      'avatar_url': widget.myAvatarUrl,
      'mic_muted': _micMuted,
      'camera_on': _cameraOn,
    });
  }

  Future<void> _disconnect() async {
    await _voiceService.leaveChannel();
    await supabase.removeChannel(_presenceChannel);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Se o usuário fechar/voltar sem passar pelo botão de desconectar
    // (ex: botão "voltar" do navegador), ainda assim liberamos o
    // microfone/câmera e saímos do Presence — senão a pessoa continua
    // "na sala" pros outros, mesmo tendo saído.
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

    final others = othersPresence.values
        .map((payload) => _VoiceParticipant(
              userId: payload['user_id'] as String,
              displayName: payload['display_name'] as String? ?? 'Alguém',
              avatarUrl: payload['avatar_url'] as String?,
              micMuted: payload['mic_muted'] as bool? ?? false,
              cameraOn: payload['camera_on'] as bool? ?? false,
              isLocal: false,
            ))
        .toList();

    return [
      _VoiceParticipant(
        userId: widget.myUserId,
        displayName: '${widget.myDisplayName} (você)',
        avatarUrl: widget.myAvatarUrl,
        micMuted: _micMuted,
        cameraOn: _cameraOn,
        isLocal: true,
      ),
      ...others,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: [
            _CallTopBar(channelName: widget.channelName, connecting: _connecting),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_errorMessage!, style: const TextStyle(color: _C.red)),
              ),
            Expanded(
              child: _connecting
                  ? const Center(child: CircularProgressIndicator(color: _C.blurple))
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
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 16 / 10,
                            ),
                            itemBuilder: (context, index) =>
                                _ParticipantTile(participant: participants[index]),
                          );
                        },
                      ),
                    ),
            ),
            _CallControlBar(
              micMuted: _micMuted,
              cameraOn: _cameraOn,
              onToggleMic: _toggleMic,
              onToggleCamera: _toggleCamera,
              onDisconnect: _disconnect,
            ),
          ],
        ),
      ),
    );
  }
}

class _CallTopBar extends StatelessWidget {
  final String channelName;
  final bool connecting;
  const _CallTopBar({required this.channelName, required this.connecting});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _C.divider))),
      child: Row(
        children: [
          const Icon(Icons.volume_up_rounded, color: _C.textMuted, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(channelName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _C.textHeader, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (connecting ? Colors.orange : _C.green).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: connecting ? Colors.orange : _C.green),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: connecting ? Colors.orange : _C.green, size: 8),
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
  const _ParticipantTile({required this.participant});

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
            child: participant.cameraOn
                ? Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_C.blurple, _C.bg],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    // Placeholder de vídeo — para exibir o vídeo real do
                    // Agora aqui, troque este Icon por
                    // `_voiceService.localVideoView()` (participante
                    // local) ou `.remoteVideoView(uid, roomId)`
                    // (participantes remotos, cruzando o uid do Agora
                    // com o userId do Presence).
                    child: Icon(Icons.videocam_rounded,
                        color: Colors.white.withOpacity(0.85), size: 42),
                  )
                : Container(
                    color: _C.card,
                    alignment: Alignment.center,
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: _C.blurple,
                      backgroundImage:
                          participant.avatarUrl != null ? NetworkImage(participant.avatarUrl!) : null,
                      child: participant.avatarUrl == null
                          ? Text(
                              participant.displayName.isNotEmpty
                                  ? participant.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    participant.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: participant.micMuted ? _C.red : _C.green,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(participant.displayName,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
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
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onDisconnect;

  const _CallControlBar({
    required this.micMuted,
    required this.cameraOn,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _C.divider))),
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
            icon: cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            isActive: !cameraOn,
            tooltip: cameraOn ? 'Desligar câmera' : 'Ligar câmera',
            onTap: onToggleCamera,
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
    final Color bgColor =
        widget.isDisconnect ? _C.red : (widget.isActive ? Colors.white : _C.darker);
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
              borderRadius: BorderRadius.circular(widget.isDisconnect ? 26 : 16),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, color: iconColor, size: 24),
          ),
        ),
      ),
    );
  }
}
