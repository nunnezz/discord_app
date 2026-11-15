import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Arquivo .env opcional: o app pode continuar usando valores
      // padrão para o Supabase público e o usuário preenche o resto
      // manualmente quando for necessário.
    }
  }

  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? 'https://hcwetkdnxqeveyyurawm.supabase.co';

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ??
      'sb_publishable_l9ux4cEv39cv3MLWfKWjPQ_15KwOEKv';

  static String get agoraAppId => dotenv.env['AGORA_APP_ID'] ?? '';

  static String get agoraAppCertificate =>
      dotenv.env['AGORA_APP_CERTIFICATE'] ?? '';
}
