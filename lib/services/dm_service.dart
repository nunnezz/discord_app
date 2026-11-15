import '../models/models.dart';
import 'supabase_client.dart';

// =========================================================================
// DM SERVICE
// =========================================================================
class DmService {
  /// Pega a conversa existente com esse usuário, ou cria uma nova — tudo
  /// resolvido atomicamente do lado do banco (função `get_or_create_dm_conversation`).
  static Future<String> getOrCreateConversation(String otherUserId) async {
    final result = await supabase.rpc(
      'get_or_create_dm_conversation',
      params: {'other_user_id': otherUserId},
    );
    return result as String;
  }

  /// Lista as conversas do usuário logado, cada uma já com o perfil do
  /// OUTRO participante resolvido (nunca o meu próprio).
  static Future<List<DmConversation>> fetchMyConversations(String myUserId) async {
    final rows = await supabase
        .from('dm_conversations')
        .select('id, user_a, user_b, created_at, '
            'profile_a:profiles!dm_conversations_user_a_fkey(*), '
            'profile_b:profiles!dm_conversations_user_b_fkey(*)')
        .or('user_a.eq.$myUserId,user_b.eq.$myUserId')
        .order('created_at', ascending: false);

    return rows.map<DmConversation>((row) {
      final isUserA = row['user_a'] == myUserId;
      final otherProfileMap = (isUserA ? row['profile_b'] : row['profile_a'])
          as Map<String, dynamic>;
      return DmConversation(
        id: row['id'] as String,
        otherUser: Profile.fromMap(otherProfileMap),
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
    }).toList();
  }

  static Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    if (content.trim().isEmpty) return;
    await supabase.from('direct_messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content.trim(),
    });
  }

  /// Mesmo padrão de cache leve do ChatService, mas separado por ser uma
  /// tabela diferente.
  static final Map<String, String> _usernameCache = {};

  static Stream<List<DirectMessageModel>> watchConversation(String conversationId) {
    return supabase
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .asyncMap(_resolveSenderUsernames);
  }

  static Future<List<DirectMessageModel>> _resolveSenderUsernames(
      List<Map<String, dynamic>> rows) async {
    final missingIds = rows
        .map((r) => r['sender_id'] as String)
        .toSet()
        .where((id) => !_usernameCache.containsKey(id))
        .toList();

    if (missingIds.isNotEmpty) {
      final profiles = await supabase
          .from('profiles')
          .select('id, username')
          .inFilter('id', missingIds);
      for (final p in profiles) {
        _usernameCache[p['id'] as String] = p['username'] as String;
      }
    }

    return rows.map((row) {
      final enrichedRow = Map<String, dynamic>.from(row);
      enrichedRow['profiles'] = {
        'username': _usernameCache[row['sender_id']] ?? 'desconhecido',
      };
      return DirectMessageModel.fromMap(enrichedRow);
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
}