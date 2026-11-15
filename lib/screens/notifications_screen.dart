import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/friend_service.dart';
import '../services/supabase_client.dart';

class _C {
  static const bg = Color(0xFF313338);
  static const darker = Color(0xFF2B2D31);
  static const blurple = Color(0xFF5865F2);
  static const green = Color(0xFF23A55A);
  static const red = Color(0xFFDA373C);
  static const textMuted = Color(0xFF949BA4);
}

// =========================================================================
// ÍCONE COM BADGE — coloque este widget na sua barra de navegação
// inferior (mobile) ou onde quiser o sininho de notificações.
// =========================================================================
class NotificationBellIcon extends StatelessWidget {
  final VoidCallback onTap;
  const NotificationBellIcon({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final myId = currentAuthUser?.id;
    if (myId == null) return const Icon(Icons.notifications_rounded);

    return StreamBuilder<int>(
      // Esse stream já vem do FriendService — sempre que um pedido novo
      // chega (ou é respondido), o número no badge atualiza sozinho,
      // sem precisar de nenhum refresh manual.
      stream: FriendService.watchPendingCount(myId),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_rounded, color: Colors.white, size: 26),
              if (count > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _C.red,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.darker, width: 1.5),
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// =========================================================================
// TELA DE NOTIFICAÇÕES
// =========================================================================
//
// IMPORTANTE sobre "o número zera ao abrir a aba": o badge não conta
// "notificações não lidas" separadamente — ele conta pedidos com
// status = 'pending'. Então o número só some quando o pedido é
// Aceito/Recusado (não apenas visualizado). Isso é proposital: é o
// mesmo comportamento do Discord para pedidos de amizade (uma "tarefa"
// pendente, não uma notificação que se marca como lida sozinha).
// Se você preferir o comportamento de "sumir ao abrir a tela", veja o
// comentário no fim do arquivo com a alternativa usando `last_seen_at`.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<FriendRequestModel>> _futureRequests;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  void _loadRequests() {
    final myId = currentAuthUser!.id;
    _futureRequests = FriendService.fetchPendingReceived(myId);
  }

  Future<void> _respond(FriendRequestModel request, bool accept) async {
    await FriendService.respondToRequest(requestId: request.id, accept: accept);
    setState(_loadRequests); // recarrega a lista sem o pedido já respondido
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.bg,
        elevation: 0,
        title: const Text('Notificações'),
      ),
      body: FutureBuilder<List<FriendRequestModel>>(
        future: _futureRequests,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: _C.blurple));
          }
          final requests = snapshot.data!;
          if (requests.isEmpty) {
            return const Center(
              child: Text('Nenhum pedido de amizade pendente.',
                  style: TextStyle(color: _C.textMuted)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final request = requests[index];
              return _FriendRequestTile(
                request: request,
                onAccept: () => _respond(request, true),
                onReject: () => _respond(request, false),
              );
            },
          );
        },
      ),
    );
  }
}

class _FriendRequestTile extends StatelessWidget {
  final FriendRequestModel request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _FriendRequestTile({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.darker,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _C.blurple,
            backgroundImage: request.otherUser.avatarUrl != null
                ? NetworkImage(request.otherUser.avatarUrl!)
                : null,
            child: request.otherUser.avatarUrl == null
                ? Text(request.otherUser.displayName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.otherUser.displayName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text('@${request.otherUser.username} quer ser seu amigo',
                    style: const TextStyle(color: _C.textMuted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Aceitar',
            icon: const Icon(Icons.check_circle_rounded, color: _C.green),
            onPressed: onAccept,
          ),
          IconButton(
            tooltip: 'Recusar',
            icon: const Icon(Icons.cancel_rounded, color: _C.red),
            onPressed: onReject,
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// ALTERNATIVA: badge que zera ao simplesmente ABRIR a tela (mesmo com
// pedidos ainda pendentes) — se for isso que você quis dizer.
// Para isso, adicione ao schema: uma coluna
//   `last_notifications_seen_at timestamptz` na tabela `profiles`.
// E troque `watchPendingCount` para contar apenas pedidos com
// `created_at > last_notifications_seen_at`. Ao abrir a NotificationsScreen,
// dispare:
//   await supabase.from('profiles')
//       .update({'last_notifications_seen_at': DateTime.now().toIso8601String()})
//       .eq('id', myId);
// -------------------------------------------------------------------------
