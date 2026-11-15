// Teste de integração da camada de estado do app contra as agências REAIS.
//
// Pré-requisito: as 3 agências no ar (agencia/dev-agencias.sh start).
//   cd app && flutter test test/integracao_test.dart
//
// Não usa widgets: exercita o EstadoApp (controller do app) exatamente como as
// telas o usam. Se as agências não estiverem no ar, os testes são pulados.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iceibank_app/modelos.dart';
import 'package:iceibank_app/servicos/api.dart';
import 'package:iceibank_app/servicos/estado_app.dart';
import 'package:iceibank_app/servicos/monitor_lideranca.dart';
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

  test('painel de lideranca acompanha um failover real', () async {
    if (!noAr) return markTestSkipped('agencias fora do ar');
    final script = Platform.environment['DEV_AGENCIAS'] ??
        '${Directory.current.parent.path}/agencia/dev-agencias.sh';
    final monitor = MonitorLideranca(Api(host: 'localhost'));
    await monitor.consultar();
    expect(monitor.situacao, SituacaoCluster.estavel);
    final liderInicial = monitor.lider!;

    // Derruba a líder de verdade e espera o cluster convergir para outra.
    await Process.run(script, ['stop', '$liderInicial']);
    final situacoes = <SituacaoCluster>{};
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await monitor.consultar();
      situacoes.add(monitor.situacao);
      if (monitor.situacao == SituacaoCluster.estavel && monitor.lider != liderInicial) break;
    }
    expect(monitor.lider, isNot(liderInicial));
    expect(situacoes, contains(SituacaoCluster.liderSemResposta));
    expect(monitor.eventos.map((e) => e.texto), contains(startsWith('FAILOVER')));

    // Religa: a de ID maior retoma a liderança (bully).
    await Process.run(script, ['start']);
    for (var i = 0; i < 20 && monitor.lider != liderInicial; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await monitor.consultar();
    }
    expect(monitor.lider, liderInicial);
    for (final e in monitor.eventos.reversed) {
      // ignore: avoid_print
      print('${formatarHora(e.quando)}  ${e.texto}');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('offline-first: fila, saldo otimista e sincronizacao em ordem ao reconectar', () async {
    if (!noAr) return markTestSkipped('agencias fora do ar');
    final estado = await novoEstado();
    await estado.entrar('lara', 'iceibank');
    final id = base + 3;
    await estado.criarConta(id, 'Caio', 100);

    await estado.definirOfflineSimulado(true);
    expect(estado.online, isFalse);
    expect(await estado.depositar(id, 50), contains('salvo no aparelho'));
    await estado.sacar(id, 30);
    expect(estado.fila, hasLength(2));
    expect(estado.saldoExibido(id), 120); // UI otimista
    expect(estado.contas[id]!.saldoServidor, 100);
    // saque maior que o saldo otimista é barrado ainda offline
    await expectLater(estado.sacar(id, 500), throwsA(isA<ErroApi>()));

    await estado.definirOfflineSimulado(false); // reconecta -> sincroniza
    expect(estado.fila, isEmpty);
    expect(estado.contas[id]!.saldoServidor, 120);
    expect(estado.historico.take(2).map((r) => r.resultado), everyElement('APLICADA'));
  });

  test('offline-first: conflito 409 visivel, rollback otimista e reaplicacao', () async {
    if (!noAr) return markTestSkipped('agencias fora do ar');
    final estado = await novoEstado();
    await estado.entrar('lara', 'iceibank');
    final id = base + 6;
    await estado.criarConta(id, 'Duda', 100);

    await estado.definirOfflineSimulado(true);
    await estado.sacar(id, 30);
    await estado.depositar(id, 5);

    // Enquanto o app está offline, outro cliente (ex.: o frontend web) mexe na conta.
    final outro = Api(host: 'localhost')..token = estado.api.token;
    await outro.depositar(id, 10);

    await estado.definirOfflineSimulado(false);
    final saque = estado.fila.first;
    expect(saque.status, StatusOperacao.conflito);
    expect(saque.conflito!['relacao'], 'ANTES');
    expect(saque.conflito!['escritasConcorrentes'], isNotEmpty);
    expect(estado.fila[1].status, StatusOperacao.pendente); // bloqueada atrás do conflito
    expect(estado.contas[id]!.saldoServidor, 110); // cache atualizado com o servidor
    expect(estado.saldoExibido(id), 115); // o saque em conflito saiu do saldo (rollback)

    await estado.resolverConflito(saque, reaplicar: true);
    expect(estado.fila, isEmpty);
    expect(estado.contas[id]!.saldoServidor, 85);
  });

  test('funcionalidade adicional: deposito offline concorrente e mesclado', () async {
    if (!noAr) return markTestSkipped('agencias fora do ar');
    final estado = await novoEstado();
    await estado.entrar('lara', 'iceibank');
    final id = base + 9;
    await estado.criarConta(id, 'Edu', 100);

    await estado.definirOfflineSimulado(true);
    await estado.depositar(id, 20);
    final outro = Api(host: 'localhost')..token = estado.api.token;
    await outro.sacar(id, 10);

    await estado.definirOfflineSimulado(false);
    expect(estado.fila, isEmpty);
    expect(estado.historico.first.resultado, 'MESCLADA');
    expect(estado.contas[id]!.saldoServidor, 110);
  });
}
