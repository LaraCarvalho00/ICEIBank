import 'package:material_ui/material_ui.dart';

/// Mesma paleta do frontend web (tema escuro "app de investimento").
class Cores {
  static const fundo = Color(0xFF0B0F16);
  static const elevado = Color(0xFF141A24);
  static const linha = Color(0xFF222C3A);
  static const texto = Color(0xFFE7EEF8);
  static const textoSuave = Color(0xFF93A1B5);
  static const textoFraco = Color(0xFF5F6D81);
  static const destaque = Color(0xFF00C896);
  static const erro = Color(0xFFFF6B6B);
  static const alerta = Color(0xFFFFB454);
  static const info = Color(0xFF6BA8FF);
}

ThemeData temaIceibank() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Cores.destaque,
    brightness: Brightness.dark,
    primary: Cores.destaque,
    error: Cores.erro,
    surface: Cores.elevado,
  );
  return ThemeData(
    colorScheme: esquema,
    scaffoldBackgroundColor: Cores.fundo,
    appBarTheme: const AppBarTheme(backgroundColor: Cores.fundo, elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: Cores.elevado,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Cores.linha),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Cores.elevado),
  );
}
