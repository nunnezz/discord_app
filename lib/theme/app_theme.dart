
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// =========================================================================
/// CONTROLADOR DE TEMA GLOBAL — PERSISTENTE
/// =========================================================================
/// Singleton com um ValueNotifier<bool> observável. O `main.dart` escuta
/// este notifier para trocar o `themeMode` do MaterialApp, e qualquer tela
/// pode ler `AppTheme.isDark` para adaptar suas cores customizadas.
///
/// A escolha do usuário é SALVA no localStorage (web) / SharedPreferences
/// (mobile): recarregar a página, fechar o navegador ou reabrir o app
/// mantém o tema escolhido — só muda quando o usuário trocar de novo.
class AppTheme {
  AppTheme._();
  static final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);
  static const String _prefsKey = 'cord_theme_dark';
  static bool _loaded = false;

  static bool get isDark => darkMode.value;
  static set isDark(bool v) => darkMode.value = v;

  /// Carrega o tema salvo (chame UMA vez no main, antes do runApp).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      darkMode.value = prefs.getBool(_prefsKey) ?? false;
      _loaded = true;
    } catch (_) {
      _loaded = false; // falhou? segue com claro (fallback seguro)
    }
  }

  /// Define o tema E salva para as próximas sessões.
  static Future<void> setDark(bool value) async {
    darkMode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // Sem persistência disponível (raro): o tema funciona só nesta sessão.
    }
  }
}
