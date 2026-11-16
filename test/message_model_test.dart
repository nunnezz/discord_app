import 'package:cord_app/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = {
    'display_name': 'Nome atualizado',
    'username': 'nome_antigo',
    'avatar_url': 'https://example.com/avatar.png',
  };

  test('server messages use the profile display name', () {
    final message = MessageModel.fromMap({
      'id': 'message-id',
      'channel': 'geral',
      'sender_id': 'user-id',
      'content': 'Olá',
      'created_at': '2026-11-15T12:00:00Z',
      'profiles': profile,
    });

    expect(message.senderDisplayName, 'Nome atualizado');
    expect(message.senderAvatarUrl, 'https://example.com/avatar.png');
  });

  test('direct messages use the profile display name', () {
    final message = DirectMessageModel.fromMap({
      'id': 'message-id',
      'conversation_id': 'conversation-id',
      'sender_id': 'user-id',
      'content': 'Olá',
      'created_at': '2026-11-15T12:00:00Z',
      'profiles': profile,
    });

    expect(message.senderDisplayName, 'Nome atualizado');
    expect(message.senderAvatarUrl, 'https://example.com/avatar.png');
  });

  test('chat messages can contain a media attachment without a caption', () {
    final message = MessageModel.fromMap({
      'id': 'message-id',
      'channel': 'geral',
      'sender_id': 'user-id',
      'content': '',
      'media_path': 'user-id/media.mp4',
      'media_type': 'video',
      'media_name': 'video.mp4',
      'media_url': 'https://example.com/signed-video',
      'created_at': '2026-11-15T12:00:00Z',
      'profiles': profile,
    });

    expect(message.content, isEmpty);
    expect(message.mediaPath, 'user-id/media.mp4');
    expect(message.mediaType, 'video');
    expect(message.mediaName, 'video.mp4');
    expect(message.mediaUrl, 'https://example.com/signed-video');
  });

  test('falls back to username when display name is empty', () {
    final message = MessageModel.fromMap({
      'id': 'message-id',
      'channel': 'geral',
      'sender_id': 'user-id',
      'content': 'Olá',
      'created_at': '2026-11-15T12:00:00Z',
      'profiles': {
        'display_name': ' ',
        'username': 'nome_antigo',
      },
    });

    expect(message.senderDisplayName, 'nome_antigo');
  });
}
