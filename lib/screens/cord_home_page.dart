import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/chat_media_service.dart';
import '../services/dm_service.dart';
import '../services/friend_service.dart';
import '../services/profile_service.dart';
import '../services/realtime_lifecycle_service.dart';
import '../services/server_service.dart';
import '../voice/voice_call_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

// =========================================================================
// PALETA — DESIGN SYSTEM LIGHT (Deep Indigo/Violet, estética Linear/Vercel)
// =========================================================================
// Neutros frios, acento indigo sofisticado, sem nenhum verde estilo
// mensageiro. Os NOMES das constantes foram mantidos (darkest, darker,
// blurple...) de propósito: toda a UI existente referencia _C e é
// re-estilizada automaticamente ao trocar os valores aqui.
class _C {
  // Fundos — neutros frios bem claros.
  static const darkest = Color(0xFFF8FAFC); // fundo do app (slate-50)
  static const darker = Color(0xFFFFFFFF); // sidebars / painéis
  static const chatBg = Color(0xFFF8FAFC); // área de chat
  static const inputBg = Color(0xFFFFFFFF); // campos de texto / cards

  // Estados de interação (tint indigo suave).
  static const hoverChannel = Color(0xFFF1F5F9); // slate-100
  static const activeChannel = Color(0xFFE8EAFD); // indigo tint

  // ACENTO: deep indigo/violet (estilo Linear).
  static const blurple = Color(0xFF6366F1);
  static const mintSoft = Color(0xFFEEF0FE); // tint p/ bolhas enviadas
  static const violet = Color(0xFF8B5CF6); // secundário p/ gradientes

  static const green = Color(0xFF0EA5E9); // "sucesso" agora é sky blue
  static const textNormal = Color(0xFF334155); // slate-700
  static const textMuted = Color(0xFF64748B); // slate-500
  static const textHeader = Color(0xFF0F172A); // slate-900
  static const divider = Color(0xFFE2E8F0); // slate-200
  static const red = Color(0xFFE11D48);

  // Sombras difusas (neumorphism suave) para cards flutuantes.
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withOpacity(0.06),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
}

class _ChatAvatar extends StatelessWidget {
  final String displayName;
  final String? avatarUrl;

  const _ChatAvatar({
    required this.displayName,
    required this.avatarUrl,
  });

  Widget _initial() {
    return Text(
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: _C.blurple,
        child: _initial(),
      );
    }

    return CircleAvatar(
      radius: 20,
      backgroundColor: _C.blurple,
      child: ClipOval(
        child: Image.network(
          avatarUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _initial(),
          errorBuilder: (context, error, stackTrace) => _initial(),
        ),
      ),
    );
  }
}

// =========================================================================
// ESTRUTURA DE CANAIS
// =========================================================================
// O servidor "Cord" (fixo, id 'default') continua usando esta lista
// ESTÁTICA de canais — mantido assim de propósito, para não arriscar
// quebrar nada do que você já testou. Já os SERVIDORES REAIS (criados
// pelo usuário, tabela `servers`) têm canais DINÂMICOS, vindos da
// tabela `channels` via ServerService — ver `_categoriesFromServerChannels`
// mais abaixo, que converte um `List<ServerChannelModel>` para este
// mesmo formato `CategoryDef`/`ChannelDef`, reaproveitando toda a UI.
enum ChannelType { text, voice }

class ChannelDef {
  final String name;
  final ChannelType type;
  final String? displayName;

  /// Id da linha na tabela `channels` (null = canal estático do servidor
  /// "Cord", que não vive no banco e por isso não pode ser editado).
  final String? id;

  const ChannelDef(this.name, this.type, {this.displayName, this.id});

  String get label => displayName ?? name;
}

class CategoryDef {
  final String title;
  final List<ChannelDef> channels;
  const CategoryDef(this.title, this.channels);
}

const List<CategoryDef> _builtInCategories = [
  CategoryDef('CANAIS DE TEXTO', [
    ChannelDef('geral', ChannelType.text, displayName: 'chat global'),
    ChannelDef('anúncios', ChannelType.text),
  ]),
  CategoryDef('CANAIS DE VOZ', [
    ChannelDef('Sala Geral', ChannelType.voice, displayName: 'Sala Global'),
  ]),
];

/// Id fixo do servidor "Cord" embutido no app (não tem linha na tabela
/// `servers` — é só uma constante usada como `server_id` nas mensagens).
const String kBuiltInServerId = 'default';

/// Converte os canais vindos do banco (`ServerChannelModel`, tabela
/// `channels`) para o mesmo formato `CategoryDef`/`ChannelDef` usado
/// pelo servidor "Cord" — assim toda a UI de canais (`_ChannelSidebar`,
/// `_CategorySection`, `_ChannelTile`) é 100% reaproveitada, sem
/// precisar de nenhuma versão "dinâmica" separada dos widgets.
List<CategoryDef> _categoriesFromServerChannels(
    List<ServerChannelModel> channels) {
  final textChannels = channels
      .where((c) => c.type == ServerChannelType.text)
      .map((c) => ChannelDef(c.name, ChannelType.text, id: c.id))
      .toList();
  final voiceChannels = channels
      .where((c) => c.type == ServerChannelType.voice)
      .map((c) => ChannelDef(c.name, ChannelType.voice, id: c.id))
      .toList();
  return [
    CategoryDef('CANAIS DE TEXTO', textChannels),
    CategoryDef('CANAIS DE VOZ', voiceChannels),
  ];
}

/// Qual "área" da barra lateral está ativa — igual ao Discord: ou você
/// está em "Amigos" (Home) ou dentro de um servidor. As duas são
/// mutuamente exclusivas e nunca aparecem misturadas na mesma coluna.
enum _NavArea { friends, server }

enum _ServerAction { create, discover, joinByInvite }

class _CreateServerData {
  final String name;
  final bool isPublic;

  const _CreateServerData({required this.name, required this.isPublic});
}

// =========================================================================
// CORD HOME PAGE
// =========================================================================
class CordHomePage extends StatefulWidget {
  final String userId;
  const CordHomePage({super.key, required this.userId});

  @override
  State<CordHomePage> createState() => _CordHomePageState();
}

class _CordHomePageState extends State<CordHomePage> {
  _NavArea navArea = _NavArea.server;

  // Chamada de voz ativa renderizada como OVERLAY dentro desta página
  // (Stack no build), em vez de rota no Navigator. Motivo: toda rota,
  // mesmo transparente, coloca uma barreira de foco/hit-test acima do
  // app; com a call minimizada isso impedia de usar o chat. Sem rota,
  // minimizada = só o mini-player flutuante sobre o app normal.
  VoiceCallScreen? _activeCall;

  // Servidor "Cord" fixo é sempre a opção inicial.
  String selectedServerId = kBuiltInServerId;
  List<ServerModel> myServers = [];

  // Canais do servidor selecionado no momento. Para o servidor "Cord"
  // (fixo), sempre é `_builtInCategories`. Para um servidor real, é
  // carregado do banco e guardado aqui.
  List<CategoryDef> currentCategories = _builtInCategories;
  bool loadingChannels = false;

  String selectedChannel = 'geral';
  bool showMembersPanel = true;

  String get _selectedChannelLabel {
    for (final category in currentCategories) {
      for (final channel in category.channels) {
        if (channel.type == ChannelType.text &&
            channel.name == selectedChannel) {
          return channel.label;
        }
      }
    }
    return selectedChannel;
  }

  // Conversa privada aberta no momento (null = mostrando a lista de
  // amigos, não uma conversa específica).
  DmConversation? activeDmConversation;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final TextEditingController _dmMessageController = TextEditingController();
  final ScrollController _dmScrollController = ScrollController();

  static const double _mobileBreakpoint = 700;

  @override
  void initState() {
    super.initState();
    _loadMyServers();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _dmMessageController.dispose();
    _dmScrollController.dispose();
    super.dispose();
  }

  ServerModel? get _activeServer {
    for (final server in myServers) {
      if (server.id == selectedServerId) return server;
    }
    return null;
  }

  Future<void> _loadMyServers() async {
    try {
      final servers = await ServerService.fetchMyServers(widget.userId);
      if (mounted) setState(() => myServers = servers);
    } catch (e) {
      // Falha silenciosa aqui é aceitável: o servidor "Cord" continua
      // funcionando normalmente mesmo se a lista de servidores extras
      // não carregar (ex: schema de servers ainda não foi criado).
      debugPrint('Erro ao carregar servidores: $e');
    }
  }

