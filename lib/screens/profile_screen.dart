import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../services/friend_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_client.dart';
import '../theme/app_theme.dart';

// Paleta clara compartilhada com o design system do chat (cord_home_page).
class _C {
  static bool get _dark => AppTheme.isDark;

  static Color get bg =>
      _dark ? const Color(0xFF0B0F1A) : const Color(0xFFF8FAFC);
  static Color get darker =>
      _dark ? const Color(0xFF111827) : const Color(0xFFFFFFFF);
  static Color get blurple =>
      _dark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);
  static Color get green =>
      _dark ? const Color(0xFF38BDF8) : const Color(0xFF0EA5E9);
  static Color get textNormal =>
      _dark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
  static Color get textMuted =>
      _dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color get textHeader =>
      _dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  static Color get divider =>
      _dark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
  static const red = Color(0xFFE11D48);

  static Color get card => cardBg;
  static Color get cardBg => _dark
      ? const Color(0xFF111827).withValues(alpha: 0.85)
      : Colors.white.withValues(alpha: 0.8);
  static Color get glassBorder => _dark
      ? const Color(0xFF1E293B).withValues(alpha: 0.6)
      : Colors.white.withValues(alpha: 0.6);

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

/// Tela de perfil do usuário logado (ou de outro usuário, em modo leitura).
class ProfileScreen extends StatefulWidget {
  final String userId;

  /// Se for o perfil do próprio usuário logado, mostramos o botão
  /// "Editar perfil". Se for o perfil de outro usuário (ex: clicou no
  /// avatar de alguém no chat), mostramos em modo somente leitura.
  final bool isOwnProfile;

