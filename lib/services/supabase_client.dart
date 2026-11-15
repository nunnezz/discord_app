import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

// =========================================================================
// CREDENCIAIS DO SUPABASE
// =========================================================================
// As chaves do Supabase são lidas de .env para evitar espalhar
// informações sensíveis em código. O único valor que pode ficar no
// repositório é a URL pública do projeto e a anon key pública, mas o
// ideal é manter tudo em variáveis de ambiente.

/// Chame isso uma única vez, no início do `main()`.
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
}

/// Atalho usado em todo o app para acessar o cliente já inicializado.
SupabaseClient get supabase => Supabase.instance.client;

/// Atalho para o usuário autenticado atual (nulo se deslogado).
User? get currentAuthUser => supabase.auth.currentUser;