  Future<void> _refreshMyServersAfterVoiceInvite() async {
    try {
      final servers = await ServerService.fetchMyServers(widget.userId);
      if (mounted) setState(() => myServers = servers);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Não foi possível atualizar os servidores: $e')),
        );
      }
    }
  }

  /// Troca de servidor selecionado. Para o "Cord" fixo, os canais já
  /// são conhecidos (estáticos); para um servidor real, busca os
  /// canais no banco antes de exibir.
  Future<void> _selectServer(String serverId) async {
    if (serverId == kBuiltInServerId) {
      setState(() {
        selectedServerId = kBuiltInServerId;
        currentCategories = _builtInCategories;
        selectedChannel = 'geral';
      });
      return;
    }

    setState(() {
      selectedServerId = serverId;
      loadingChannels = true;
    });

    try {
      final channels = await ServerService.fetchChannels(serverId);
      final categories = _categoriesFromServerChannels(channels);
      final firstTextChannel = categories
          .expand((c) => c.channels)
          .firstWhere((c) => c.type == ChannelType.text,
              orElse: () => const ChannelDef('geral', ChannelType.text))
          .name;

      if (!mounted) return;
      setState(() {
        currentCategories = categories;
        selectedChannel = firstTextChannel;
        loadingChannels = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => loadingChannels = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao carregar canais: $e')));
      }
    }
  }

  /// Recarrega os canais do servidor selecionado (após criar/renomear/
  /// excluir um canal). Não mexe no canal selecionado — só atualiza a lista.
  Future<void> _loadChannels() async {
    final serverId = selectedServerId;
    if (serverId == kBuiltInServerId) return;
    try {
      final channels = await ServerService.fetchChannels(serverId);
      if (!mounted) return;
      setState(() => currentCategories = _categoriesFromServerChannels(channels));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao recarregar canais: $e')));
      }
    }
  }

  /// Abre o diálogo de criar servidor, cria de fato no banco e já
  /// seleciona o servidor recém-criado.
  Future<void> _createServer(BuildContext context) async {
    final serverData = await showDialog<_CreateServerData>(
      context: context,
      builder: (_) => const _CreateServerDialog(),
    );
    if (serverData == null || serverData.name.trim().isEmpty) return;

    try {
      await ServerService.createServer(
        name: serverData.name,
        isPublic: serverData.isPublic,
      );

      // Busca a lista atualizada em vez de usar o retorno do insert
      // (ver comentário em ServerService.createServer sobre por que
      // evitamos encadear .select() ali).
      final servers = await ServerService.fetchMyServers(widget.userId);
      if (!mounted) return;

      setState(() {
        myServers = servers;
        navArea = _NavArea.server;
      });

      // fetchMyServers ordena por joined_at crescente, então o
      // servidor recém-criado é sempre o último da lista.
      if (servers.isNotEmpty) {
        await _selectServer(servers.last.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao criar servidor: $e')));
      }
    }
  }

  Future<void> _openServerActions(BuildContext context) async {
    final action = await showDialog<_ServerAction>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Servidores'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ServerAction.create),
            child: const Text('Criar servidor'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ServerAction.discover),
            child: const Text('Explorar servidores públicos'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ServerAction.joinByInvite),
            child: const Text('Entrar com convite'),
          ),
        ],
      ),
    );

    if (action == _ServerAction.create) {
      await _createServer(context);
    } else if (action == _ServerAction.discover) {
      await _discoverPublicServers(context);
    } else if (action == _ServerAction.joinByInvite) {
      await _joinWithInvite(context);
    }
  }

  Future<void> _discoverPublicServers(BuildContext context) async {
    final serverId = await showDialog<String>(
      context: context,
      builder: (_) => const _PublicServersDialog(),
    );
    if (serverId == null) return;

    await _reloadAndSelectServer(serverId);
  }

  Future<void> _joinWithInvite(BuildContext context) async {
    final inviteCode = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinServerDialog(),
    );
    if (inviteCode == null || inviteCode.trim().isEmpty) return;

    try {
      final serverId = await ServerService.joinServerWithInvite(inviteCode);
      await _reloadAndSelectServer(serverId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível usar o convite: $e')),
        );
      }
    }
  }

  Future<void> _reloadAndSelectServer(String serverId) async {
    try {
      final servers = await ServerService.fetchMyServers(widget.userId);
      if (!mounted) return;
      setState(() {
        myServers = servers;
        navArea = _NavArea.server;
      });
      await _selectServer(serverId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar seus servidores: $e')),
        );
      }
    }
  }

  Future<void> _createServerInvite() async {
    if (selectedServerId == kBuiltInServerId) return;
    try {
      final code = await ServerService.createInvite(selectedServerId);
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Convite copiado. Ele expira em 7 dias.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao criar convite: $e')),
        );
      }
    }
  }

  Future<void> _toggleServerVisibility() async {
    final selectedServers =
        myServers.where((item) => item.id == selectedServerId).toList();
    if (selectedServers.isEmpty) return;
    final server = selectedServers.first;
    if (server.ownerId != widget.userId) return;

    try {
      await ServerService.setServerVisibility(
        serverId: server.id,
        isPublic: !server.isPublic,
      );
      final servers = await ServerService.fetchMyServers(widget.userId);
      if (!mounted) return;
      setState(() => myServers = servers);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            server.isPublic
                ? 'Servidor agora é privado.'
                : 'Servidor agora é público e aparece na descoberta.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao alterar privacidade: $e')),
        );
      }
    }
  }

  Future<void> _sendMessage(String channelName) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();

    try {
      await ChatService.sendMessage(
        channel: channelName,
        senderId: widget.userId,
        content: text,
        serverId: selectedServerId,
      );
      // Não inserimos a mensagem manualmente em lista nenhuma: o
      // StreamBuilder abaixo recebe a linha nova via Realtime sozinho,
      // inclusive para outros usuários vendo o mesmo canal.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao enviar mensagem: $e')));
      }
    }
  }

  Future<void> _sendDmMessage() async {
    final conversation = activeDmConversation;
    if (conversation == null) return;
    final text = _dmMessageController.text.trim();
    if (text.isEmpty) return;
    _dmMessageController.clear();

    try {
      await DmService.sendMessage(
        conversationId: conversation.id,
        senderId: widget.userId,
        content: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao enviar mensagem: $e')));
      }
    }
  }

  Future<void> _sendChannelMedia({
    required String channelName,
    required String serverId,
    required XFile file,
  }) async {
    final attachment = await ChatMediaService.upload(
      userId: widget.userId,
      file: file,
    );
    await ChatService.sendMessage(
      channel: channelName,
      serverId: serverId,
      senderId: widget.userId,
      content: _messageController.text,
      attachment: attachment,
    );
    _messageController.clear();
  }

  Future<void> _sendDmMedia(XFile file) async {
    final conversation = activeDmConversation;
    if (conversation == null) return;
    final attachment = await ChatMediaService.upload(
      userId: widget.userId,
      file: file,
    );
    await DmService.sendMessage(
      conversationId: conversation.id,
      senderId: widget.userId,
      content: _dmMessageController.text,
      attachment: attachment,
    );
    _dmMessageController.clear();
  }

  Future<void> _selectChannel(ChannelDef channel) async {
    if (channel.type == ChannelType.voice) {
      await _joinVoiceChannel(channel.name, displayName: channel.label);
      return;
    }
    setState(() => selectedChannel = channel.name);
  }

  /// Abre a tela de chamada de voz de verdade (Agora + Presence). O
  /// `roomId` combina servidor + canal para que dois canais com o
  /// mesmo nome em servidores diferentes nunca caiam na mesma "sala".
  Future<void> _joinVoiceChannel(
    String channelName, {
    String? displayName,
  }) async {
    Profile? profile;
    try {
      profile = await ProfileService.fetchProfile(widget.userId);
    } catch (_) {
      // Segue mesmo sem o perfil resolvido — a tela de chamada usa um
      // nome genérico como fallback (ver `myDisplayName` abaixo).
    }

    if (!mounted) return;
    setState(() {
      _activeCall = VoiceCallScreen(
        channelName: displayName ?? channelName,
        roomId: '$selectedServerId::$channelName',
        myUserId: widget.userId,
        myDisplayName: profile?.displayName ?? 'Você',
        myAvatarUrl: profile?.avatarUrl,
        onExit: () => setState(() => _activeCall = null),
      );
    });
  }

  /// Abre a chamada a partir de um convite recebido por DM (usado pelo
  /// _VoiceInviteCard, que vive numa subárvore e não tem acesso direto ao
  /// setState desta página).
  void _openVoiceInvite({
    required String roomId,
    required String channelName,
    String? fallbackName,
    String? avatarUrl,
  }) {
    final myUserId = widget.userId;
    Profile? profile;
    ProfileService.fetchProfile(myUserId)
        .then((p) {
          profile = p;
          if (!mounted) return;
          setState(() {
            _activeCall = VoiceCallScreen(
              channelName: channelName,
              roomId: roomId,
              myUserId: myUserId,
              myDisplayName: profile?.displayName ?? fallbackName ?? 'Você',
              myAvatarUrl: profile?.avatarUrl ?? avatarUrl,
              onExit: () => setState(() => _activeCall = null),
            );
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _activeCall = VoiceCallScreen(
              channelName: channelName,
              roomId: roomId,
              myUserId: myUserId,
              myDisplayName: fallbackName ?? 'Você',
              myAvatarUrl: avatarUrl,
              onExit: () => setState(() => _activeCall = null),
            );
          });
        });
  }

  // =========================================================================
  // GESTÃO DE CANAIS (só para o dono do servidor selecionado)
  // =========================================================================
  bool get _canManageChannels =>
      selectedServerId != kBuiltInServerId &&
      _activeServer?.ownerId == widget.userId;

  bool _isVoiceCategoryTitle(String title) =>
      title.toUpperCase().contains('VOZ');

  Future<void> _createChannelInCategory(ChannelType type) async {
    final serverId = selectedServerId;
    if (serverId == kBuiltInServerId) return;
    final name = await _promptChannelName(
      title: type == ChannelType.voice
          ? 'Criar canal de voz'
          : 'Criar canal de texto',
      hint: type == ChannelType.voice
          ? 'Ex: Sala de Jogos'
          : 'Ex: bate-papo-geral',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ServerService.createChannel(
        serverId: serverId,
        name: name,
        isVoice: type == ChannelType.voice,
      );
      await _loadChannels();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao criar canal: $e')));
      }
    }
  }

  Future<void> _renameChannel(ChannelDef channel) async {
    if (channel.id == null) return;
    final newName = await _promptChannelName(
      title: 'Renomear canal',
      hint: channel.label,
      initialText: channel.name,
    );
    if (newName == null || newName.trim().isEmpty) return;
    try {
      await ServerService.renameChannel(
        channelId: channel.id!,
        newName: newName,
      );
      await _loadChannels();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao renomear canal: $e')));
      }
    }
  }

  Future<void> _deleteChannel(ChannelDef channel) async {
    if (channel.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _C.darker,
        title: const Text('Excluir canal',
            style: TextStyle(color: _C.textHeader)),
        content: Text(
          'Excluir "${channel.label}"? As mensagens dele ficam no histórico, mas o canal some para todo mundo.',
          style: const TextStyle(color: _C.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir',
                style: TextStyle(color: _C.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ServerService.deleteChannel(channel.id!);
      await _loadChannels();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir canal: $e')));
      }
    }
  }

  /// Diálogo com campo de texto para pedir o nome do canal. Retorna null
  /// se o usuário cancelar.
  Future<String?> _promptChannelName({
    required String title,
    String? hint,
    String? initialText,
  }) {
    final controller = TextEditingController(text: initialText);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _C.darker,
        title: Text(title, style: const TextStyle(color: _C.textHeader)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: const TextStyle(color: _C.textNormal),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _C.textMuted),
            filled: true,
            fillColor: _C.inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (value) =>
              Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Salvar', style: TextStyle(color: _C.blurple)),
          ),
        ],
      ),
    );
  }

  /// Abre a conversa com um amigo (busca ou cria) e já muda o foco para
  /// a área de Amigos, exibindo o chat dessa conversa como conteúdo
  /// principal — igual ao Discord quando você clica no ícone de
  /// mensagem ao lado de um amigo.
  Future<void> _openConversationWith(Profile friend) async {
    try {
      final conversationId = await DmService.getOrCreateConversation(friend.id);
      if (!mounted) return;
      setState(() {
        navArea = _NavArea.friends;
        activeDmConversation = DmConversation(
          id: conversationId,
          otherUser: friend,
          createdAt: DateTime.now(),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao abrir conversa: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < _mobileBreakpoint;
        final page = isMobile
            ? _buildMobileLayout(context)
            : _buildDesktopLayout(context, constraints.maxWidth);
        final call = _activeCall;
        if (call == null) return page;
        // A call vive num Stack POR CIMA da página (não numa rota). Cheia
        // = cobre tudo; minimizada = só o mini-player no canto, e todo o
        // resto do app por baixo continua 100% clicável.
        return Stack(
          children: [
            Positioned.fill(child: page),
            Positioned.fill(child: call),
          ],
        );
      },
    );
  }

  // -----------------------------------------------------------------
  // DESKTOP: navbar superior + 2 colunas [drawer de canais/DMs] [chat]
  // -----------------------------------------------------------------
  Widget _buildDesktopLayout(BuildContext context, double availableWidth) {
    // Largura da 2ª coluna se adapta em vez de ser fixa em todos os
    // tamanhos: em janelas/tablets mais estreitos (ex: split-screen,
    // laptop pequeno) ela encolhe um pouco para sobrar mais espaço pro
    // conteúdo principal, evitando que o chat fique espremido demais.
    final double sidebarWidth = availableWidth < 900 ? 220 : 280;
    final String currentServerName = selectedServerId == kBuiltInServerId
        ? 'Cord'
        : myServers.firstWhere((s) => s.id == selectedServerId).name;

    Widget mainContent;
    if (navArea == _NavArea.server) {
      mainContent = loadingChannels
          ? const Center(
              child: CircularProgressIndicator(color: _C.blurple))
          : _ChatArea(
              channelName: selectedChannel,
              displayName: _selectedChannelLabel,
              controller: _messageController,
              scrollController: _scrollController,
              onSend: () => _sendMessage(selectedChannel),
              onSendMedia: (file) => _sendChannelMedia(
                channelName: selectedChannel,
                serverId: selectedServerId,
                file: file,
              ),
              onToggleMembers: () => setState(
                  () => showMembersPanel = !showMembersPanel),
              membersPanelOpen: showMembersPanel,
              myUserId: widget.userId,
              serverId: selectedServerId,
            );
    } else if (activeDmConversation != null) {
      mainContent = _DmChatArea(
        conversation: activeDmConversation!,
        controller: _dmMessageController,
        scrollController: _dmScrollController,
        onSend: _sendDmMessage,
        onSendMedia: _sendDmMedia,
        myUserId: widget.userId,
        onPublicServerJoined: _refreshMyServersAfterVoiceInvite,
      );
    } else {
      mainContent = _FriendsMainPanel(
        myUserId: widget.userId,
        onOpenConversation: _openConversationWith,
      );
    }

    return Scaffold(
      backgroundColor: _C.darkest,
      body: Column(
        children: [
          // ---------------- NAVBAR SUPERIOR (glass) ----------------
          // Substitui o rail vertical de servidores: logo, tabs principais
          // (Início / Mensagens / servidores) e resumo do perfil à direita.
          _TopNavBar(
            currentServerName: currentServerName,
            navArea: navArea,
            userId: widget.userId,
            onHomeTap: () => setState(() {
              navArea = _NavArea.friends;
              activeDmConversation = null;
            }),
            onMessagesTap: () => setState(() => navArea = _NavArea.friends),
            onServerTap: (id) {
              setState(() => navArea = _NavArea.server);
              _selectServer(id);
            },
            servers: myServers,
            selectedServerId: selectedServerId,
          ),
          // ---------------- 2 COLUNAS ----------------
          Expanded(
            child: Row(
              children: [
                // Drawer esquerdo: canais (modo servidor) ou amigos/DMs
                // (modo social). Colapsável pelo botão na navbar.
                if (navArea == _NavArea.server)
                  _ChannelSidebar(
                    serverName: currentServerName,
                    serverIsPublic: _activeServer?.isPublic,
                    canManageServer: _activeServer?.ownerId == widget.userId,
                    onCreateInvite: _activeServer == null
                        ? null
                        : _createServerInvite,
                    onToggleVisibility:
                        _activeServer?.ownerId == widget.userId
                            ? _toggleServerVisibility
                            : null,
                    categories: currentCategories,
                    selectedChannel: selectedChannel,
                    onChannelTap: _selectChannel,
                    userId: widget.userId,
                    width: sidebarWidth,
                    showHeader: true,
                    onCreateChannel: _canManageChannels
                        ? _createChannelInCategory
                        : null,
                    onEditChannel:
                        _canManageChannels ? _renameChannel : null,
                    onDeleteChannel:
                        _canManageChannels ? _deleteChannel : null,
                  )
                else
                  _FriendsSidebar(
                    myUserId: widget.userId,
                    activeConversationId: activeDmConversation?.id,
                    onFriendsTap: () =>
                        setState(() => activeDmConversation = null),
                    onOpenConversation: (conv) =>
                        setState(() => activeDmConversation = conv),
                    width: sidebarWidth,
                  ),
                Expanded(child: mainContent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // MOBILE: lista de canais em tela cheia; toque em canal de texto abre
  // o chat em uma nova rota, com seta de voltar automática. "Amigos"
  // vira uma tela cheia separada, acessível pelo topo da gaveta.
  // -----------------------------------------------------------------
  Widget _buildMobileLayout(BuildContext context) {
    final String currentServerName = selectedServerId == kBuiltInServerId
        ? 'Cord'
        : myServers.firstWhere((s) => s.id == selectedServerId).name;

    return Scaffold(
      backgroundColor: _C.darker,
      drawer: Drawer(
        width: 72,
        backgroundColor: _C.darkest,
        child: SafeArea(
          child: _ServerRail(
            navArea: _NavArea
                .server, // a gaveta sempre mostra o servidor como "ativo"
            servers: myServers,
            selectedServerId: selectedServerId,
            onHomeTap: () {
              Navigator.of(context).pop(); // fecha a gaveta
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _MobileFriendsScreen(
                    myUserId: widget.userId,
                    onPublicServerJoined: _refreshMyServersAfterVoiceInvite,
                  ),
                ),
              );
            },
            onSelectServer: (id) {
              _selectServer(id);
              Navigator.of(context).pop();
            },
            onAddServer: () async {
              Navigator.of(context).pop();
              await _openServerActions(context);
            },
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: _C.darker,
        elevation: 0,
        title: Text(currentServerName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: _C.textHeader, fontWeight: FontWeight.bold)),
        actions: [
          if (_activeServer != null)
            _ServerActionsMenu(
              isPublic: _activeServer!.isPublic,
              canManageServer: _activeServer!.ownerId == widget.userId,
              onCreateInvite: _createServerInvite,
              onToggleVisibility: _toggleServerVisibility,
            ),
        ],
      ),
      body: loadingChannels
          ? const Center(child: CircularProgressIndicator(color: _C.blurple))
          : _ChannelSidebar(
              serverName: currentServerName,
              serverIsPublic: _activeServer?.isPublic,
              canManageServer: _activeServer?.ownerId == widget.userId,
              onCreateInvite:
                  _activeServer == null ? null : _createServerInvite,
              onToggleVisibility: _activeServer?.ownerId == widget.userId
                  ? _toggleServerVisibility
                  : null,
              categories: currentCategories,
              selectedChannel: selectedChannel,
              userId: widget.userId,
              width: double.infinity,
              showHeader: false,
              onCreateChannel: _canManageChannels ? _createChannelInCategory : null,
              onEditChannel: _canManageChannels ? _renameChannel : null,
              onDeleteChannel: _canManageChannels ? _deleteChannel : null,
              onChannelTap: (channel) {
                if (channel.type == ChannelType.voice) {
                  _selectChannel(channel);
                  return;
                }
                setState(() => selectedChannel = channel.name);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _MobileChatScreen(
                      channelName: channel.name,
                      displayName: channel.label,
                      controller: _messageController,
                      scrollController: _scrollController,
                      onSend: () => _sendMessage(channel.name),
                      onSendMedia: (file) => _sendChannelMedia(
                        channelName: channel.name,
                        serverId: selectedServerId,
                        file: file,
                      ),
                      myUserId: widget.userId,
                      serverId: selectedServerId,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// =========================================================================
// NAVBAR SUPERIOR — logo + tabs + perfil (glassmorphism)
// =========================================================================
// Substitui o rail vertical do layout antigo do Discord: navegação no
// topo, em linha, com fundo translúcido desfocado e sombra difusa.
class _TopNavBar extends StatelessWidget {
  final String currentServerName;
  final _NavArea navArea;
  final String userId;
  final VoidCallback onHomeTap;
  final VoidCallback onMessagesTap;
  final ValueChanged<String> onServerTap;
  final List<ServerModel> servers;
  final String selectedServerId;

  const _TopNavBar({
    required this.currentServerName,
    required this.navArea,
    required this.userId,
    required this.onHomeTap,
    required this.onMessagesTap,
    required this.onServerTap,
    required this.servers,
    required this.selectedServerId,
  });

  @override
  Widget build(BuildContext context) {
    final isFriendsActive = navArea == _NavArea.friends;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        // Glassmorphism: branco translúcido + blur + borda de luz fina.
        color: Colors.white.withOpacity(0.72),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.6))),
        boxShadow: _C.softShadow,
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // LOGO
                GestureDetector(
                  onTap: onHomeTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _C.softShadow,
                    ),
                    child: const Text('Cord',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            letterSpacing: -0.3)),
                  ),
                ),
                const SizedBox(width: 20),
                // TABS PRINCIPAIS
                _NavTab(
                  icon: Icons.home_rounded,
                  label: 'Início',
                  isActive: isFriendsActive &&
                      selectedServerId == kBuiltInServerId,
                  onTap: onHomeTap,
                ),
                const SizedBox(width: 6),
                _NavTab(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Mensagens',
                  isActive: isFriendsActive,
                  onTap: onMessagesTap,
                ),
                const SizedBox(width: 6),
                // Aba Configurações: abre a tela dedicada.
                _NavTab(
                  icon: Icons.settings_rounded,
                  label: 'Configurações',
                  isActive: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SettingsScreen(userId: userId),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Servidores como "tabs" com dropdown.
                PopupMenuButton<String>(
                  tooltip: 'Servidores',
                  onSelected: onServerTap,
                  color: _C.inputBg,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: kBuiltInServerId,
                        child: const Text('Cord (global)')),
                    for (final s in servers)
                      PopupMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: !isFriendsActive
                          ? _C.activeChannel
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.dns_rounded,
                            size: 18,
                            color: !isFriendsActive
                                ? _C.blurple
                                : _C.textMuted),
                        const SizedBox(width: 6),
                        Text(currentServerName,
                            style: TextStyle(
                                color: !isFriendsActive
                                    ? _C.textHeader
                                    : _C.textNormal,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more_rounded,
                            size: 18, color: _C.textMuted),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // RESUMO DO PERFIL (abre o próprio perfil ao clicar).
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                          userId: userId, isOwnProfile: true),
                    ),
                  ),
                  child: _UserFooter(userId: userId),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _NavTab({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? _C.activeChannel : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 19,
                color: isActive ? _C.blurple : _C.textMuted),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: isActive ? _C.textHeader : _C.textNormal,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// COLUNA DE NAVEGAÇÃO PRINCIPAL: Home (Amigos) + divisor + servidores
// =========================================================================
class _ServerRail extends StatelessWidget {
  final _NavArea navArea;
  final List<ServerModel> servers;
  final String selectedServerId;
  final VoidCallback onHomeTap;
  final ValueChanged<String> onSelectServer;
  final VoidCallback onAddServer;

  const _ServerRail({
    required this.navArea,
    required this.servers,
    required this.selectedServerId,
    required this.onHomeTap,
    required this.onSelectServer,
    required this.onAddServer,
  });

  @override
  Widget build(BuildContext context) {
    final bool isFriendsActive = navArea == _NavArea.friends;

    return Container(
      width: 72,
      color: _C.darkest,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // "Home" — abre a área de Amigos/DMs, separada dos servidores.
          _RailIcon(
            tooltip: 'Amigos',
            isActive: isFriendsActive,
            icon: Icons.people_alt_rounded,
            onTap: onHomeTap,
          ),
          const SizedBox(height: 8),
          Container(height: 2, width: 32, color: _C.divider),
          const SizedBox(height: 8),
          // Lista de servidores: o "Cord" fixo primeiro, depois os
          // servidores reais que o usuário criou/participa.
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _RailIcon(
                  tooltip: 'Cord',
                  isActive:
                      !isFriendsActive && selectedServerId == kBuiltInServerId,
                  icon: Icons.forum_rounded,
                  onTap: () => onSelectServer(kBuiltInServerId),
                ),
                for (final server in servers) ...[
                  const SizedBox(height: 8),
                  _RailIcon(
                    tooltip: server.name,
                    isActive: !isFriendsActive && selectedServerId == server.id,
                    label: server.iconText,
                    onTap: () => onSelectServer(server.id),
                  ),
                ],
              ],
            ),
          ),
          // Botão de adicionar servidor — mesmo estilo do "+" verde do
          // Discord de verdade.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Tooltip(
              message: 'Servidores',
              child: GestureDetector(
                onTap: onAddServer,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _C.darker,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child:
                      const Icon(Icons.add_rounded, color: _C.green, size: 26),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sair da conta',
            icon: const Icon(Icons.logout_rounded, color: _C.textMuted),
            onPressed: () => AuthService.signOut(),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  final String tooltip;
  final bool isActive;
  final IconData? icon;
  final String? label;
  final VoidCallback onTap;

  const _RailIcon({
    required this.tooltip,
    required this.isActive,
    required this.onTap,
    this.icon,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive ? _C.blurple : _C.darker,
              borderRadius: BorderRadius.circular(isActive ? 16 : 24),
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 24)
                : Text(
                    label ?? '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Recebe o nome e a visibilidade inicial do servidor.
class _CreateServerDialog extends StatefulWidget {
  const _CreateServerDialog();

  @override
  State<_CreateServerDialog> createState() => _CreateServerDialogState();
}

class _CreateServerDialogState extends State<_CreateServerDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isPublic = false;

  _CreateServerData get _serverData => _CreateServerData(
        name: _nameController.text,
        isPublic: _isPublic,
      );

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _C.darker,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Criar servidor',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Seu novo servidor já nasce com um canal de texto ("geral") e um de voz.',
              style: TextStyle(color: _C.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (value) => Navigator.of(context).pop(_serverData),
              decoration: InputDecoration(
                hintText: 'Nome do servidor',
                hintStyle: const TextStyle(color: _C.textMuted),
                filled: true,
                fillColor: _C.chatBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Servidor público'),
              subtitle: Text(
                _isPublic
                    ? 'Aparece na descoberta e qualquer pessoa pode entrar.'
                    : 'Só entra quem receber um convite.',
                style: const TextStyle(color: _C.textMuted, fontSize: 12),
              ),
              value: _isPublic,
              activeThumbColor: _C.blurple,
              onChanged: (value) => setState(() => _isPublic = value),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _C.textMuted),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: const Text('Cancelar',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_serverData),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: _C.blurple),
                    child: const Text('Criar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicServersDialog extends StatefulWidget {
  const _PublicServersDialog();

  @override
  State<_PublicServersDialog> createState() => _PublicServersDialogState();
}

class _PublicServersDialogState extends State<_PublicServersDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<ServerModel> _servers = [];
  bool _loading = true;
  String? _error;
  String? _joiningServerId;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadServers() async {
    try {
      final servers = await ServerService.fetchPublicServers();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar servidores: $e';
      });
    }
  }

  Future<void> _join(ServerModel server) async {
    setState(() {
      _joiningServerId = server.id;
      _error = null;
    });
    try {
      final serverId = await ServerService.joinPublicServer(server.id);
      if (mounted) Navigator.of(context).pop(serverId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joiningServerId = null;
        _error = 'Não foi possível entrar no servidor: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredServers = _servers
        .where((server) => server.name.toLowerCase().contains(query))
        .toList();

    return AlertDialog(
      backgroundColor: _C.darker,
      title: const Text('Servidores públicos'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar por nome',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredServers.isEmpty
                      ? const Center(
                          child: Text('Nenhum servidor público encontrado.'))
                      : ListView.builder(
                          itemCount: filteredServers.length,
                          itemBuilder: (context, index) {
                            final server = filteredServers[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _C.blurple,
                                child: Text(server.iconText),
                              ),
                              title: Text(server.name),
                              subtitle: const Text('Público'),
                              trailing: TextButton(
                                onPressed: _joiningServerId == null
                                    ? () => _join(server)
                                    : null,
                                child: _joiningServerId == server.id
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('Entrar'),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _JoinServerDialog extends StatefulWidget {
  const _JoinServerDialog();

  @override
  State<_JoinServerDialog> createState() => _JoinServerDialogState();
}

class _JoinServerDialogState extends State<_JoinServerDialog> {
  final TextEditingController _inviteController = TextEditingController();

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _C.darker,
      title: const Text('Entrar com convite'),
      content: TextField(
        controller: _inviteController,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(hintText: 'Cole o código do convite'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _inviteController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_inviteController.text.trim()),
          child: const Text('Entrar'),
        ),
      ],
    );
  }
}

// =========================================================================
// BARRA DE CANAIS
// =========================================================================
class _ChannelSidebar extends StatelessWidget {
  final String serverName;
  final bool? serverIsPublic;
  final bool canManageServer;
  final VoidCallback? onCreateInvite;
  final VoidCallback? onToggleVisibility;
  final List<CategoryDef> categories;
  final String selectedChannel;
  final ValueChanged<ChannelDef> onChannelTap;
  final String userId;
  final double width;
  final bool showHeader;

  /// Gestão de canais (só para o dono do servidor):
  final void Function(ChannelType type)? onCreateChannel;
  final void Function(ChannelDef channel)? onEditChannel;
  final void Function(ChannelDef channel)? onDeleteChannel;

  const _ChannelSidebar({
    required this.serverName,
    required this.serverIsPublic,
    required this.canManageServer,
    required this.onCreateInvite,
    required this.onToggleVisibility,
    required this.categories,
    required this.selectedChannel,
    required this.onChannelTap,
    required this.userId,
    required this.width,
    required this.showHeader,
    this.onCreateChannel,
    this.onEditChannel,
    this.onDeleteChannel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: _C.darker,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _C.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      serverName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _C.textHeader,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (serverIsPublic != null && onCreateInvite != null)
                    _ServerActionsMenu(
                      isPublic: serverIsPublic!,
                      canManageServer: canManageServer,
                      onCreateInvite: onCreateInvite!,
                      onToggleVisibility: onToggleVisibility,
                    ),
                ],
              ),
            ),
          ],
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final category in categories)
                  _CategorySection(
                    category: category,
                    selectedChannel: selectedChannel,
                    onChannelTap: onChannelTap,
                    onCreateChannel: onCreateChannel,
                    onEditChannel: onEditChannel,
                    onDeleteChannel: onDeleteChannel,
                  ),
              ],
            ),
          ),
          _UserFooter(userId: userId),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final CategoryDef category;
  final String selectedChannel;
  final ValueChanged<ChannelDef> onChannelTap;
  final void Function(ChannelType type)? onCreateChannel;
  final void Function(ChannelDef channel)? onEditChannel;
  final void Function(ChannelDef channel)? onDeleteChannel;

  const _CategorySection({
    required this.category,
    required this.selectedChannel,
    required this.onChannelTap,
    this.onCreateChannel,
    this.onEditChannel,
    this.onDeleteChannel,
  });

  @override
  Widget build(BuildContext context) {
    final isVoiceCategory = category.channels.isNotEmpty
        ? category.channels.first.type == ChannelType.voice
        : category.title.toUpperCase().contains('VOZ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  category.title,
                  style: const TextStyle(
                      color: _C.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
              if (onCreateChannel != null)
                GestureDetector(
                  onTap: () =>
                      onCreateChannel!(isVoiceCategory ? ChannelType.voice : ChannelType.text),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.add_rounded,
                        color: _C.textMuted, size: 18),
                  ),
                ),
            ],
          ),
        ),
        for (final channel in category.channels)
          _ChannelTile(
            channel: channel,
            isSelected: channel.name == selectedChannel,
            onTap: () => onChannelTap(channel),
            onEdit: onEditChannel,
            onDelete: onDeleteChannel,
          ),
      ],
    );
  }
}

class _ChannelTile extends StatefulWidget {
  final ChannelDef channel;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(ChannelDef channel)? onEdit;
  final void Function(ChannelDef channel)? onDelete;

  const _ChannelTile({
    required this.channel,
    required this.isSelected,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final Color bg = widget.isSelected
        ? _C.activeChannel
        : (_hovering ? _C.hoverChannel : Colors.transparent);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(4)),
            child: Row(
              children: [
                Icon(
                  widget.channel.type == ChannelType.text
                      ? Icons.tag_rounded
                      : Icons.volume_up_rounded,
                  size: 20,
                  color: widget.isSelected ? _C.textNormal : _C.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.channel.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isSelected ? Colors.white : _C.textMuted,
                      fontSize: 15,
                      fontWeight:
                          widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                // Menu de editar/excluir — só para canais que vivem no banco
                // (o "Cord" fixo não tem id) e quando há alguém autorizado a
                // gerenciar (callbacks informados).
                if (widget.channel.id != null &&
                    (widget.onEdit != null || widget.onDelete != null) &&
                    (_hovering || widget.isSelected))
                  SizedBox(
                    width: 24,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz_rounded,
                          size: 18, color: _C.textMuted),
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'edit' && widget.onEdit != null) {
                          widget.onEdit!(widget.channel);
                        } else if (value == 'delete' &&
                            widget.onDelete != null) {
                          widget.onDelete!(widget.channel);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          height: 36,
                          child: Row(children: [
                            Icon(Icons.edit_rounded,
                                size: 16, color: _C.textMuted),
                            SizedBox(width: 8),
                            Text('Renomear',
                                style: TextStyle(fontSize: 14)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          height: 36,
                          child: Row(children: [
                            Icon(Icons.delete_rounded,
                                size: 16, color: _C.red),
                            SizedBox(width: 8),
                            Text('Excluir',
                                style: TextStyle(
                                    fontSize: 14, color: _C.red)),
                          ]),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerActionsMenu extends StatelessWidget {
  final bool isPublic;
  final bool canManageServer;
  final VoidCallback onCreateInvite;
  final VoidCallback? onToggleVisibility;

  const _ServerActionsMenu({
    required this.isPublic,
    required this.canManageServer,
    required this.onCreateInvite,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Opções do servidor',
      onSelected: (action) {
        if (action == 'invite') {
          onCreateInvite();
        } else if (action == 'visibility') {
          onToggleVisibility?.call();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'invite',
          child: Text('Criar convite'),
        ),
        if (canManageServer)
          PopupMenuItem(
            value: 'visibility',
            child: Text(isPublic ? 'Tornar privado' : 'Tornar público'),
          ),
      ],
      icon: const Icon(Icons.more_vert, color: _C.textMuted),
    );
  }
}

/// Rodapé com o perfil do usuário logado — busca o Profile real
/// (username/display_name) no Supabase em vez de mostrar o UUID cru.
class _UserFooter extends StatelessWidget {
  final String userId;
  const _UserFooter({required this.userId});

  @override
  Widget build(BuildContext context) {
    // Card de usuário claro e sem "quadro escuro" legado: superfície
    // translúcida, cantos arredondados, alinhado com a navbar superior.
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
        boxShadow: _C.softShadow,
      ),
      child: StreamBuilder<Profile>(
        stream: ProfileService.watchMyProfile(userId),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final displayName = profile?.displayName ?? '...';
          final initial =
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            // Clicar abre o SEU PRÓPRIO perfil.
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ProfileScreen(userId: userId, isOwnProfile: true),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _C.blurple, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: _C.blurple,
                      backgroundImage: profile?.avatarUrl != null
                          ? NetworkImage(profile!.avatarUrl!)
                          : null,
                      child: profile?.avatarUrl == null
                          ? Text(initial,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700))
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _C.textHeader,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =========================================================================
// SEGUNDA COLUNA NO MODO "AMIGOS": item fixo "Amigos" + lista de DMs
// =========================================================================
// Espelha o comportamento real do Discord: "Amigos" fica fixo no topo
// (sempre visível, nunca misturado com canais de servidor), e embaixo
// fica a lista de conversas privadas abertas, mais recentes primeiro.
class _FriendsSidebar extends StatefulWidget {
  final String myUserId;
  final String? activeConversationId;
  final VoidCallback onFriendsTap;
  final ValueChanged<DmConversation> onOpenConversation;
  final double width;

  const _FriendsSidebar({
    required this.myUserId,
    required this.activeConversationId,
    required this.onFriendsTap,
    required this.onOpenConversation,
    this.width = 240,
  });

  @override
  State<_FriendsSidebar> createState() => _FriendsSidebarState();
}

class _FriendsSidebarState extends State<_FriendsSidebar> {
  late Future<List<DmConversation>> _conversationsFuture;
  late Future<List<FriendRequestModel>> _pendingRequestsFuture;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = DmService.fetchMyConversations(widget.myUserId);
    _pendingRequestsFuture =
        FriendService.fetchPendingReceived(widget.myUserId);
  }

  /// Chame depois de abrir uma conversa nova (que ainda não estava na
  /// lista) para ela aparecer aqui sem precisar reabrir a tela inteira.
  void _refresh() {
    setState(() {
      _conversationsFuture = DmService.fetchMyConversations(widget.myUserId);
      _pendingRequestsFuture =
          FriendService.fetchPendingReceived(widget.myUserId);
    });
  }

  Future<void> _respond(FriendRequestModel request, bool accept) async {
    await FriendService.respondToRequest(requestId: request.id, accept: accept);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bool isFriendsSelected = widget.activeConversationId == null;

    return Container(
      width: widget.width,
      color: _C.darker,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _C.divider)),
            ),
            child: const Text('Amigos',
                style: TextStyle(
                    color: _C.textHeader,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: _NavRow(
                    icon: Icons.people_alt_rounded,
                    label: 'Amigos',
                    isActive: isFriendsSelected,
                    onTap: widget.onFriendsTap,
                  ),
                ),

                // ---------------------------------------------------
                // PEDIDOS DE AMIZADE — logo abaixo de "Amigos", como
                // pedido. Só aparece quando existe pelo menos um pedido
                // pendente, pra não ocupar espaço à toa.
                // ---------------------------------------------------
                FutureBuilder<List<FriendRequestModel>>(
                  future: _pendingRequestsFuture,
                  builder: (context, snapshot) {
                    final requests = snapshot.data ?? const [];
                    if (requests.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                          child: Text(
                            'PEDIDOS DE AMIZADE (${requests.length})',
                            style: const TextStyle(
                                color: _C.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (final request in requests)
                          _PendingRequestRow(
                            request: request,
                            onAccept: () => _respond(request, true),
                            onReject: () => _respond(request, false),
                          ),
                      ],
                    );
                  },
                ),

                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Text('CONVERSAS PRIVADAS',
                      style: TextStyle(
                          color: _C.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                FutureBuilder<List<DmConversation>>(
                  future: _conversationsFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: _C.blurple, strokeWidth: 2)),
                      );
                    }
                    final conversations = snapshot.data!;
                    if (conversations.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Nenhuma conversa ainda.',
                            style:
                                TextStyle(color: _C.textMuted, fontSize: 13)),
                      );
                    }
                    return Column(
                      children: [
                        for (final conv in conversations)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _NavRow(
                              avatarLetter: conv
                                      .otherUser.displayName.isNotEmpty
                                  ? conv.otherUser.displayName[0].toUpperCase()
                                  : '?',
                              avatarUrl: conv.otherUser.avatarUrl,
                              label: conv.otherUser.displayName,
                              isActive: widget.activeConversationId == conv.id,
                              onTap: () => widget.onOpenConversation(conv),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          _UserFooter(userId: widget.myUserId),
        ],
      ),
    );
  }
}

/// Linha de um pedido de amizade pendente, com avatar + nome + dois
/// botões pequenos (aceitar/recusar) lado a lado — pensada para caber
/// numa coluna estreita (200–240px).
class _PendingRequestRow extends StatelessWidget {
  final FriendRequestModel request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _PendingRequestRow({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: _C.blurple,
            backgroundImage: request.otherUser.avatarUrl != null
                ? NetworkImage(request.otherUser.avatarUrl!)
                : null,
            child: request.otherUser.avatarUrl == null
                ? Text(request.otherUser.displayName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 11))
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              request.otherUser.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            tooltip: 'Aceitar',
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.check_circle_rounded, color: _C.green),
            onPressed: onAccept,
          ),
          IconButton(
            tooltip: 'Recusar',
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.cancel_rounded, color: Color(0xFFDA373C)),
            onPressed: onReject,
          ),
        ],
      ),
    );
  }
}

/// Linha de navegação reutilizada tanto para "Amigos" (com ícone) quanto
/// para cada conversa privada na lista (com avatar).
class _NavRow extends StatefulWidget {
  final IconData? icon;
  final String? avatarLetter;
  final String? avatarUrl;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavRow({
    this.icon,
    this.avatarLetter,
    this.avatarUrl,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final Color bg = widget.isActive
        ? _C.activeChannel
        : (_hovering ? _C.hoverChannel : Colors.transparent);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(4)),
            child: Row(
              children: [
                if (widget.icon != null)
                  Icon(widget.icon,
                      size: 20,
                      color: widget.isActive ? Colors.white : _C.textMuted)
                else
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: _C.blurple,
                    backgroundImage: widget.avatarUrl != null
                        ? NetworkImage(widget.avatarUrl!)
                        : null,
                    child: widget.avatarUrl == null
                        ? Text(widget.avatarLetter ?? '?',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11))
                        : null,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isActive ? Colors.white : _C.textMuted,
                      fontSize: 15,
                      fontWeight:
                          widget.isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// CONTEÚDO PRINCIPAL NO MODO "AMIGOS" (sem conversa aberta): gerencia a
// lista de amigos e permite abrir uma DM ou adicionar alguém novo.
// =========================================================================
class _FriendsMainPanel extends StatefulWidget {
  final String myUserId;
  final ValueChanged<Profile> onOpenConversation;

  const _FriendsMainPanel(
      {required this.myUserId, required this.onOpenConversation});

  @override
  State<_FriendsMainPanel> createState() => _FriendsMainPanelState();
}

class _FriendsMainPanelState extends State<_FriendsMainPanel> {
  late Future<List<Profile>> _friendsFuture;

  @override
  void initState() {
    super.initState();
    _friendsFuture = FriendService.fetchAcceptedFriends(widget.myUserId);
  }

  void _refresh() {
    setState(() =>
        _friendsFuture = FriendService.fetchAcceptedFriends(widget.myUserId));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.chatBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _C.divider))),
            child: Row(
              children: [
                const Icon(Icons.people_alt_rounded,
                    color: _C.textMuted, size: 20),
                const SizedBox(width: 8),
                const Text('Amigos',
                    style: TextStyle(
                        color: _C.textHeader,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) =>
                          _AddFriendDialog(myUserId: widget.myUserId),
                    );
                    _refresh();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: _C.blurple),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: const Text('Adicionar amigo'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Profile>>(
              future: _friendsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: _C.blurple));
                }
                final friends = snapshot.data!;
                if (friends.isEmpty) {
                  return const Center(
                    child: Text('Você ainda não tem amigos adicionados.',
                        style: TextStyle(color: _C.textMuted)),
                  );
                }
                return ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: friends.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: _C.divider, height: 1),
                  itemBuilder: (context, index) {
                    final friend = friends[index];
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
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text('@${friend.username}',
                          style: const TextStyle(
                              color: _C.textMuted, fontSize: 12)),
                      trailing: IconButton(
                        tooltip: 'Enviar mensagem',
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            color: _C.textMuted),
                        onPressed: () => widget.onOpenConversation(friend),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// ÁREA DE CHAT DE UMA CONVERSA PRIVADA (DM) — mesmo padrão do _ChatArea,
// só que ligado ao DmService em vez do ChatService.
// =========================================================================
class _DmChatArea extends StatelessWidget {
  final DmConversation conversation;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final Future<void> Function(XFile) onSendMedia;
  final String myUserId;
  final Future<void> Function() onPublicServerJoined;

  const _DmChatArea({
    required this.conversation,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    required this.onSendMedia,
    required this.myUserId,
    required this.onPublicServerJoined,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.chatBg,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _C.divider))),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _C.blurple,
                  backgroundImage: conversation.otherUser.avatarUrl != null
                      ? NetworkImage(conversation.otherUser.avatarUrl!)
                      : null,
                  child: conversation.otherUser.avatarUrl == null
                      ? Text(
                          conversation.otherUser.displayName[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12))
                      : null,
                ),
                const SizedBox(width: 8),
                Text(conversation.otherUser.displayName,
                    style: const TextStyle(
                        color: _C.textHeader,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ],
            ),
          ),
          Expanded(
            child: _DmMessagesList(
              conversationId: conversation.id,
              scrollController: scrollController,
              myUserId: myUserId,
              onPublicServerJoined: onPublicServerJoined,
            ),
          ),
          _MessageInputBar(
            controller: controller,
            onSend: onSend,
            onSendMedia: onSendMedia,
            channelName: '@${conversation.otherUser.username}',
          ),
        ],
      ),
    );
  }
}