  const ProfileScreen({
    super.key,
    required this.userId,
    this.isOwnProfile = true,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<Profile> _profileFuture;

  // Só usado quando !isOwnProfile — decide o que o botão de amizade mostra.
  Future<(FriendshipStatus, String?)>? _relationshipFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _profileFuture = _fetchProfile();
    if (!widget.isOwnProfile) {
      _loadRelationship();
    }
  }

  Future<Profile> _fetchProfile() {
    return ProfileService.fetchProfile(widget.userId)
        .timeout(const Duration(seconds: 20));
  }

  void _loadRelationship() {
    final myId = currentAuthUser?.id;
    if (myId == null) return;
    setState(() {
      _relationshipFuture = FriendService.getRelationshipStatus(
        myUserId: myId,
        otherUserId: widget.userId,
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openEditSheet(Profile profile) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _C.darker,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _EditProfileSheet(profile: profile),
    );
    if (!mounted) return;
    setState(() => _profileFuture = _fetchProfile());
  }

  Future<void> _sendFriendRequest(Profile profile) async {
    final myId = currentAuthUser?.id;
    if (myId == null) return;
    try {
      await FriendService.sendFriendRequest(senderId: myId, receiverId: profile.id);
      _loadRelationship();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao enviar pedido: $e')));
      }
    }
  }

  Future<void> _respondToRequest(String requestId, bool accept) async {
    try {
      await FriendService.respondToRequest(requestId: requestId, accept: accept);
      _loadRelationship();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      // HEADER claro: seta de voltar + título integrados numa barra
      // translúcida, sem aparência de app escuro legado.
      appBar: AppBar(
        backgroundColor: AppTheme.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.72),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _C.textHeader,
        title: const Text('Perfil',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<Profile>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Não foi possível carregar o perfil.',
                      style: TextStyle(color: _C.textHeader),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: TextStyle(color: _C.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () =>
                          setState(() => _profileFuture = _fetchProfile()),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: _C.blurple),
            );
          }
          final profile = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            children: [
              // ---------------- CARTÃO DE PERFIL (glass) ----------------
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                decoration: BoxDecoration(
                  color: _C.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _C.glassBorder),
                  boxShadow: _C.softShadow,
                ),
                child: Column(
                  children: [
                    // Avatar com anel refinado (borda dupla).
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _C.blurple, width: 2.5),
                      ),
                      child: CircleAvatar(
                        radius: 46,
                        backgroundColor: _C.blurple,
                        backgroundImage: profile.avatarUrl != null
                            ? NetworkImage(profile.avatarUrl!)
                            : null,
                        child: profile.avatarUrl == null
                            ? Text(
                                profile.displayName.isNotEmpty
                                    ? profile.displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      profile.displayName,
                      style: TextStyle(
                        color: _C.textHeader,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${profile.username}',
                      style: TextStyle(color: _C.textMuted, fontSize: 13.5),
                    ),
                    if (profile.bio.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        profile.bio,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _C.textMuted, fontSize: 13, height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (widget.isOwnProfile)
                      // BOTÃO PÍLULA moderno com acento indigo (StadiumBorder).
                      ElevatedButton.icon(
                        onPressed: () => _openEditSheet(profile),
                        icon: const Icon(Icons.edit_rounded,
                            size: 16, color: Colors.white),
                        label: const Text('Editar perfil',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _C.blurple,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                          shape: const StadiumBorder(),
                        ),
                      )
                    else
                      _FriendActionButton(
                        profile: profile,
                        relationshipFuture: _relationshipFuture,
                        onSendRequest: () => _sendFriendRequest(profile),
                        onRespond: _respondToRequest,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // ---------------- TABS (indicador em pill) ----------------
              Container(
                decoration: BoxDecoration(
                  color: _C.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _C.divider),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: _C.textHeader,
                  unselectedLabelColor: _C.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  unselectedLabelStyle:
                      const TextStyle(fontWeight: FontWeight.w500),
                  indicator: BoxDecoration(
                    color: _C.blurple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(height: 42, text: 'Principal'),
                    Tab(height: 42, text: 'Lista de desejos'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 320,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _MainTab(profile: profile),
                    const _WishlistTab(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MainTab extends StatelessWidget {
  final Profile profile;
  const _MainTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    // "Sobre mim" em seu próprio card arredondado com padding generoso.
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _C.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
        boxShadow: _C.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sobre mim',
              style: TextStyle(
                  color: _C.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(
            profile.bio.isEmpty
                ? 'Este usuário ainda não escreveu uma bio.'
                : profile.bio,
            style: TextStyle(
              color: profile.bio.isEmpty ? _C.textMuted : _C.textHeader,
              fontStyle:
                  profile.bio.isEmpty ? FontStyle.italic : FontStyle.normal,
              height: 1.45,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _WishlistTab extends StatelessWidget {
  const _WishlistTab();

  @override
  Widget build(BuildContext context) {
    // Placeholder — plugue aqui uma tabela `wishlist_items` no Supabase
    // do mesmo jeito que fizemos com profiles/messages, se quiser essa
    // aba funcional de verdade.
    return Center(
      child: Text('Nenhum item na lista de desejos ainda.',
          style: TextStyle(color: _C.textMuted)),
    );
  }
}

/// Botão exibido quando você visita o perfil de OUTRA pessoa. Muda de
/// aparência dependendo do relacionamento atual entre vocês dois.
class _FriendActionButton extends StatelessWidget {
  final Profile profile;
  final Future<(FriendshipStatus, String?)>? relationshipFuture;
  final VoidCallback onSendRequest;
  final void Function(String requestId, bool accept) onRespond;

  const _FriendActionButton({
    required this.profile,
    required this.relationshipFuture,
    required this.onSendRequest,
    required this.onRespond,
  });

  @override
  Widget build(BuildContext context) {
    if (relationshipFuture == null) return const SizedBox.shrink();

    return FutureBuilder<(FriendshipStatus, String?)>(
      future: relationshipFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            height: 36,
            width: 36,
            child: CircularProgressIndicator(strokeWidth: 2, color: _C.blurple),
          );
        }

        final (status, requestId) = snapshot.data!;

        switch (status) {
          case FriendshipStatus.friends:
            return Chip(
              avatar: Icon(Icons.check_circle_rounded,
                  color: _C.green, size: 18),
              label: Text('Vocês são amigos',
                  style: TextStyle(color: _C.textHeader)),
              backgroundColor: _C.darker,
            );

          case FriendshipStatus.pendingSentByMe:
            return OutlinedButton.icon(
              onPressed: null, // desabilitado: já esperando resposta
              icon: const Icon(Icons.hourglass_top_rounded, size: 16),
              label: const Text('Pedido enviado'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _C.textMuted),
                foregroundColor: _C.textMuted,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            );

          case FriendshipStatus.pendingReceivedByMe:
            // Ele te mandou um pedido — deixa aceitar/recusar direto do perfil.
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => onRespond(requestId!, true),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Aceitar pedido'),
                  style: ElevatedButton.styleFrom(backgroundColor: _C.blurple)
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => onRespond(requestId!, false),
                  child: Text('Recusar',
                      style: TextStyle(color: _C.textMuted)),
                ),
              ],
            );

          case FriendshipStatus.none:
            return ElevatedButton.icon(
              onPressed: onSendRequest,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Adicionar amigo'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _C.blurple),
            );
        }
      },
    );
  }
}

/// Bottom sheet de edição: nome de exibição, status e foto.
class _EditProfileSheet extends StatefulWidget {
  final Profile profile;
  const _EditProfileSheet({required this.profile});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  static const int _maxBioLength = 500;

  late final TextEditingController _nameController =
      TextEditingController(text: widget.profile.displayName);
  late final TextEditingController _bioController =
      TextEditingController(text: widget.profile.bio);

  XFile? _pickedImage;
  Uint8List? _pickedImageBytes;
  bool _pickingImage = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_saving || _pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw const FormatException('A imagem selecionada está vazia.');
      }
      if (!mounted) return;
      setState(() {
        _pickedImage = file;
        _pickedImageBytes = bytes;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível escolher a foto: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('O nome de exibição não pode ficar vazio.')));
      return;
    }

    setState(() => _saving = true);
    try {
      String? avatarUrl = widget.profile.avatarUrl;
      if (_pickedImage != null) {
        avatarUrl = await ProfileService.uploadAvatar(widget.profile.id, _pickedImage!);
      }

      final updated = widget.profile.copyWith(
        displayName: name,
        bio: _bioController.text.trim(),
        avatarUrl: avatarUrl,
      );

      await ProfileService.updateProfile(updated);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildAvatarPreview() {
    final bytes = _pickedImageBytes;
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(
          bytes,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.person_rounded, color: Colors.white, size: 36),
        ),
      );
    }

    final avatarUrl = widget.profile.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.person_rounded, color: Colors.white, size: 36),
        ),
      );
    }

    return const Icon(Icons.person_rounded, color: Colors.white, size: 36);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Editar perfil',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickingImage || _saving ? null : _pickImage,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: _C.blurple,
                        child: _buildAvatarPreview()
                      ),
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: _C.darker,
                        child: Icon(
                          _pickingImage ? Icons.hourglass_top_rounded : Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickingImage || _saving ? null : _pickImage,
                  icon: _pickingImage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _pickingImage
                        ? 'Carregando imagem...'
                        : _pickedImage == null
                            ? 'Escolher foto'
                            : 'Trocar foto',
                  ),
                ),
                if (_pickedImage != null)
                  Text(
                    'A foto será salva ao tocar em Salvar.',
                    style: TextStyle(color: _C.textMuted, fontSize: 12)
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Nome de exibição',
              style: TextStyle(
                  color: _C.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            style: TextStyle(color: _C.textHeader),
            decoration: const InputDecoration(
              hintText: 'Nome exibido para todos',
            ),
          ),
          const SizedBox(height: 16),
          Text('BIO',
              style: TextStyle(
                  color: _C.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _bioController,
            style: TextStyle(color: _C.textHeader),
            maxLength: _maxBioLength,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
              hintText: 'Conte um pouco sobre você...',
              alignLabelWithHint: true,
            ),
            // O contador "x/500" nativo do TextField já aparece sozinho
            // por causa do `maxLength` — não precisa montar um manual.
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: _C.blurple),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}