import 'dart:async';

import 'package:flutter/widgets.dart';

import 'supabase_client.dart';
import 'web_activity_stub.dart'
    if (dart.library.html) 'web_activity_web.dart';

/// ===========================================================================
/// GERENCIAMENTO INTELIGENTE DE CONEXÕES REALTIME
/// ===========================================================================
/// O plano gratuito do Supabase tem LIMITE DE 200 CONEXÕES SIMULTÂNEAS de
/// Realtime. Um websocket fica aberto por usuário conectado, mesmo que ele
/// tenha minimizado a aba ou saído pra almoçar — desperdiçando vagas.
///
/// Este serviço aplica 3 regras para liberar vagas sem perder mensagens:
///
/// 1. ABA OCULTA: aba minimizada/trocada por > 30s → desconecta o cliente
///    Realtime inteiro (`supabase.removeChannel` em todos os canais + socket
///    fechado). Ao voltar → reconecta e refetch das mensagens perdidas.
/// 2. INATIVIDADE (AFK): sem interação (mouse/teclado/touch/scroll) por
///    5 min → desconecta, igual à aba oculta. Qualquer interação reconecta.
/// 3. SINCRONIZAÇÃO: na reconexão, emite um evento global (`onReconnect`)
///    que as telas de chat escutam para refetch das mensagens a partir do
///    timestamp da última mensagem renderizada — nada se perde, nada duplica.
///
/// IMPORTANTE: usamos `dart:html` (não `dart:js_interop`) porque o projeto
/// ainda compila com as bibliotecas JS legadas; funciona no Flutter web ≥3.x.
/// No mobile nativo não existe `visibilitychange` — lá o lifecycle do
/// Flutter (AppLifecycleState) cumpre o mesmo papel, já integrado abaixo.
class RealtimeLifecycleService with WidgetsBindingObserver {
  RealtimeLifecycleService._();
  static final RealtimeLifecycleService instance = RealtimeLifecycleService._();

  /// ABA OCULTA: tempo máximo escondido antes de desconectar.
  static const _hiddenDisconnectAfter = Duration(seconds: 30);

  /// AFK: tempo sem interação antes de desconectar.
  static const _afkDisconnectAfter = Duration(minutes: 5);

  /// Reconecta no máximo a cada 5s (evita flap em abas que piscam).
  static const _minReconnectInterval = Duration(seconds: 5);

  bool _initialized = false;
  bool _disposed = false;

  // --- estado interno ---
  DateTime? _hiddenAt; // quando a aba ficou oculta
  DateTime _lastInteraction = DateTime.now();
  Timer? _tickTimer; // verificador periódico único
  DateTime _lastDisconnectAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disconnected = false;
  WebActivityHooks? _webHooks;

  /// Chamado SEMPRE que o serviço reconecta o Realtime (volta de aba
  /// oculta ou de AFK). As telas de chat escutam isto para refetch.
  final StreamController<void> _onReconnectController =
      StreamController<void>.broadcast();
  Stream<void> get onReconnect => _onReconnectController.stream;

  /// True se o Realtime está atualmente desconectado por economia.
  bool get isDisconnected => _disconnected;

  void init() {
    if (_initialized || _disposed) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);

    _webHooks = WebActivityHooks(
      onHidden: () => _hiddenAt = DateTime.now(),
      onVisible: () {
        if (_hiddenAt != null &&
            DateTime.now().difference(_hiddenAt!) > _hiddenDisconnectAfter) {
          _reconnect('aba voltou ao foco');
        }
        _hiddenAt = null;
      },
      onActivity: markActivity,
    )..attach();

    // ---- verificador periódico (1x por segundo, bem barato) ----
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Registra interação do usuário (reinicia o contador de AFK).
  void markActivity() => _lastInteraction = DateTime.now();

  void _tick() {
    if (_disposed || _disconnected) return;
    final now = DateTime.now();

    // AFK?
    if (now.difference(_lastInteraction) >= _afkDisconnectAfter) {
      _disconnect('inatividade de ${_afkDisconnectAfter.inMinutes} min');
      return;
    }

    // Aba oculta há mais de 30s?
    if (_hiddenAt != null &&
        now.difference(_hiddenAt!) >= _hiddenDisconnectAfter) {
      _disconnect('aba oculta por >30s');
    }
  }

  // =========================================================================
  // DESCONECTAR / RECONECTAR
  // =========================================================================
  void _disconnect(String reason) {
    if (_disposed || _disconnected) return;
    _disconnected = true;
    _lastDisconnectAt = DateTime.now();
    debugPrint('[RealtimeLifecycle] Desconectando ($reason) — liberando vaga.');
    try {
      // Remove TODOS os canais ativos — cada removeChannel encerra a
      // inscrição do websocket daquele canal no servidor. É isso que
      // libera a vaga no limite de 200 conexões.
      for (final channel in supabase.getChannels()) {
        unawaited(supabase.removeChannel(channel));
      }
    } catch (e) {
      debugPrint('[RealtimeLifecycle] Erro ao desconectar: $e');
    }
  }

  void _reconnect(String reason) {
    if (!_disconnected) return; // nunca desconectou — nada a fazer
    final now = DateTime.now();
    if (now.difference(_lastDisconnectAt) < _minReconnectInterval) return;
    _lastDisconnectAt = now;
    debugPrint('[RealtimeLifecycle] Reconectando ($reason).');

    // NÃO religamos o socket manualmente: as telas de chat escutam o
    // evento abaixo e RECRIAM suas streams — o supabase_flutter abre o
    // canal novo (e o websocket, se preciso) por conta própria, sem
    // depender de APIs @internal do realtime_client.
    _disconnected = false;
    _lastInteraction = DateTime.now();
    _hiddenAt = null;
    // Notifica as telas: refetch das mensagens perdidas (regra 3).
    _onReconnectController.add(null);
  }

  // =========================================================================
  // LIFECYCLE DO APP (mobile nativo: background/foreground)
  // =========================================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _hiddenAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_hiddenAt != null &&
          DateTime.now().difference(_hiddenAt!) > _hiddenDisconnectAfter) {
        _reconnect('app voltou ao primeiro plano');
      }
      _hiddenAt = null;
      _lastInteraction = DateTime.now();
    }
  }

  /// Chame no dispose() da raiz do app. (O singleton vive o app todo; na
  /// prática isto só importa em testes.)
  void dispose() {
    _disposed = true;
    _tickTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _webHooks?.detach();
    _onReconnectController.close();
    _initialized = false;
  }
}
