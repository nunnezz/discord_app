import 'package:cord_app/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const serverData = {
    'id': 'server-id',
    'name': 'Cord Test',
    'icon_text': 'C',
    'owner_id': 'owner-id',
  };

  test('existing server records default to private', () {
    final server = ServerModel.fromMap(serverData);

    expect(server.isPublic, isFalse);
  });

  test('reads public visibility from the server record', () {
    final server = ServerModel.fromMap({
      ...serverData,
      'is_public': true,
    });

    expect(server.isPublic, isTrue);
  });
}
