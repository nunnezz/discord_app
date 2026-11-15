import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../services/friend_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_client.dart';

// Cores reaproveitadas do tema Cord — ajuste o import se você já tem
// essas constantes centralizadas em outro arquivo (ex: CordColors).
class _C {
  static const bg = Color(0xFF313338);
  static const darker = Color(0xFF2B2D31);
  static const blurple = Color(0xFF5865F2);
  static const green = Color(0xFF23A55A);
  static const textMuted = Color(0xFF949BA4);
  static const textHeader = Color(0xFFF2F3F5);
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

  // Só usado quando !isOwnProfile — decide o que o botão de amizade mostra.
  Future<(FriendshipStatus, String?)>? _relationshipFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (!widget.isOwnProfile) {
      _loadRelationship();
    }
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
      appBar: AppBar(
        backgroundColor: _C.bg,
        elevation: 0,
        title: const Text('Perfil'),
      ),
      // StreamBuilder mantém a tela sempre sincronizada com o banco: se
      // você editar o perfil em outro dispositivo, esta tela atualiza
      // sozinha, sem precisar de F5 nem pull-to-refresh.
      body: StreamBuilder<Profile>(
        stream: ProfileService.watchMyProfile(widget.userId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _C.blurple),
            );
          }
          final profile = snapshot.data!;
          return Column(
            children: [
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 48,
                backgroundColor: _C.blurple,
                backgroundImage:
                    profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
                child: profile.avatarUrl == null
                    ? Text(
                        profile.displayName.isNotEmpty
                            ? profile.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(color: Colors.white, fontSize: 32),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                profile.displayName,
                style: const TextStyle(
                  color: _C.textHeader,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '@${profile.username}',
                style: const TextStyle(color: _C.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 8),
              if (profile.bio.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    profile.bio,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _C.textMuted, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 16),
              if (widget.isOwnProfile)
                OutlinedButton.icon(
                  onPressed: () => _openEditSheet(profile),
                  icon: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                  label: const Text('Editar perfil',
                      style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _C.textMuted),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                )
              else
                _FriendActionButton(
                  profile: profile,
                  relationshipFuture: _relationshipFuture,
                  onSendRequest: () => _sendFriendRequest(profile),
                  onRespond: _respondToRequest,
                ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: _C.textMuted,
                indicatorColor: _C.blurple,
                tabs: const [
                  Tab(text: 'Principal'),
                  Tab(text: 'Lista de desejos'),
                ],
              ),
              Expanded(
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Sobre mim',
            style: TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          profile.bio.isEmpty ? 'Este usuário ainda não escreveu uma bio.' : profile.bio,
          style: TextStyle(
            color: profile.bio.isEmpty ? _C.textMuted : Colors.white,
            fontStyle: profile.bio.isEmpty ? FontStyle.italic : FontStyle.normal,
            height: 1.4,
          ),
        ),
      ],
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
    return const Center(
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
          return const SizedBox(
            height: 36,
            width: 36,
            child: CircularProgressIndicator(strokeWidth: 2, color: _C.blurple),
          );
        }

        final (status, requestId) = snapshot.data!;

        switch (status) {
          case FriendshipStatus.friends:
            return Chip(
              avatar: const Icon(Icons.check_circle_rounded, color: _C.green, size: 18),
              label: const Text('Vocês são amigos', style: TextStyle(color: Colors.white)),
              backgroundColor: _C.darker,
            );

          case FriendshipStatus.pendingSentByMe:
            return OutlinedButton.icon(
              onPressed: null, // desabilitado: já esperando resposta
              icon: const Icon(Icons.hourglass_top_rounded, size: 16),
              label: const Text('Pedido enviado'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _C.textMuted),
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
                  style: ElevatedButton.styleFrom(backgroundColor: _C.blurple),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => onRespond(requestId!, false),
                  child: const Text('Recusar', style: TextStyle(color: _C.textMuted)),
                ),
              ],
            );

          case FriendshipStatus.none:
            return ElevatedButton.icon(
              onPressed: onSendRequest,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Adicionar amigo'),
              style: ElevatedButton.styleFrom(backgroundColor: _C.blurple),
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
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512);
    if (file != null) setState(() => _pickedImage = file);
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
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 40,
                backgroundColor: _C.blurple,
                backgroundImage: _pickedImage != null
                    ? null // preview via FutureBuilder seria ideal em produção
                    : (widget.profile.avatarUrl != null
                        ? NetworkImage(widget.profile.avatarUrl!)
                        : null),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Nome de exibição',
              style: TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Nome exibido para todos',
            ),
          ),
          const SizedBox(height: 16),
          const Text('BIO',
              style: TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _bioController,
            style: const TextStyle(color: Colors.white),
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