import 'package:flutter/material.dart';

/// =========================================================================
/// CONTROLADOR DE TEMA GLOBAL
/// =========================================================================
/// Singleton com um ValueNotifier<bool> observável. O `main.dart` escuta
/// este notifier para trocar o `themeMode` do MaterialApp, e qualquer tela
/// pode ler `AppTheme.isDark.value` (ou ouvir a stream) para adaptar suas
/// cores customizadas.
class AppTheme {
  AppTheme._();
  static final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);

  static bool get isDark => darkMode.value;
  static set isDark(bool v) => darkMode.value = v;
}
