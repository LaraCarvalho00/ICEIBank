import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../modelos.dart';
import 'api.dart';

enum TipoEventoLider { info, alerta, failover, retomada }

class EventoLider {
  EventoLider(this.quando, this.texto, this.tipo);
  final DateTime quando;
  final String texto;
  final TipoEventoLider tipo;
}

/// Situação do cluster vista pelo app.
enum SituacaoCluster {
  /// Todas as agências no ar concordam e a líder responde.
  estavel,

  /// A líder reconhecida pelas outras não responde (antes do heartbeat delas
  /// perceber) - a fase "invisível" do failover.
  liderSemResposta,

  /// Eleição em andamento ou agências discordando de quem é a líder.
  emEleicao,

  /// Nenhuma agência responde.
  foraDoAr,
}

/// Painel de liderança: consulta `GET /bully/lider` das 3 agências a cada
/// 2 s, em paralelo, e deduz quem é a líder e em que fase do failover o
/// cluster está. Guarda um histórico de transições para a tela.
class MonitorLideranca extends ChangeNotifier {
  MonitorLideranca(this._api);

  final Api _api;
  Timer? _timer;
  bool _consultando = false;

  List<EstadoAgencia?> estados = List.filled(ConfigApp.numeroAgencias, null);
  int? lider;
  SituacaoCluster situacao = SituacaoCluster.foraDoAr;
  DateTime? ultimaConsulta;
  final List<EventoLider> eventos = [];

  /// Líder que as agências vivas reconhecem (mesmo que ela não responda).
  int? liderReconhecido;

  bool _primeira = true;

  void iniciar() {
    _timer ??= Timer.periodic(ConfigApp.intervaloPainelLider, (_) => consultar());
    consultar();
  }

  void parar() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    parar();
    super.dispose();
  }

  Future<void> consultar() async {
    if (_consultando) return;
    _consultando = true;
    try {
      final novos = await Future.wait(
        List.generate(ConfigApp.numeroAgencias, _api.consultarLider),
      );
      _registrarTransicoesDeAgencia(novos);
      estados = novos;
      ultimaConsulta = DateTime.now();
      _recalcular();
      _primeira = false;
      notifyListeners();
    } finally {
      _consultando = false;
    }
  }

  void _registrarTransicoesDeAgencia(List<EstadoAgencia?> novos) {
    if (_primeira) return;
    for (var i = 0; i < novos.length; i++) {
      final antes = estados[i] != null;
      final agora = novos[i] != null;
      if (antes && !agora) {
        _evento('Agencia $i parou de responder', TipoEventoLider.alerta);
      } else if (!antes && agora) {
        _evento('Agencia $i voltou a responder', TipoEventoLider.info);
      }
    }
  }

  void _recalcular() {
    final vivas = estados.whereType<EstadoAgencia>().toList();
    final anterior = lider;

    if (vivas.isEmpty) {
      situacao = SituacaoCluster.foraDoAr;
      lider = null;
      liderReconhecido = null;
    } else {
      final reconhecidos = vivas.map((e) => e.liderAtual).toSet();
      final algumaEmEleicao = vivas.any((e) => e.emEleicao);
      if (reconhecidos.length == 1 && reconhecidos.first != null && !algumaEmEleicao) {
        liderReconhecido = reconhecidos.first;
        if (estados[liderReconhecido!] != null) {
          situacao = SituacaoCluster.estavel;
          lider = liderReconhecido;
        } else {
          situacao = SituacaoCluster.liderSemResposta;
          lider = null;
        }
      } else {
        situacao = SituacaoCluster.emEleicao;
        lider = null;
        liderReconhecido = null;
      }
    }

    if (lider != null && lider != _ultimaLiderEstavel) {
      final antiga = _ultimaLiderEstavel;
      if (_primeira || antiga == null && eventos.isEmpty) {
        _evento('Lider atual: Agencia $lider', TipoEventoLider.info);
      } else if (antiga != null && lider! > antiga) {
        _evento('Agencia $lider (ID maior) assumiu a lideranca no lugar da $antiga',
            TipoEventoLider.retomada);
      } else {
        _evento(
          antiga == null
              ? 'Nova lider eleita: Agencia $lider'
              : 'FAILOVER: Agencia $antiga -> Agencia $lider',
          TipoEventoLider.failover,
        );
      }
      _ultimaLiderEstavel = lider;
    } else if (anterior != null && lider == null) {
      _evento(
        situacao == SituacaoCluster.liderSemResposta
            ? 'Lider $anterior nao responde - aguardando o heartbeat das outras agencias'
            : 'Eleicao em andamento',
        TipoEventoLider.alerta,
      );
    }
  }

  int? _ultimaLiderEstavel;

  void _evento(String texto, TipoEventoLider tipo) {
    eventos.insert(0, EventoLider(DateTime.now(), texto, tipo));
    if (eventos.length > 40) eventos.removeLast();
  }
}
