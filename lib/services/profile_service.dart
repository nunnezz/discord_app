import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'supabase_client.dart';

// =========================================================================
// PROFILE SERVICE
// =========================================================================
class ProfileService {
  /// Busca o perfil de UM usuário pelo id.
  static Future<Profile> fetchProfile(String userId) async {
    final row =
        await supabase.from('profiles').select().eq('id', userId).single();
    return Profile.fromMap(row);
  }

  /// Stream em tempo real do MEU PRÓPRIO perfil — útil para refletir na
  /// hora qualquer edição feita (inclusive de outro dispositivo logado).
  static Stream<Profile> watchMyProfile(String userId) {
    return supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((rows) => Profile.fromMap(rows.first));
  }

  /// Salva as alterações feitas na tela "Editar perfil".
  static Future<void> updateProfile(Profile profile) async {
    await supabase
        .from('profiles')
        .update(profile.toUpdateMap())
        .eq('id', profile.id);
  }

  /// Envia uma nova foto de avatar para o Supabase Storage (bucket
  /// `avatars`, que você precisa criar como público no painel:
  /// Storage → New bucket → nome "avatars" → Public bucket = ON)
  /// e retorna a URL pública para salvar em `avatar_url`.
  static Future<String> uploadAvatar(String userId, XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final fileExt = imageFile.name.split('.').last;
    final filePath = '$userId/avatar.$fileExt';

    await supabase.storage.from('avatars').uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    return supabase.storage.from('avatars').getPublicUrl(filePath);
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