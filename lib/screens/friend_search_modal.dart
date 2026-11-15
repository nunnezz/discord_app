import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/friend_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_client.dart';

class _C {
  static const bg = Color(0xFF313338);
  static const blurple = Color(0xFF5865F2);
  static const green = Color(0xFF23A55A);
  static const textMuted = Color(0xFF949BA4);
  static const error = Color(0xFFDA373C);
}

/// Abra com:
/// showDialog(context: context, builder: (_) => const FriendSearchModal());
class FriendSearchModal extends StatefulWidget {
  const FriendSearchModal({super.key});

  @override
  State<FriendSearchModal> createState() => _FriendSearchModalState();
}

class _FriendSearchModalState extends State<FriendSearchModal> {
  final TextEditingController _controller = TextEditingController();

  bool _searching = false;
  bool _searched = false; // já disparou ao menos uma busca?
  Profile? _foundProfile;
  bool _requestSent = false;

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _searched = true;
      _foundProfile = null;
      _requestSent = false;
    });

    final result = await ProfileService.searchByUsername(query);

    if (!mounted) return;
    setState(() {
      _searching = false;
      _foundProfile = result;
    });
  }

  Future<void> _sendRequest() async {
    final me = currentAuthUser;
    if (me == null || _foundProfile == null) return;

    try {
      await FriendService.sendFriendRequest(
        senderId: me.id,
        receiverId: _foundProfile!.id,
      );
      setState(() => _requestSent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você já enviou um pedido para este usuário.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _C.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Adicionar amigo',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Você pode adicionar amigos pelo nome de usuário do Cord.',
              style: TextStyle(color: _C.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Digite um nome de usuário',
                hintStyle: const TextStyle(color: _C.textMuted),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search_rounded, color: _C.blurple),
                  onPressed: _search,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_searching)
              const Center(child: CircularProgressIndicator(color: _C.blurple)),
            if (!_searching && _searched && _foundProfile == null)
              const _ResultMessage(
                icon: Icons.person_off_rounded,
                color: _C.error,
                text: 'Usuário não encontrado.',
              ),
            if (!_searching && _foundProfile != null) _FoundProfileTile(
              profile: _foundProfile!,
              requestSent: _requestSent,
              onAdd: _sendRequest,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _ResultMessage({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ],
    );
  }
}

class _FoundProfileTile extends StatelessWidget {
  final Profile profile;
  final bool requestSent;
  final VoidCallback onAdd;

  const _FoundProfileTile({
    required this.profile,
    required this.requestSent,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _C.blurple,
            backgroundImage:
                profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
            child: profile.avatarUrl == null
                ? Text(profile.displayName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.displayName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text('@${profile.username}',
                    style: const TextStyle(color: _C.textMuted, fontSize: 12)),
              ],
            ),
          ),
          if (requestSent)
            const Text('Pedido enviado', style: TextStyle(color: _C.green, fontSize: 12))
          else
            ElevatedButton(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(backgroundColor: _C.blurple),
              child: const Text('Adicionar'),
            ),
        ],
      ),
    );
  }
}
