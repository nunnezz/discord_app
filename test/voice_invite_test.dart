import 'package:cord_app/voice/voice_call_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voice invites expire at their stored deadline', () {
    final now = DateTime.utc(2026, 11, 16, 12);

    expect(
      isVoiceInviteExpired(now.add(const Duration(hours: 24)), now: now),
      isFalse,
    );
    expect(
      isVoiceInviteExpired(now, now: now),
      isTrue,
    );
  });

  test('extracts the server id before the voice channel name', () {
    expect(
      serverIdFromVoiceRoomId('server-id::Sala::de::Voz'),
      'server-id',
    );
  });

  test('returns null when a room id has no server separator', () {
    expect(serverIdFromVoiceRoomId('invalid-room-id'), isNull);
  });
}
