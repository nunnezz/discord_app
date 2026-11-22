import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'services/realtime_lifecycle_service.dart';
import 'services/supabase_client.dart';
import 'services/auth_service.dart';
import 'auth/auth_screen.dart';
import 'screens/cord_home_page.dart';

Future<void> main() async {
  // Necessário sempre que você faz algo assíncrono ANTES do runApp.
  WidgetsFlutterBinding.ensureInitialized();

  await AppConfig.load();
  await initSupabase();

  // Liga o gerenciamento inteligente de conexões Realtime: libera vagas
  // do limite de 200 conexões do plano free desconectando usuários com
  // aba oculta >30s ou inativos >5min (ver realtime_lifecycle_service).
  RealtimeLifecycleService.instance.init();

  runApp(const CordApp());
}

class CordApp extends StatelessWidget {
  const CordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cord',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
        // Tipografia moderna (Inter quando disponível no dispositivo,
        // fallback da plataforma caso contrário) e hierarquia limpa.
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // deep indigo
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xCCFFFFFF),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Color(0xFF0F172A),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// =========================================================================
// AUTH GATE
// Agora escuta `AuthService.onAuthStateChange` (que vem do Supabase) em
// vez de guardar um `String? loggedInUsername` manualmente. Isso também
// resolve de graça um problema que o mapa local nunca resolveu: se o
// usuário fechar e reabrir o app, a SESSÃO PERSISTE (o Supabase guarda
// o token localmente) e ele cai direto na tela principal, sem precisar
// logar de novo.
// =========================================================================
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.onAuthStateChange,
      builder: (context, snapshot) {
        // Enquanto o Supabase ainda não confirmou se há sessão salva.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1E1F22),
            body: Center(
                child: CircularProgressIndicator(color: Color(0xFF5865F2))),
          );
        }

        final session = supabase.auth.currentSession;

        if (session == null) {
          return const AuthScreen();
        }

        // Sessão ativa: entra direto na tela principal do Cord, com o
        // id do usuário logado — é a partir dele que a CordHomePage
        // busca o perfil (ProfileService) e filtra/envia mensagens
        // (ChatService) no Supabase.
        return CordHomePage(userId: session.user.id);
      },
    );
  }
}
