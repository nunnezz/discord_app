// =========================================================================
// MODELOS — mapeiam 1:1 as linhas das tabelas do Supabase para objetos Dart.
// Cada modelo tem um `fromMap` (leitura) e, quando fizer sentido, um
// `toMap` (escrita) usado nos `.insert()` / `.update()`.
// =========================================================================

/// Espelha a tabela `profiles`.
class Profile {
  final String id; // mesmo id do auth.users
  final String username; // ex: "nikita_da_jogada" (sem @)
  final String displayName;
  final String? avatarUrl;
  final String statusMessage;

  /// Texto livre de até 500 caracteres, exibido na tela de perfil.
  final String bio;

  const Profile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.statusMessage,
    required this.bio,
    this.avatarUrl,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      username: map['username'] as String,
      displayName:
          (map['display_name'] as String?) ?? map['username'] as String,
      avatarUrl: map['avatar_url'] as String?,
      statusMessage:
          (map['status_message'] as String?) ?? 'O que você tem ouvido?',
      bio: (map['bio'] as String?) ?? '',
    );
  }

  /// Usado apenas para os campos que o próprio usuário pode editar.
  Map<String, dynamic> toUpdateMap() {
    return {
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'status_message': statusMessage,
      'bio': bio,
    };
  }

  Profile copyWith({
    String? displayName,
    String? avatarUrl,
    String? statusMessage,
    String? bio,
  }) {
    return Profile(
      id: id,
      username: username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      statusMessage: statusMessage ?? this.statusMessage,
      bio: bio ?? this.bio,
    );
  }
}

/// Espelha a tabela `friend_requests`, já com o perfil do OUTRO usuário
/// resolvido via join — facilita muito a exibição na tela de notificações.
class FriendRequestModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String status; // 'pending' | 'accepted' | 'rejected'
  final DateTime createdAt;
  final Profile
      otherUser; // quem enviou (se eu sou o destinatário) ou quem recebeu

  const FriendRequestModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    required this.otherUser,
  });

  factory FriendRequestModel.fromMap(
    Map<String, dynamic> map, {
    required Map<String, dynamic> otherUserMap,
  }) {
    return FriendRequestModel(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      receiverId: map['receiver_id'] as String,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      otherUser: Profile.fromMap(otherUserMap),
    );
  }
}

String _profileDisplayName(Map<String, dynamic>? profile) {
  final displayName = (profile?['display_name'] as String?)?.trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;

  final username = (profile?['username'] as String?)?.trim();
  if (username != null && username.isNotEmpty) return username;
  return 'desconhecido';
}

String? _profileAvatarUrl(Map<String, dynamic>? profile) {
  final avatarUrl = (profile?['avatar_url'] as String?)?.trim();
  return avatarUrl == null || avatarUrl.isEmpty ? null : avatarUrl;
}

/// Espelha a tabela `messages`, já com o nome de exibição atual do remetente.
class MessageModel {
  final String id;
  final String channel;
  final String senderId;
  final String senderDisplayName;
  final String? senderAvatarUrl;
  final String content;
  final String? mediaPath;
  final String? mediaType;
  final String? mediaName;
  final String? mediaUrl;
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    required this.channel,
    required this.senderId,
    required this.senderDisplayName,
    this.senderAvatarUrl,
    required this.content,
    this.mediaPath,
    this.mediaType,
    this.mediaName,
    this.mediaUrl,
    required this.createdAt,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    final profileMap = map['profiles'] as Map<String, dynamic>?;
    return MessageModel(
      id: map['id'] as String,
      channel: map['channel'] as String,
      senderId: map['sender_id'] as String,
      senderDisplayName: _profileDisplayName(profileMap),
      senderAvatarUrl: _profileAvatarUrl(profileMap),
      content: map['content'] as String? ?? '',
      mediaPath: map['media_path'] as String?,
      mediaType: map['media_type'] as String?,
      mediaName: map['media_name'] as String?,
      mediaUrl: map['media_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}

/// Uma conversa privada (DM) entre dois usuários — já com o perfil do
/// OUTRO participante resolvido (nunca o seu próprio).
class DmConversation {
  final String id;
  final Profile otherUser;
  final DateTime createdAt;

  const DmConversation({
    required this.id,
    required this.otherUser,
    required this.createdAt,
  });
}

/// Espelha a tabela `direct_messages`, já com o remetente resolvido.
class DirectMessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderDisplayName;
  final String? senderAvatarUrl;
  final String content;
  final String? mediaPath;
  final String? mediaType;
  final String? mediaName;
  final String? mediaUrl;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const DirectMessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderDisplayName,
    this.senderAvatarUrl,
    required this.content,
    this.mediaPath,
    this.mediaType,
    this.mediaName,
    this.mediaUrl,
    required this.createdAt,
    this.expiresAt,
  });

  factory DirectMessageModel.fromMap(Map<String, dynamic> map) {
    final profileMap = map['profiles'] as Map<String, dynamic>?;
    return DirectMessageModel(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      senderDisplayName: _profileDisplayName(profileMap),
      senderAvatarUrl: _profileAvatarUrl(profileMap),
      content: map['content'] as String? ?? '',
      mediaPath: map['media_path'] as String?,
      mediaType: map['media_type'] as String?,
      mediaName: map['media_name'] as String?,
      mediaUrl: map['media_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      expiresAt: map['expires_at'] == null
          ? null
          : DateTime.parse(map['expires_at'] as String).toLocal(),
    );
  }
}

/// Espelha a tabela `servers`.
class ServerModel {
  final String id;
  final String name;
  final String iconText;
  final String ownerId;
  final bool isPublic;

  const ServerModel({
    required this.id,
    required this.name,
    required this.iconText,
    required this.ownerId,
    required this.isPublic,
  });

  factory ServerModel.fromMap(Map<String, dynamic> map) {
    final name = map['name'] as String;
    return ServerModel(
      id: map['id'] as String,
      name: name,
      iconText: (map['icon_text'] as String?)?.isNotEmpty == true
          ? map['icon_text'] as String
          : (name.isNotEmpty ? name[0].toUpperCase() : '?'),
      ownerId: map['owner_id'] as String,
      isPublic: map['is_public'] as bool? ?? false,
    );
  }
}

/// Espelha a tabela `channels` (canais de um servidor real, criado pelo
/// usuário — não confundir com os canais estáticos do servidor "Cord").
enum ServerChannelType { text, voice }

class ServerChannelModel {
  final String id;
  final String serverId;
  final String name;
  final ServerChannelType type;
  final int position;

  const ServerChannelModel({
    required this.id,
    required this.serverId,
    required this.name,
    required this.type,
    required this.position,
  });

  factory ServerChannelModel.fromMap(Map<String, dynamic> map) {
    return ServerChannelModel(
      id: map['id'] as String,
      serverId: map['server_id'] as String,
      name: map['name'] as String,
      type: (map['type'] as String) == 'voice'
          ? ServerChannelType.voice
          : ServerChannelType.text,
      position: (map['position'] as num?)?.toInt() ?? 0,
    );
  }
}
