import '../models/models.dart';
import 'supabase_client.dart';

// =========================================================================
// SERVER SERVICE
// =========================================================================
class ServerService {
  /// Lista os servidores dos quais o usuário é membro (não inclui o
  /// "Cord" fixo — esse continua vivendo só no app, sem linha no banco).
  static Future<List<ServerModel>> fetchMyServers(String myUserId) async {
    final rows = await supabase
        .from('server_members')
        .select('servers(*)')
        .eq('user_id', myUserId)
        .order('joined_at');

    return rows
        .map<ServerModel>((row) =>
            ServerModel.fromMap(row['servers'] as Map<String, dynamic>))
        .toList();
  }

  static Future<List<ServerModel>> fetchPublicServers() async {
    final rows = await supabase
        .from('servers')
        .select('id, name, icon_text, owner_id, is_public')
        .eq('is_public', true)
        .order('name');

    return rows.map<ServerModel>(ServerModel.fromMap).toList();
  }

  /// Cria um servidor novo. O trigger `handle_new_server` no banco já
  /// cuida de: adicionar você como membro e criar os 2 canais padrão
  /// ("geral" e "Sala de Voz") — não precisa repetir essa lógica aqui.
  ///
  /// Repare que NÃO mandamos `owner_id` no insert: a coluna tem
  /// `default auth.uid()` no banco, preenchido automaticamente a
  /// partir do token de autenticação da requisição.
  ///
  /// Repare também que NÃO encadeamos `.select()` no insert. Quando
  /// você pede a linha de volta (`RETURNING`) numa tabela com RLS, o
  /// Postgres exige que essa linha também passe pela política de
  /// SELECT antes de devolvê-la — e usa a MESMA mensagem de erro
  /// genérica ("new row violates row-level security policy") tanto
  /// para uma falha no INSERT quanto nesse SELECT pós-insert. Isso
  /// torna impossível saber, só pela mensagem, qual dos dois falhou.
  /// Separar em duas operações elimina essa ambiguidade e qualquer
  /// interação estranha entre o trigger (que precisa rodar primeiro) e
  /// a política de SELECT sendo avaliada no meio do mesmo comando.
  static Future<void> createServer({
    required String name,
    required bool isPublic,
  }) async {
    await supabase.from('servers').insert({
      'name': name.trim(),
      'is_public': isPublic,
    });
  }

  static Future<void> setServerVisibility({
    required String serverId,
    required bool isPublic,
  }) async {
    await supabase
        .from('servers')
        .update({'is_public': isPublic}).eq('id', serverId);
  }

  static Future<String> createInvite(String serverId) async {
    final code = await supabase.rpc(
      'create_server_invite',
      params: {'target_server_id': serverId},
    );
    return code as String;
  }

  static Future<String> joinPublicServer(String serverId) async {
    final joinedServerId = await supabase.rpc(
      'join_public_server',
      params: {'target_server_id': serverId},
    );
    return joinedServerId as String;
  }

  static Future<bool> joinPublicServerFromVoiceInvite({
    required String serverId,
    required String userId,
  }) async {
    final memberships = await supabase
        .from('server_members')
        .select('server_id')
        .eq('server_id', serverId)
        .eq('user_id', userId);
    if (memberships.isNotEmpty) return true;

    final publicServers = await fetchPublicServers();
    if (!publicServers.any((server) => server.id == serverId)) return false;

    await joinPublicServer(serverId);
    return true;
  }

  static Future<String> joinServerWithInvite(String inviteCode) async {
    final serverId = await supabase.rpc(
      'join_server_with_invite',
      params: {'invite_code': inviteCode.trim()},
    );
    return serverId as String;
  }

  /// Lista os canais de um servidor, já ordenados (posição, depois nome).
  static Future<List<ServerChannelModel>> fetchChannels(String serverId) async {
    final rows = await supabase
        .from('channels')
        .select()
        .eq('server_id', serverId)
        .order('position');

    return rows.map<ServerChannelModel>(ServerChannelModel.fromMap).toList();
  }

  /// Cria um canal novo (texto ou voz) no servidor. O `name` é o nome
  /// exibido — o mesmo valor é usado como chave do chat/voz.
  static Future<void> createChannel({
    required String serverId,
    required String name,
    required bool isVoice,
  }) async {
    // Descobre a próxima posição livre dentro do tipo, pra o canal novo
    // aparecer por último na lista da categoria dele.
    final existing = await supabase
        .from('channels')
        .select('position')
        .eq('server_id', serverId)
        .eq('type', isVoice ? 'voice' : 'text');
    int maxPosition = -1;
    for (final row in existing) {
      final p = (row['position'] as num?)?.toInt() ?? 0;
      if (p > maxPosition) maxPosition = p;
    }

    await supabase.from('channels').insert({
      'server_id': serverId,
      'name': name.trim(),
      'type': isVoice ? 'voice' : 'text',
      'position': maxPosition + 1,
    });
  }

  /// Renomeia um canal existente.
  static Future<void> renameChannel({
    required String channelId,
    required String newName,
  }) async {
    await supabase
        .from('channels')
        .update({'name': newName.trim()}).eq('id', channelId);
  }

  /// Exclui um canal. As mensagens antigas continuam no banco (chaveadas
  /// pelo nome do canal), mas ficam inacessíveis pela UI.
  static Future<void> deleteChannel(String channelId) async {
    await supabase.from('channels').delete().eq('id', channelId);
  }
}
