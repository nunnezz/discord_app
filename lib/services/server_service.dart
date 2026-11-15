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
        .map<ServerModel>((row) => ServerModel.fromMap(row['servers'] as Map<String, dynamic>))
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
        .update({'is_public': isPublic})
        .eq('id', serverId);
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
}
