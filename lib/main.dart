import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'services/realtime_lifecycle_service.dart';
import 'services/supabase_client.dart';
import 'services/auth_service.dart';
import 'auth/auth_screen.dart';
import 'screens/cord_home_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Necessário sempre que você faz algo assíncrono ANTES do runApp.
  WidgetsFlutterBinding.ensureInitialized();

  await AppConfig.load();
  await initSupabase();

  // Carrega o tema salvo ANTES do runApp — evita flash do tema claro
  // quando o usuário escolheu o escuro na sessão anterior.
  await AppTheme.load();

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
    // O modo escuro é CONTROLADO GLOBALMENTE pelo switch em Configurações
    // (AppTheme.darkMode). Este ValueListenableBuilder reconstrói o
    // MaterialApp quando o usuário liga/desliga — e o darkTheme abaixo é
    // o mesmo design system (indigo/neutros) em Brightness.dark.
    return ValueListenableBuilder<bool>(
      valueListenable: AppTheme.darkMode,
      builder: (context, isDark, _) => MaterialApp(
        title: 'Cord',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          useMaterial3: true,
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
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B0F1A),
          useMaterial3: true,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF818CF8), // indigo claro no escuro
            brightness: Brightness.dark,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.white.withOpacity(0.06),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            foregroundColor: const Color(0xFFE2E8F0),
          ),
        ),
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: const AuthGate(),
      ),
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
