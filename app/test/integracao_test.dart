// Teste de integração da camada de estado do app contra as agências REAIS.
//
// Pré-requisito: as 3 agências no ar (agencia/dev-agencias.sh start).
//   cd app && flutter test test/integracao_test.dart
//
// Não usa widgets: exercita o EstadoApp (controller do app) exatamente como as
// telas o usam. Se as agências não estiverem no ar, os testes são pulados.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iceibank_app/servicos/api.dart';
import 'package:iceibank_app/servicos/estado_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<EstadoApp> novoEstado() async {
  SharedPreferences.setMockInitialValues({});
  final estado = await EstadoApp.iniciar();
  await estado.definirHost('localhost');
  return estado;
}

void main() {
  late bool noAr;
  // Contas novas a cada execução (as agências guardam contas em memória).
  final base = 3000 + Random().nextInt(3000) * 3; // múltiplo de 3 -> agência 0

  setUpAll(() async {
    noAr = await Api(host: 'localhost').algumaAgenciaNoAr();
  });

  test('fluxo bancario: login, criar conta, deposito, saque, transferencia', () async {
    if (!noAr) return markTestSkipped('agencias fora do ar');
    final estado = await novoEstado();
    await estado.entrar('lara', 'iceibank');
    expect(estado.logado, isTrue);

    await estado.criarConta(base, 'Ana', 100);
    await estado.criarConta(base + 1, 'Bia', 0); // agência 1
    await estado.depositar(base, 50);
    await estado.sacar(base, 30);
    expect(estado.saldoExibido(base), 120);

    await expectLater(estado.sacar(base, 1000), throwsA(isA<ErroApi>()));

    final msg = await estado.transferir(base, base + 1, 20);
    expect(msg, contains('assincrona'));
    expect(estado.saldoExibido(base), 100);
    await Future<void>.delayed(const Duration(seconds: 2));
    await estado.abrirConta(base + 1);
    expect(estado.saldoExibido(base + 1), 20);
  });
}
