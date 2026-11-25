import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centraliza a leitura de configuração do app.
///
/// - Web: os valores vêm de `--dart-define` (String.fromEnvironment).
/// - Mobile: os valores vêm do arquivo `.env` (flutter_dotenv), com os
///   mesmos defaults públicos usados na web como fallback.
class AppConfig {
  /// Controla se o dotenv carregou com sucesso — os getters usam isto
  /// para não estourar NotInitializedError quando o .env está ausente
  /// (era o que travava o app Android na splash).
  static bool _dotenvReady = false;

  static Future<void> load() async {
    // Carrega o .env em TODAS as plataformas (é um asset embutido no
    // build, não precisa de --dart-define). O fallback para
    // String.fromEnvironment fica nos getters.
    try {
      await dotenv.load(fileName: '.env');
      _dotenvReady = true;
    } catch (e) {
      _dotenvReady = false;
      debugPrint('[AppConfig] .env não carregado: $e — '
          'seguindo com os valores padrão.');
    }
  }

  static const _defaultSupabaseUrl = 'https://hcwetkdnxqeveyyurawm.supabase.co';
  static const _defaultSupabaseAnonKey =
      'sb_publishable_l9ux4cEv39cv3MLWfKWjPQ_15KwOEKv';

  /// Lê uma variável do dotenv APENAS se ele foi inicializado; caso
  /// contrário devolve null (evita NotInitializedError).
  static String? _fromEnv(String key) {
    if (!_dotenvReady) return null;
    try {
      final value = dotenv.env[key];
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }

  static String get supabaseUrl => kIsWeb
      ? const String.fromEnvironment(
          'SUPABASE_URL',
          defaultValue: _defaultSupabaseUrl,
        )
      : (_fromEnv('SUPABASE_URL') ?? _defaultSupabaseUrl);

  static String get supabaseAnonKey => kIsWeb
      ? const String.fromEnvironment(
          'SUPABASE_ANON_KEY',
          defaultValue: _defaultSupabaseAnonKey,
        )
      : (_fromEnv('SUPABASE_ANON_KEY') ?? _defaultSupabaseAnonKey);

  static String get agoraAppId {
    // Lê do .env em TODAS as plataformas (web incluída — dotenv é asset,
    // não precisa de --dart-define); fallback para --dart-define.
    final fromDotenv = _fromEnv('AGORA_APP_ID')?.trim() ?? '';
    if (fromDotenv.isNotEmpty) return fromDotenv;
    return const String.fromEnvironment('AGORA_APP_ID');
  }

  static String get agoraAppCertificate =>
      _fromEnv('AGORA_APP_CERTIFICATE')?.trim() ?? '';
}