class _DmMessagesList extends StatefulWidget {
  final String conversationId;
  final ScrollController scrollController;
  final String myUserId;
  final Future<void> Function() onPublicServerJoined;

  const _DmMessagesList({
    required this.conversationId,
    required this.scrollController,
    required this.myUserId,
    required this.onPublicServerJoined,
  });

  @override
  State<_DmMessagesList> createState() => _DmMessagesListState();
}

class _DmMessagesListState extends State<_DmMessagesList> {
  late Stream<List<DirectMessageModel>> _stream;
  StreamSubscription<void>? _reconnectSub;

  @override
  void initState() {
    super.initState();
    _stream = _buildStream();
    // REGRA 3: ao reconectar (aba oculta/AFK), recria a stream — o refetch
    // completo traz as mensagens perdidas sem duplicar nada.
    _reconnectSub = RealtimeLifecycleService.instance.onReconnect.listen((_) {
      if (mounted) setState(() => _stream = _buildStream());
    });
  }

  Stream<List<DirectMessageModel>> _buildStream() =>
      DmService.watchConversation(widget.conversationId);

  @override
  void didUpdateWidget(covariant _DmMessagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _stream = _buildStream();
    }
  }

  @override
  void dispose() {
    // REGRA 4: cancela o listener de reconexão ao sair da conversa.
    _reconnectSub?.cancel();
    super.dispose();
  }

  /// Se a mensagem for um convite de chamada de voz (ver
  /// kVoiceInvitePrefix em voice_call_screen.dart), mostra um cartão
  /// clicável em vez do texto cru.
  Widget _buildMessageContent(
      BuildContext context, DirectMessageModel message) {
    final invite = parseVoiceInviteMessage(message.content);
    if (invite == null) {
      return Text(message.content,
          style: const TextStyle(
              color: _C.textNormal, fontSize: 15, height: 1.35));
    }

    return _VoiceInviteCard(
      roomId: invite.roomId,
      channelName: invite.channelName,
      expiresAt:
          message.expiresAt ?? message.createdAt.add(kVoiceInviteLifetime),
      myUserId: widget.myUserId,
      onPublicServerJoined: widget.onPublicServerJoined,
    );
  }

  Widget _buildMessageBody(BuildContext context, DirectMessageModel message) {
    final isMine = message.senderId == widget.myUserId;
    final hasMedia = message.mediaPath != null;
    final hasText = message.content.trim().isNotEmpty;

    // Mensagem só de mídia: sem bolha, card com aspect ratio original.
    if (hasMedia && !hasText) {
      return Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _ChatMediaPreview(
            mediaType: message.mediaType,
            mediaUrl: message.mediaUrl,
            fileName: message.mediaName,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (hasMedia)
          _ChatMediaPreview(
            mediaType: message.mediaType,
            mediaUrl: message.mediaUrl,
            fileName: message.mediaName,
          ),
        if (hasText)
          Padding(
            padding: EdgeInsets.only(top: hasMedia ? 2 : 0),
            child: isMine
                // Texto branco sobre o indigo da bolha enviada.
                ? Text(message.content,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, height: 1.35))
                : _buildMessageContent(context, message),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DirectMessageModel>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: _C.blurple));
        }
        final messages = snapshot.data!;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (widget.scrollController.hasClients) {
            widget.scrollController
                .jumpTo(widget.scrollController.position.maxScrollExtent);
          }
        });

        if (messages.isEmpty) {
          return const Center(
            child: Text('Nenhuma mensagem ainda. Diga oi! 👋',
                style: TextStyle(color: _C.textMuted)),
          );
        }

        // Mesma linguagem de bolhas do chat de servidor: enviada à direita
        // (menta), recebida à esquerda (branca).
        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isMine = message.senderId == widget.myUserId;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              child: Row(
                mainAxisAlignment:
                    isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMine)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 2),
                      child: _ChatAvatar(
                        displayName: message.senderDisplayName,
                        avatarUrl: message.senderAvatarUrl,
                      ),
                    ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (!isMine)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3, left: 4),
                            child: Row(
                              children: [
                                Text(message.senderDisplayName,
                                    style: const TextStyle(
                                        color: _C.blurple,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5)),
                                const SizedBox(width: 6),
                                Text(
                                    DateFormat('HH:mm')
                                        .format(message.createdAt),
                                    style: const TextStyle(
                                        color: _C.textMuted,
                                        fontSize: 10.5)),
                              ],
                            ),
                          ),
                        // SÓ MÍDIA: sem bolha — o card fala por si.
                        if (message.mediaPath != null &&
                            message.content.trim().isEmpty)
                          _buildMessageBody(context, message)
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width *
                                        0.7),
                            decoration: BoxDecoration(
                              gradient: isMine
                                  ? const LinearGradient(colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF8B5CF6)
                                    ])
                                  : null,
                              color: isMine ? null : _C.inputBg,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft:
                                    Radius.circular(isMine ? 18 : 4),
                                bottomRight:
                                    Radius.circular(isMine ? 4 : 18),
                              ),
                              border: isMine
                                  ? null
                                  : Border.all(color:
                                      Colors.white.withOpacity(0.6)),
                              boxShadow: _C.softShadow,
                            ),
                            child: _buildMessageBody(context, message),
                          ),
                        if (isMine)
                          Padding(
                            padding: const EdgeInsets.only(top: 3, right: 4),
                            child: Text(
                                DateFormat('HH:mm')
                                    .format(message.createdAt),
                                style: const TextStyle(
                                    color: _C.textMuted,
                                    fontSize: 10.5)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Cartão clicável mostrado no lugar de uma mensagem de texto normal
/// quando ela é um convite de chamada de voz. Tocar nele já entra
/// direto na chamada, sem precisar navegar até o servidor/canal.
class _VoiceInviteCard extends StatefulWidget {
  final String roomId;
  final String channelName;
  final DateTime expiresAt;
  final String myUserId;
  final Future<void> Function() onPublicServerJoined;

  const _VoiceInviteCard({
    required this.roomId,
    required this.channelName,
    required this.expiresAt,
    required this.myUserId,
    required this.onPublicServerJoined,
  });

  @override
  State<_VoiceInviteCard> createState() => _VoiceInviteCardState();
}

class _VoiceInviteCardState extends State<_VoiceInviteCard> {
  Timer? _expiryTimer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(covariant _VoiceInviteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expiresAt != oldWidget.expiresAt) _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _expired = true;
      return;
    }
    _expired = false;
    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(() => _expired = true);
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _join(BuildContext context) async {
    if (_expired) return;
    final serverId = serverIdFromVoiceRoomId(widget.roomId);
    var joinedServer = false;
    String? membershipNotice;
    if (serverId != null && serverId != kBuiltInServerId) {
      try {
        joinedServer = await ServerService.joinPublicServerFromVoiceInvite(
          serverId: serverId,
          userId: widget.myUserId,
        );
        if (!joinedServer) {
          membershipNotice =
              'Este servidor é privado. Peça um convite do servidor para ele aparecer na sua lista.';
        }
      } on PostgrestException catch (error) {
        membershipNotice =
            'Não foi possível adicionar você ao servidor: ${error.message}';
      }
    }

    Profile? profile;
    String? profileNotice;
    try {
      profile = await ProfileService.fetchProfile(widget.myUserId);
    } catch (error) {
      profileNotice = 'Não foi possível carregar seu perfil na chamada: $error';
    }
    if (!context.mounted) return;
    context.findAncestorStateOfType<_CordHomePageState>()?._openVoiceInvite(
      roomId: widget.roomId,
      channelName: widget.channelName,
      fallbackName: profile?.displayName,
      avatarUrl: profile?.avatarUrl,
    );
    if (joinedServer) {
      if (!context.mounted) return;
      await widget.onPublicServerJoined();
    }
    if (membershipNotice != null || profileNotice != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text([membershipNotice, profileNotice].whereType<String>().join('\n'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_expired) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _C.inputBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.timer_off_rounded, color: _C.textMuted),
            SizedBox(width: 10),
            Text(
              'Convite para chamada expirado',
              style: TextStyle(color: _C.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _join(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _C.blurple.withValues(alpha: 0.12),
          border: Border.all(color: _C.blurple),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.call_rounded, color: _C.blurple),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Convite para chamada de voz',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  Text(widget.channelName,
                      style:
                          const TextStyle(color: _C.textMuted, fontSize: 12)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => _join(context),
              style: ElevatedButton.styleFrom(backgroundColor: _C.blurple),
              child: const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// ÁREA DE CHAT — mensagens em tempo real via ChatService (Supabase Realtime)
// =========================================================================
class _ChatArea extends StatelessWidget {
  final String channelName;
  final String displayName;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final Future<void> Function(XFile) onSendMedia;
  final VoidCallback onToggleMembers;
  final bool membersPanelOpen;
  final String myUserId;
  final String serverId;

  const _ChatArea({
    required this.channelName,
    required this.displayName,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    required this.onSendMedia,
    required this.onToggleMembers,
    required this.membersPanelOpen,
    required this.myUserId,
    required this.serverId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.chatBg,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _C.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tag_rounded, color: _C.textMuted, size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _C.textHeader,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
                IconButton(
                  tooltip: 'Adicionar amigo',
                  icon: const Icon(Icons.person_add_alt_1_rounded,
                      color: _C.textMuted),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _AddFriendDialog(myUserId: myUserId),
                  ),
                ),
                IconButton(
                  tooltip:
                      membersPanelOpen ? 'Ocultar membros' : 'Mostrar membros',
                  icon: Icon(Icons.group_rounded,
                      color: membersPanelOpen ? Colors.white : _C.textMuted),
                  onPressed: onToggleMembers,
                ),
              ],
            ),
          ),
          Expanded(
            child: _MessagesList(
              channelName: channelName,
              scrollController: scrollController,
              myUserId: myUserId,
              serverId: serverId,
            ),
          ),
          _MessageInputBar(
            controller: controller,
            onSend: onSend,
            onSendMedia: onSendMedia,
            channelName: displayName,
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// DIÁLOGO "ADICIONAR AMIGO"
// =========================================================================
// Campo de nome de usuário + botão "Adicionar amigo" (busca e já envia o
// pedido em um único clique) + botão "Cancelar" (só fecha o diálogo).
class _AddFriendDialog extends StatefulWidget {
  final String myUserId;
  const _AddFriendDialog({required this.myUserId});

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final TextEditingController _usernameController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _handleAddFriend() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _errorMessage = 'Digite um nome de usuário.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final profile = await ProfileService.searchByUsername(username);

      if (profile == null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Usuário não encontrado.';
        });
        return;
      }

      if (profile.id == widget.myUserId) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Você não pode adicionar a si mesmo.';
        });
        return;
      }

      await FriendService.sendFriendRequest(
        senderId: widget.myUserId,
        receiverId: profile.id,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Pedido de amizade enviado para @${profile.username}!')),
      );
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        // A constraint UNIQUE(sender_id, receiver_id) do banco cai aqui
        // quando um pedido para esse usuário já existe.
        _errorMessage =
            'Não foi possível enviar o pedido (talvez já exista um pendente).';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _C.darker,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Adicionar amigo',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _handleAddFriend(),
              decoration: InputDecoration(
                hintText: 'Nome de usuário',
                hintStyle: const TextStyle(color: _C.textMuted),
                filled: true,
                fillColor: _C.chatBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!,
                  style:
                      const TextStyle(color: Color(0xFFFF8B8B), fontSize: 13)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _C.textMuted),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: const Text('Cancelar',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleAddFriend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.blurple,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Adicionar amigo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista de mensagens de um canal — em tempo real, direto do Supabase.
/// Reaproveitado tanto pelo layout desktop quanto pelo mobile.
class _MessagesList extends StatefulWidget {
  final String channelName;
  final ScrollController scrollController;
  final String myUserId;
  final String serverId;

  const _MessagesList({
    required this.channelName,
    required this.scrollController,
    required this.myUserId,
    required this.serverId,
  });

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> {
  late Stream<List<MessageModel>> _stream;
  StreamSubscription<void>? _reconnectSub;

  @override
  void initState() {
    super.initState();
    _stream = _buildStream();
    // REGRA 3 — SINCRONIZAÇÃO: quando o RealtimeLifecycleService reconecta
    // (volta de aba oculta ou de AFK), recriamos a stream. Ela refaz o
    // fetch COMPLETO do histórico — as mensagens enviadas enquanto o
    // usuário estava desconectado aparecem, e nada duplica (é a lista
    // inteira do banco, não um append).
    _reconnectSub = RealtimeLifecycleService.instance.onReconnect.listen((_) {
      if (mounted) setState(() => _stream = _buildStream());
    });
  }

  Stream<List<MessageModel>> _buildStream() =>
      ChatService.watchChannel(widget.channelName, serverId: widget.serverId);

  @override
  void didUpdateWidget(covariant _MessagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // REGRA 4 — LIMPEZA/recriação: se o canal mudou, nova stream.
    if (oldWidget.channelName != widget.channelName ||
        oldWidget.serverId != widget.serverId) {
      _stream = _buildStream();
    }
  }

  @override
  void dispose() {
    // REGRA 4 — todos os listeners deste widget são cancelados aqui.
    _reconnectSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MessageModel>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Erro ao carregar mensagens: ${snapshot.error}',
                style: const TextStyle(color: _C.textMuted)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: _C.blurple));
        }

        final messages = snapshot.data!;

        // Autoscroll para a mensagem mais recente sempre que a lista mudar.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (widget.scrollController.hasClients) {
            widget.scrollController
                .jumpTo(widget.scrollController.position.maxScrollExtent);
          }
        });

        if (messages.isEmpty) {
          return const Center(
            child: Text('Nenhuma mensagem ainda. Diga oi! 👋',
                style: TextStyle(color: _C.textMuted)),
          );
        }

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) => _MessageBubble(
              message: messages[index], myUserId: widget.myUserId),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final String myUserId;
  const _MessageBubble({required this.message, required this.myUserId});

  static String _formatTime(DateTime dt) => DateFormat('HH:mm').format(dt);

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: message.senderId,
          isOwnProfile: message.senderId == myUserId,
        ),
      ),
    );
  }

  Widget _buildMessageBody(bool isMine) {
    final hasMedia = message.mediaPath != null;
    final hasText = message.content.trim().isNotEmpty;

    // ---------------- MENSAGEM SÓ DE MÍDIA ----------------
    // Sem bolha: a mídia vive no próprio card (com aspect ratio real).
    if (hasMedia && !hasText) {
      return Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _ChatMediaPreview(
            mediaType: message.mediaType,
            mediaUrl: message.mediaUrl,
            fileName: message.mediaName,
          ),
        ],
      );
    }

    // ---------------- MÍDIA + TEXTO ou SÓ TEXTO ----------------
    // Quando há texto junto, o card de mídia entra dentro da bolha
    // (sem padding lateral extra para alinhar com o texto).
    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (hasMedia)
          _ChatMediaPreview(
            mediaType: message.mediaType,
            mediaUrl: message.mediaUrl,
            fileName: message.mediaName,
          ),
        if (hasText)
          Padding(
            padding: EdgeInsets.only(top: hasMedia ? 2 : 0),
            child: Text(
              message.content,
              style: TextStyle(
                  // Texto branco sobre o indigo das bolhas enviadas;
                  // charcoal sobre o branco das recebidas.
                  color: isMine ? Colors.white : _C.textNormal,
                  fontSize: 15,
                  height: 1.35),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.senderId == myUserId;

    final content = Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // Remetente + hora (só em mensagens recebidas, como no iMessage).
        if (!isMine)
          Padding(
            padding: const EdgeInsets.only(bottom: 3, left: 4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _openProfile(context),
                  child: Text(message.senderDisplayName,
                      style: const TextStyle(
                          color: _C.blurple,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5)),
                ),
                const SizedBox(width: 6),
                Text(_formatTime(message.createdAt),
                    style: const TextStyle(
                        color: _C.textMuted, fontSize: 10.5)),
              ],
            ),
          ),
        // BOLHA — cantos assimétricos (estilo mensageiro):
        // enviada = indigo sólido com texto branco, à direita;
        // recebida = branco limpo com texto escuro, à esquerda.
        // Quando é SÓ MÍDIA (sem texto), a bolha é omitida por completo:
        // o card de mídia (com aspect ratio original) fala por si.
        if (message.mediaPath != null &&
            message.content.trim().isEmpty)
          _buildMessageBody(isMine)
        else
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7),
            decoration: BoxDecoration(
              gradient: isMine
                  ? const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])
                  : null,
              color: isMine ? null : _C.inputBg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMine ? 18 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 18),
              ),
              border: isMine
                  ? null
                  : Border.all(color: Colors.white.withOpacity(0.6)),
              boxShadow: _C.softShadow,
            ),
            child: _buildMessageBody(isMine),
          ),
        if (isMine)
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 4),
            child: Text(_formatTime(message.createdAt),
                style: const TextStyle(
                    color: _C.textMuted, fontSize: 10.5)),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: GestureDetector(
                onTap: () => _openProfile(context),
                child: _ChatAvatar(
                  displayName: message.senderDisplayName,
                  avatarUrl: message.senderAvatarUrl,
                ),
              ),
            ),
          Flexible(child: content),
        ],
      ),
    );
  }
}

