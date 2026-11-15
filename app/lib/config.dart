import 'package:flutter/foundation.dart';

/// Configuração fixa do cluster - espelha `agencia/src/config.py`.
class ConfigApp {
  static const int numeroAgencias = 3;
  static const int portaBase = 4000;

  /// Emulador Android enxerga a máquina host como 10.0.2.2; web, iOS
  /// (simulador) e macOS usam localhost. Pode ser trocado na tela de
  /// configurações (ex.: IP da máquina na rede, para um celular físico).
  static String hostPadrao() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return 'localhost';
  }

  /// Mesma regra do backend: a agência dona da conta é `id % 3`.
  static int agenciaDaConta(int idConta) => idConta % numeroAgencias;

  /// Intervalos do app.
  static const Duration timeoutRequisicao = Duration(seconds: 3);
  static const Duration timeoutLider = Duration(milliseconds: 1500);
  static const Duration intervaloPainelLider = Duration(seconds: 2);
  static const Duration intervaloTentativaSync = Duration(seconds: 4);
}
