import '../models/models.dart';
import 'supabase_client.dart';

// =========================================================================
// CHAT SERVICE
// =========================================================================
class ChatService {
  /// Envia uma mensagem para um canal de um servidor. `serverId` tem
  /// como padrão `'default'` — o servidor fixo "Cord" que já existia
  /// antes do sistema de múltiplos servidores, para manter 100% de
  /// compatibilidade com o histórico já testado.
  static Future<void> sendMessage({
    required String channel,
    required String senderId,
    required String content,
    String serverId = 'default',
  }) async {
    if (content.trim().isEmpty) return;
    await supabase.from('messages').insert({
      'channel': channel,
      'server_id': serverId,
      'sender_id': senderId,
      'content': content.trim(),
    });
  }

  /// Stream em tempo real das mensagens de um canal, já ordenadas por
  /// data. Cada nova inserção na tabela `messages` reflete aqui na hora,
  /// para todos os usuários conectados àquele canal.
  ///
  /// IMPORTANTE: o `.stream()` do supabase_flutter só suporta UM filtro
  /// `.eq()` no lado do servidor — por isso filtramos por `server_id`
  /// ali (é o mais seletivo entre servidores diferentes) e aplicamos o
  /// filtro por `channel` manualmente em `_resolveSenderUsernames`, do
  /// lado do cliente. Isso é necessário porque um mesmo nome de canal
  /// (ex: "geral") pode existir em servidores diferentes, e sem esse
  /// segundo filtro as mensagens de servidores distintos se misturariam.
  ///
  /// OBS: `.stream()` também não suporta `select()` com join direto,
  /// então resolvemos o nome de usuário do remetente com uma segunda
  /// consulta simples — para um protótipo isso é suficiente; em
  /// produção, considere cachear os perfis já vistos em um Map local
  /// para não repetir consultas.
  static Stream<List<MessageModel>> watchChannel(String channel, {String serverId = 'default'}) {
    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('server_id', serverId)
        .order('created_at')
        .asyncMap((rows) => _resolveSenderUsernames(rows, channel));
  }

  static final Map<String, String> _usernameCache = {};

  static Future<List<MessageModel>> _resolveSenderUsernames(
      List<Map<String, dynamic>> allRows, String channel) async {
    // Filtro do lado do cliente: só as linhas deste canal específico
    // (ver explicação em watchChannel acima).
    final rows = allRows.where((r) => r['channel'] == channel).toList();

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
      return MessageModel.fromMap(enrichedRow);
    }).toList()
      // Reordena explicitamente no Dart: o `.order('created_at')` do
      // `.stream()` do Supabase às vezes não se mantém entre as
      // atualizações incrementais (cada INSERT chega como um evento
      // separado e pode ser reaplicado fora de ordem). Ordenar aqui
      // garante SEMPRE mensagem mais antiga em cima, mais nova embaixo
      // — como qualquer chat normal.
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
}