class _ChatMediaPreview extends StatelessWidget {
  final String? mediaType;
  final String? mediaUrl;
  final String? fileName;

  const _ChatMediaPreview({
    required this.mediaType,
    required this.mediaUrl,
    required this.fileName,
  });

  /// CARD DE MÍDIA INDEPENDENTE — fora da bolha de texto.
  /// Imagens/vídeos são renderizados com o aspect ratio ORIGINAL
  /// (nada de crop), num card arredondado com borda e sombra sutis.
  /// Toque numa imagem abre o lightbox em tela cheia.
  @override
  Widget build(BuildContext context) {
    if (mediaUrl == null || mediaUrl!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          'Mídia indisponível ou expirada${fileName == null ? '' : ': $fileName'}',
          style: const TextStyle(color: _C.textMuted, fontSize: 13),
        ),
      );
    }

    // Largura máxima do card: ~60% da tela (spec), com teto absoluto.
    final maxMediaWidth =
        (MediaQuery.of(context).size.width * 0.6).clamp(240.0, 420.0);

    if (mediaType == 'image') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: () => _openLightbox(context),
          child: Container(
            constraints: BoxConstraints(maxWidth: maxMediaWidth),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _C.divider),
              boxShadow: _C.softShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                mediaUrl!,
                // Aspect ratio ORIGINAL: largura limitada, altura livre,
                // BoxFit contendo a imagem inteira (sem crop).
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(
                        width: maxMediaWidth,
                        height: 180,
                        decoration: BoxDecoration(
                          color: _C.hoverChannel,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: _C.blurple),
                        ),
                      ),
                errorBuilder: (context, error, stackTrace) => const Text(
                  'Não foi possível carregar esta imagem.',
                  style: TextStyle(color: _C.textMuted),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (mediaType == 'video') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxMediaWidth),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.divider),
            boxShadow: _C.softShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _ChatVideoPlayer(url: mediaUrl!),
          ),
        ),
      );
    }

    return Text(
      fileName ?? 'Anexo',
      style: const TextStyle(color: _C.textMuted, fontSize: 13),
    );
  }

  /// LIGHTBOX — imagem em tela cheia sobre fundo escuro translúcido.
  /// Clique em qualquer lugar fecha.
  void _openLightbox(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withOpacity(0.92),
      pageBuilder: (_, __, ___) => _ImageLightbox(url: mediaUrl!),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: child,
      ),
    ));
  }
}

