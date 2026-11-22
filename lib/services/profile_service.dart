import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'supabase_client.dart';

// =========================================================================
// PROFILE SERVICE
// =========================================================================
class ProfileService {
  static const _avatarMimeTypesByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };
  static const _maxAvatarSizeBytes = 5 * 1024 * 1024;

  /// Busca o perfil de UM usuário pelo id.
  static Future<Profile> fetchProfile(String userId) async {
    final row =
        await supabase.from('profiles').select().eq('id', userId).single();
    return Profile.fromMap(row);
  }

  /// Stream em tempo real do MEU PRÓPRIO perfil — útil para refletir na
  /// hora qualquer edição feita (inclusive de outro dispositivo logado).
  ///
  /// A stream do Supabase pode chegar VAZIA em alguns momentos (snapshot
  /// inicial do realtime, ou flutuação de RLS) — se aplicarmos `rows.first`
  /// direto, isso vira um erro no StreamBuilder e o rodapé do usuário fica
  /// eternamente no "...". Por isso: busca o perfil por HTTP como fallback
  /// quando a stream não traz linha, e ignora eventos vazios enquanto
  /// já temos dados.
  static Stream<Profile> watchMyProfile(String userId) async* {
    Profile? lastKnown;
    // Primeiro dado imediato (HTTP), para a UI nunca começar vazia.
    try {
      lastKnown = await fetchProfile(userId);
      yield lastKnown;
    } catch (_) {
      // Segue sem dado inicial — a stream abaixo pode trazer depois.
    }
    await for (final rows
        in supabase.from('profiles').stream(primaryKey: ['id']).eq('id', userId)) {
      if (rows.isEmpty) {
        if (lastKnown != null) yield lastKnown; // mantém o último conhecido
        continue;
      }
      try {
        lastKnown = Profile.fromMap(rows.first);
        yield lastKnown;
      } catch (_) {
        // Linha malformada — mantém o último conhecido.
        if (lastKnown != null) yield lastKnown;
      }
    }
  }

  /// Salva as alterações feitas na tela "Editar perfil".
  static Future<void> updateProfile(Profile profile) async {
    await supabase
        .from('profiles')
        .update(profile.toUpdateMap())
        .eq('id', profile.id);
  }

  /// Envia uma foto para o bucket público `avatars` e retorna sua URL.
  static Future<String> uploadAvatar(String userId, XFile imageFile) async {
    final extension = imageFile.name.contains('.')
        ? imageFile.name.split('.').last.toLowerCase()
        : '';
    final mimeType = _avatarMimeTypesByExtension[extension] ??
        imageFile.mimeType?.toLowerCase();
    if (mimeType == null ||
        !_avatarMimeTypesByExtension.values.contains(mimeType)) {
      throw const FormatException('Escolha uma foto JPG, PNG ou WEBP.');
    }

    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('A imagem selecionada está vazia.');
    }
    if (bytes.length > _maxAvatarSizeBytes) {
      throw const FormatException('A foto deve ter no máximo 5 MB.');
    }

    const bucket = 'avatars';
    final filePath = '$userId/avatar';
    await supabase.storage.from(bucket).uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: mimeType,
          ),
        );

    final publicUrl = supabase.storage.from(bucket).getPublicUrl(filePath);
    return '$publicUrl?v=${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Usado na tela de busca de amigos: procura por nome de usuário exato
  /// ou parcial (case-insensitive). Retorna `null` se não encontrar.
  static Future<Profile?> searchByUsername(String username) async {
    final normalized = username.trim().toLowerCase().replaceAll('@', '');
    if (normalized.isEmpty) return null;

    final rows = await supabase
        .from('profiles')
        .select()
        .ilike('username', normalized)
        .limit(1);

    if (rows.isEmpty) return null;
    return Profile.fromMap(rows.first);
  }
}