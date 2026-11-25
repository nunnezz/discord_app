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

  try {
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
  } catch (e) {
    // Sem este fallback, qualquer falha na inicialização (ex: .env
    // ausente/corrompido, Supabase inacessível) deixava o app preso na
    // splash preta, sem desenhar NADA. Agora o usuário vê o motivo.
    runApp(_BootErrorApp(error: e));
  }
}

/// Tela de erro de inicialização — mostra o motivo em vez de tela preta.
class _BootErrorApp extends StatelessWidget {
  final Object error;
  const _BootErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFE11D48), size: 48),
                const SizedBox(height: 16),
                const Text('Erro ao iniciar',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                Text('$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF64748B), fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
        // AFK multiplataforma: no mobile, sem eventos de mouse/teclado
        // nativos, registramos cada toque/arrasto; no desktop, hover,
        // rolagem (PointerSignal) e teclado (KeyEvent) também reiniciam o
        // contador. No web, quem faz isso são os listeners de dart:html
        // em web_activity_web.dart (o Listener abaixo é inofensivo lá).
        builder: (context, child) => Focus(
          // NÃO rouba o foco de campos de texto: skipTraversal evita que
          // o Focus entre na navegação por Tab, e canRequestFocus:false
          // garante que ele nunca demande o foco para si.
          skipTraversal: true,
          canRequestFocus: false,
          descendantsAreFocusable: true,
          onKeyEvent: (_, __) {
            RealtimeLifecycleService.instance.markActivity();
            return KeyEventResult.ignored; // propaga a tecla normalmente
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) =>
                RealtimeLifecycleService.instance.markActivity(),
            onPointerMove: (_) =>
                RealtimeLifecycleService.instance.markActivity(),
            // Desktop: mouse parado MAS mexendo (hover) e rolagem.
            onPointerHover: (_) =>
                RealtimeLifecycleService.instance.markActivity(),
            onPointerSignal: (_) =>
                RealtimeLifecycleService.instance.markActivity(),
            child: child,
          ),
        ),
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
