import '../models/models.dart';
import 'supabase_client.dart';

// =========================================================================
// FRIEND SERVICE
// =========================================================================

/// Estado do relacionamento entre "eu" e outro usuário — usado para
/// decidir o que mostrar no botão da tela de perfil.
enum FriendshipStatus {
  none, // nenhum pedido entre nós
  pendingSentByMe, // eu mandei, esperando resposta
  pendingReceivedByMe, // ele mandou pra mim, esperando EU responder
  friends, // já aceito dos dois lados
}

class FriendService {
  /// Envia um pedido de amizade. Usa UPSERT (não INSERT simples) para
  /// que reenviar um pedido depois de uma recusa anterior funcione —
  /// com INSERT puro, a constraint UNIQUE(sender_id, receiver_id) do
  /// banco bloquearia a segunda tentativa mesmo já tendo sido recusada.
  static Future<void> sendFriendRequest({
    required String senderId,
    required String receiverId,
  }) async {
    await supabase.from('friend_requests').upsert(
      {
        'sender_id': senderId,
        'receiver_id': receiverId,
        'status': 'pending',
        'responded_at': null,
      },
      onConflict: 'sender_id,receiver_id',
    );
  }

  static Future<void> respondToRequest({
    required String requestId,
    required bool accept,
  }) async {
    await supabase.from('friend_requests').update({
      'status': accept ? 'accepted' : 'rejected',
      'responded_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);
  }

  /// Verifica o relacionamento com outro usuário — usado pela tela de
  /// perfil para decidir o que mostrar: "Adicionar amigo", "Pedido
  /// enviado", "Aceitar pedido" ou nada (já são amigos).
  /// Retorna também o `requestId`, necessário caso o botão precise
  /// aceitar um pedido recebido diretamente do perfil.
  static Future<(FriendshipStatus, String?)> getRelationshipStatus({
    required String myUserId,
    required String otherUserId,
  }) async {
    final rows = await supabase
        .from('friend_requests')
        .select('id, sender_id, status')
        .or('and(sender_id.eq.$myUserId,receiver_id.eq.$otherUserId),'
            'and(sender_id.eq.$otherUserId,receiver_id.eq.$myUserId)')
        .limit(1);

    if (rows.isEmpty) return (FriendshipStatus.none, null);

    final row = rows.first;
    final status = row['status'] as String;
    final requestId = row['id'] as String;

    if (status == 'accepted') return (FriendshipStatus.friends, requestId);
    if (status == 'rejected') return (FriendshipStatus.none, null);

    // status == 'pending'
    final iAmSender = row['sender_id'] == myUserId;
    return (
      iAmSender ? FriendshipStatus.pendingSentByMe : FriendshipStatus.pendingReceivedByMe,
      requestId,
    );
  }

  /// Lista (uma vez) os pedidos PENDENTES recebidos por mim, já com o
  /// perfil de quem enviou.
  static Future<List<FriendRequestModel>> fetchPendingReceived(
      String myUserId) async {
    final rows = await supabase
        .from('friend_requests')
        .select('*, profiles!friend_requests_sender_id_fkey(*)')
        .eq('receiver_id', myUserId)
        .eq('status', 'pending')
        .order('created_at');

    return rows
        .map<FriendRequestModel>((row) => FriendRequestModel.fromMap(
              row,
              otherUserMap: row['profiles'] as Map<String, dynamic>,
            ))
        .toList();
  }

  /// Lista os amigos JÁ ACEITOS (para a seção "Amigos" da barra lateral).
  /// Como um pedido aceito pode ter sido enviado por mim ou recebido por
  /// mim, fazemos duas consultas (uma para cada direção) e juntamos —
  /// o Postgrest não resolve bem um "join na direção que for" numa
  /// query só quando a tabela referencia a mesma outra tabela duas vezes.
  static Future<List<Profile>> fetchAcceptedFriends(String myUserId) async {
    final sentRows = await supabase
        .from('friend_requests')
        .select('profiles!friend_requests_receiver_id_fkey(*)')
        .eq('sender_id', myUserId)
        .eq('status', 'accepted');

    final receivedRows = await supabase
        .from('friend_requests')
        .select('profiles!friend_requests_sender_id_fkey(*)')
        .eq('receiver_id', myUserId)
        .eq('status', 'accepted');

    final friends = [
      ...sentRows.map((r) => Profile.fromMap(r['profiles'] as Map<String, dynamic>)),
      ...receivedRows.map((r) => Profile.fromMap(r['profiles'] as Map<String, dynamic>)),
    ];

    friends.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return friends;
  }

  /// Stream que emite a CONTAGEM de pedidos pendentes recebidos — é isso
  /// que alimenta o badge numérico no ícone de notificações. Sempre que
  /// alguém te manda ou responde um pedido, o número atualiza sozinho.
  static Stream<int> watchPendingCount(String myUserId) {
    return supabase
        .from('friend_requests')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', myUserId)
        .map((rows) => rows.where((r) => r['status'] == 'pending').length);
  }
}