/// Visualizador em tela cheia: imagem centrada, BoxFit.contain (foto
/// inteira, qualidade máxima), fundo quase preto. Toque fecha.
class _ImageLightbox extends StatelessWidget {
  final String url;
  const _ImageLightbox({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(0.92),
        body: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 4.0,
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatVideoPlayer extends StatefulWidget {
  final String url;
  const _ChatVideoPlayer({required this.url});

  @override
  State<_ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

class _ChatVideoPlayerState extends State<_ChatVideoPlayer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializeFuture;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initializeFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Não foi possível reproduzir este vídeo.',
            style: TextStyle(color: _C.textMuted),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 280,
            height: 160,
            child: Center(
              child: CircularProgressIndicator(color: _C.blurple),
            ),
          );
        }

        final aspectRatio = _controller.value.aspectRatio > 0
            ? _controller.value.aspectRatio
            : 16 / 9;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Center(child: VideoPlayer(_controller)),
                    Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _controller,
                            builder: (context, value, child) => IconButton(
                              onPressed: value.isPlaying
                                  ? _controller.pause
                                  : _controller.play,
                              icon: Icon(
                                value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Expanded(
                            child: VideoProgressIndicator(
                              _controller,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: _C.blurple,
                                bufferedColor: _C.textMuted,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageInputBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final Future<void> Function(XFile) onSendMedia;
  final String channelName;

  const _MessageInputBar(
      {required this.controller,
      required this.onSend,
      required this.onSendMedia,
      required this.channelName});

  @override
  State<_MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<_MessageInputBar> {
  bool _sendingMedia = false;

  Future<void> _pickAndSendMedia() async {
    final selectedType = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _C.darker,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_rounded, color: _C.blurple),
              title: const Text('Enviar foto (até 5 MB)'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded, color: _C.blurple),
              title: const Text('Enviar vídeo (até 20 MB)'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (selectedType == null || !mounted) return;

    setState(() => _sendingMedia = true);
    try {
      final picker = ImagePicker();
      final file = selectedType == 'image'
          ? await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1920,
              maxHeight: 1920,
              imageQuality: 85,
            )
          : await picker.pickVideo(source: ImageSource.gallery);
      if (file != null) {
        await widget.onSendMedia(file);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível enviar a mídia: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Barra de input flutuante em vidro: pílula arredondada, sombra
    // difusa, borda clara e padding simétrico — placeholder e ícone de
    // enviar alinhados dentro dos limites.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.7)),
          boxShadow: _C.softShadow,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Enviar foto ou vídeo',
              onPressed: _sendingMedia ? null : _pickAndSendMedia,
              icon: _sendingMedia
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _C.blurple,
                      ),
                    )
                  : const Icon(Icons.add_circle_outline_rounded,
                      color: _C.textMuted),
            ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                style: const TextStyle(color: _C.textNormal, fontSize: 15),
                cursorColor: _C.blurple,
                decoration: InputDecoration(
                  hintText: 'Conversar em #${widget.channelName}',
                  hintStyle: const TextStyle(color: _C.textMuted),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                ),
                onSubmitted: (_) => widget.onSend(),
                textInputAction: TextInputAction.send,
              ),
            ),
            // Botão de enviar em pílula de acento (está dentro do raio
            // do container, mantendo o alinhamento vertical).
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: const BoxDecoration(
                color: _C.blurple,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Enviar mensagem',
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
                onPressed: widget.onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// TELA DE CHAT EM TELA CHEIA (MOBILE)
// =========================================================================
class _MobileChatScreen extends StatelessWidget {
  final String channelName;
  final String displayName;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final Future<void> Function(XFile) onSendMedia;
  final String myUserId;
  final String serverId;

  const _MobileChatScreen({
    required this.channelName,
    required this.displayName,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    required this.onSendMedia,
    required this.myUserId,
    required this.serverId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.chatBg,
      appBar: AppBar(
        backgroundColor: _C.chatBg,
        elevation: 0,
        title: Text('# $displayName',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: _C.textHeader,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Adicionar amigo',
            icon:
                const Icon(Icons.person_add_alt_1_rounded, color: _C.textMuted),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _AddFriendDialog(myUserId: myUserId),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _MessagesList(
              channelName: channelName,
              scrollController: scrollController,
              myUserId: myUserId,
              serverId: serverId,
            ),
          ),
          _MessageInputBar(
            controller: controller,
            onSend: onSend,
            onSendMedia: onSendMedia,
            channelName: displayName,
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// TELA "AMIGOS" EM TELA CHEIA (MOBILE)
// =========================================================================
// Como no mobile não há espaço para duas colunas lado a lado, juntamos
// "Amigos" e "Conversas privadas" numa única tela rolável — tocar em
// qualquer amigo ou conversa abre o chat em tela cheia (_MobileDmChatScreen).
class _MobileFriendsScreen extends StatefulWidget {
  final String myUserId;
  final Future<void> Function() onPublicServerJoined;
  const _MobileFriendsScreen({
    required this.myUserId,
    required this.onPublicServerJoined,
  });

  @override
  State<_MobileFriendsScreen> createState() => _MobileFriendsScreenState();
}

class _MobileFriendsScreenState extends State<_MobileFriendsScreen> {
  late Future<List<Profile>> _friendsFuture;
  late Future<List<DmConversation>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _friendsFuture = FriendService.fetchAcceptedFriends(widget.myUserId);
    _conversationsFuture = DmService.fetchMyConversations(widget.myUserId);
  }

  void _refresh() {
    setState(() {
      _friendsFuture = FriendService.fetchAcceptedFriends(widget.myUserId);
      _conversationsFuture = DmService.fetchMyConversations(widget.myUserId);
    });
  }

  Future<void> _openConversationWith(Profile friend) async {
    final conversationId = await DmService.getOrCreateConversation(friend.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MobileDmChatScreen(
          conversationId: conversationId,
          otherUser: friend,
          myUserId: widget.myUserId,
          onPublicServerJoined: widget.onPublicServerJoined,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _openConversation(DmConversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MobileDmChatScreen(
          conversationId: conversation.id,
          otherUser: conversation.otherUser,
          myUserId: widget.myUserId,
          onPublicServerJoined: widget.onPublicServerJoined,
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.chatBg,
      appBar: AppBar(
        backgroundColor: _C.chatBg,
        elevation: 0,
        title: const Text('Amigos',
            style:
                TextStyle(color: _C.textHeader, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Adicionar amigo',
            icon:
                const Icon(Icons.person_add_alt_1_rounded, color: _C.textMuted),
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => _AddFriendDialog(myUserId: widget.myUserId),
              );
              _refresh();
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('AMIGOS',
                style: TextStyle(
                    color: _C.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          FutureBuilder<List<Profile>>(
            future: _friendsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: CircularProgressIndicator(color: _C.blurple)),
                );
              }
              final friends = snapshot.data!;
              if (friends.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Nenhum amigo ainda.',
                      style: TextStyle(color: _C.textMuted)),
                );
              }
              return Column(
                children: friends.map((friend) {
                  return ListTile(
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
                        style:
                            const TextStyle(color: _C.textMuted, fontSize: 12)),
                    onTap: () => _openConversationWith(friend),
                  );
                }).toList(),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('CONVERSAS PRIVADAS',
                style: TextStyle(
                    color: _C.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          FutureBuilder<List<DmConversation>>(
            future: _conversationsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: CircularProgressIndicator(color: _C.blurple)),
                );
              }
              final conversations = snapshot.data!;
              if (conversations.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Nenhuma conversa ainda.',
                      style: TextStyle(color: _C.textMuted)),
                );
              }
              return Column(
                children: conversations.map((conv) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _C.blurple,
                      backgroundImage: conv.otherUser.avatarUrl != null
                          ? NetworkImage(conv.otherUser.avatarUrl!)
                          : null,
                      child: conv.otherUser.avatarUrl == null
                          ? Text(conv.otherUser.displayName[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white))
                          : null,
                    ),
                    title: Text(conv.otherUser.displayName,
                        style: const TextStyle(color: Colors.white)),
                    onTap: () => _openConversation(conv),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// CHAT DE UMA CONVERSA PRIVADA EM TELA CHEIA (MOBILE)
// =========================================================================
class _MobileDmChatScreen extends StatefulWidget {
  final String conversationId;
  final Profile otherUser;
  final String myUserId;
  final Future<void> Function() onPublicServerJoined;

  const _MobileDmChatScreen({
    required this.conversationId,
    required this.otherUser,
    required this.myUserId,
    required this.onPublicServerJoined,
  });

  @override
  State<_MobileDmChatScreen> createState() => _MobileDmChatScreenState();
}

class _MobileDmChatScreenState extends State<_MobileDmChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    try {
      await DmService.sendMessage(
        conversationId: widget.conversationId,
        senderId: widget.myUserId,
        content: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao enviar mensagem: $e')));
      }
    }
  }

  Future<void> _sendMedia(XFile file) async {
    final attachment = await ChatMediaService.upload(
      userId: widget.myUserId,
      file: file,
    );
    await DmService.sendMessage(
      conversationId: widget.conversationId,
      senderId: widget.myUserId,
      content: _controller.text,
      attachment: attachment,
    );
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.chatBg,
      appBar: AppBar(
        backgroundColor: _C.chatBg,
        elevation: 0,
        title: Text(widget.otherUser.displayName,
            style: const TextStyle(
                color: _C.textHeader,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _DmMessagesList(
              conversationId: widget.conversationId,
              scrollController: _scrollController,
              myUserId: widget.myUserId,
              onPublicServerJoined: widget.onPublicServerJoined,
            ),
          ),
          _MessageInputBar(
            controller: _controller,
            onSend: _send,
            onSendMedia: _sendMedia,
            channelName: '@${widget.otherUser.username}',
          ),
        ],
      ),
    );
  }
}
