import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static Future<void> load() async {
    if (kIsWeb) return;

    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Arquivo .env opcional: o app pode continuar usando valores
      // padrão para o Supabase público e o usuário preenche o resto
      // manualmente quando for necessário.
    }
  }

  static const _defaultSupabaseUrl =
      'https://hcwetkdnxqeveyyurawm.supabase.co';
  static const _defaultSupabaseAnonKey =
      'sb_publishable_l9ux4cEv39cv3MLWfKWjPQ_15KwOEKv';

  static String get supabaseUrl => kIsWeb
      ? const String.fromEnvironment(
          'SUPABASE_URL',
          defaultValue: _defaultSupabaseUrl,
        )
      : dotenv.env['SUPABASE_URL'] ?? _defaultSupabaseUrl;

  static String get supabaseAnonKey => kIsWeb
      ? const String.fromEnvironment(
          'SUPABASE_ANON_KEY',
          defaultValue: _defaultSupabaseAnonKey,
        )
      : dotenv.env['SUPABASE_ANON_KEY'] ?? _defaultSupabaseAnonKey;

  static String get agoraAppId => kIsWeb
      ? const String.fromEnvironment('AGORA_APP_ID')
      : dotenv.env['AGORA_APP_ID'] ?? '';

  static String get agoraAppCertificate =>
      kIsWeb ? '' : dotenv.env['AGORA_APP_CERTIFICATE'] ?? '';
}
