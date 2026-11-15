import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../modelos.dart';
import 'api.dart';
import 'armazenamento.dart';

enum TipoAviso { sucesso, alerta, erro }

class Aviso {
  Aviso(this.texto, this.tipo);
  final String texto;
  final TipoAviso tipo;
}

/// Estado central do app (CONTROLLER no MVC do app): as telas só leem daqui e
/// chamam métodos daqui; quem fala com a API e com o armazenamento local é
/// este objeto.
///
/// Offline-first (Parte F):
/// - **armazenamento local**: contas (último estado confirmado), fila de
///   operações pendentes e histórico de sincronização sobrevivem ao app ser
///   fechado (`Armazenamento`);
/// - **fila de pendentes**: depósito/saque sem conexão vira uma
///   [OperacaoPendente] com o `vetorBase` = versão da conta em cache;
/// - **UI otimista**: o saldo exibido já inclui as pendentes; se uma delas
///   entrar em conflito ou for rejeitada, o efeito dela sai do saldo (rollback);
/// - **sincronização automática**: ao reconectar (connectivity_plus + uma
///   tentativa a cada 4 s), a fila é enviada em ordem para `/sync/operacoes`;
/// - **conflito (409)**: a operação fica marcada como conflito, com o estado do
///   servidor, até o usuário decidir reaplicar ou descartar.
class EstadoApp extends ChangeNotifier {
  EstadoApp._(this._armazenamento, this.api);

  static Future<EstadoApp> iniciar() async {
    final armazenamento = await Armazenamento.abrir();
    final api = Api(host: armazenamento.host ?? ConfigApp.hostPadrao())
      ..token = armazenamento.token;
    final estado = EstadoApp._(armazenamento, api)
      ..usuario = armazenamento.usuario
      ..contas.addAll(armazenamento.lerContas())
      ..fila.addAll(armazenamento.lerFila())
      ..historico.addAll(armazenamento.lerHistorico());
    return estado;
  }

  final Armazenamento _armazenamento;
  final Api api;

  String? usuario;

  /// `false` depois de uma falha de rede; volta a `true` na próxima resposta.
  bool online = true;

  /// Contas em cache local (último estado confirmado pelo servidor).
  final Map<int, ContaLocal> contas = {};

  /// Operações feitas offline, na ordem em que o usuário as fez.
  final List<OperacaoPendente> fila = [];

  /// O que aconteceu com as operações que já saíram da fila (mais recente 1o).
  final List<RegistroSincronizacao> historico = [];

  bool sincronizando = false;

  /// Avisos pontuais para a tela mostrar (ex.: "3 operações sincronizadas").
  final StreamController<Aviso> _avisos = StreamController<Aviso>.broadcast();
  Stream<Aviso> get avisos => _avisos.stream;

  StreamSubscription<List<ConnectivityResult>>? _conectividade;
  Timer? _timerSync;

  bool get offlineSimulado => api.offlineSimulado;

  List<OperacaoPendente> pendentesDa(int idConta) =>
      fila.where((o) => o.idConta == idConta).toList();

  int get totalPendentes => fila.where((o) => o.status == StatusOperacao.pendente).length;
  int get totalConflitos => fila.where((o) => o.status == StatusOperacao.conflito).length;
  int get totalRejeitadas => fila.where((o) => o.status == StatusOperacao.rejeitada).length;

  bool get logado => api.token != null;
  String get host => api.host;

  List<ContaLocal> get contasOrdenadas =>
      contas.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  // ---- sessão ----------------------------------------------------------------

  Future<void> entrar(String usuario, String senha) async {
    final token = await _comRede(() => api.login(usuario, senha));
    api.token = token;
    this.usuario = usuario;
    await _armazenamento.salvarSessao(token, usuario);
    notifyListeners();
    // A fila sobreviveu à sessão expirada: envia agora.
    unawaited(sincronizar());
  }

  Future<void> sair() async {
    api.token = null;
    usuario = null;
    await _armazenamento.salvarSessao(null, null);
    notifyListeners();
  }

  Future<void> definirHost(String host) async {
    api.host = host.trim();
    await _armazenamento.salvarHost(api.host);
    notifyListeners();
  }

  /// Executa uma chamada à API mantendo `online` em dia e derrubando a sessão
  /// local se o token morreu.
  Future<T> _comRede<T>(Future<T> Function() chamada) async {
    try {
      final r = await chamada();
      _marcarOnline(true);
      return r;
    } on SemConexao {
      _marcarOnline(false);
      rethrow;
    } on SessaoExpirada {
      _marcarOnline(true);
      await _derrubarSessao();
      rethrow;
    } on ErroApi {
      _marcarOnline(true);
      rethrow;
    }
  }

  /// Token expirou/invalidou: volta para o login. A fila e o cache ficam -
  /// depois do novo login a sincronização continua de onde parou.
  Future<void> _derrubarSessao() async {
    api.token = null;
    await _armazenamento.salvarSessao(null, null);
    notifyListeners();
  }

  void _marcarOnline(bool valor) {
    if (online == valor) return;
    online = valor;
    notifyListeners();
  }

  void _avisar(String texto, [TipoAviso tipo = TipoAviso.sucesso]) {
    if (!_avisos.isClosed) _avisos.add(Aviso(texto, tipo));
  }

  // ---- detecção de conexão e sincronização automática ---------------------------

  /// Liga os gatilhos de sincronização. Chamado pelo `main` (os testes chamam
  /// [sincronizar] diretamente).
  void iniciarSincronizacaoAutomatica() {
    // Mudança de rede do aparelho (Wi-Fi/dados/nenhuma). Não basta para saber
    // se a AGÊNCIA está no ar, por isso o timer abaixo também testa de fato.
    _conectividade ??= Connectivity().onConnectivityChanged.listen((resultado) {
      if (resultado.every((r) => r == ConnectivityResult.none)) {
        _marcarOnline(false);
      } else {
        unawaited(verificarConexao());
      }
    });
    _timerSync ??= Timer.periodic(ConfigApp.intervaloTentativaSync, (_) {
      if (!online || totalPendentes > 0) unawaited(verificarConexao());
    });
    unawaited(verificarConexao());
  }

  @override
  void dispose() {
    _conectividade?.cancel();
    _timerSync?.cancel();
    _avisos.close();
    super.dispose();
  }

  /// Testa se alguma agência responde; se voltou, sincroniza a fila e
  /// atualiza os saldos em cache.
  Future<void> verificarConexao() async {
    final estavaOffline = !online;
    final noAr = await api.algumaAgenciaNoAr();
    _marcarOnline(noAr);
    if (!noAr || !logado) return;
    if (estavaOffline) _avisar('Conexao restabelecida.');
    await sincronizar();
    if (estavaOffline) {
      try {
        await atualizarContas();
      } catch (_) {/* sessão expirada: a tela de login aparece sozinha */}
    }
  }

  Future<void> definirOfflineSimulado(bool valor) async {
    api.offlineSimulado = valor;
    notifyListeners();
    if (valor) {
      _marcarOnline(false);
    } else {
      await verificarConexao();
    }
  }

  // ---- contas ------------------------------------------------------------------

  /// Saldo que a tela mostra (UI otimista): o último saldo confirmado pelo
  /// servidor + o efeito das operações ainda na fila.
  double saldoExibido(int id) =>
      (contas[id]?.saldoServidor ?? 0) +
      pendentesDa(id).fold<double>(0, (soma, o) => soma + o.efeitoOtimista);

  Future<void> _salvarFila() => _armazenamento.salvarFila(fila);

  Future<void> _guardar(Map<String, dynamic> json) async {
    final id = json['id'] as int;
    final existente = contas[id];
    if (existente == null) {
      contas[id] = ContaLocal.daApi(json);
    } else {
      existente.atualizarDaApi(json);
    }
    await _armazenamento.salvarContas(contas);
    notifyListeners();
  }

  /// Busca a conta no servidor e atualiza o cache. Sem conexão, devolve o que
  /// estiver em cache (ou repassa o erro se a conta nunca foi aberta aqui).
  Future<ContaLocal> abrirConta(int id) async {
    try {
      await _guardar(await _comRede(() => api.consultarConta(id)));
    } on SemConexao {
      if (contas[id] == null) rethrow;
    }
    return contas[id]!;
  }

  Future<void> esquecerConta(int id) async {
    if (pendentesDa(id).isNotEmpty) {
      throw ErroApi(0, 'A conta tem operacoes na fila de sincronizacao. Resolva-as antes.');
    }
    contas.remove(id);
    await _armazenamento.salvarContas(contas);
    notifyListeners();
  }

  /// Atualiza todas as contas em cache (puxar para atualizar).
  Future<void> atualizarContas() async {
    for (final id in contas.keys.toList()) {
      try {
        await _guardar(await _comRede(() => api.consultarConta(id)));
      } on SemConexao {
        return;
      } on ErroApi catch (e) {
        if (e is SessaoExpirada) rethrow;
        // 404: a agência reiniciou e perdeu a conta - mantém o cache.
      }
    }
  }

  Future<ContaLocal> criarConta(int id, String nome, double saldoInicial) async {
    await _guardar(await _comRede(() => api.criarConta(id, nome, saldoInicial)));
    return contas[id]!;
  }

  Future<String> depositar(int id, double valor) => _operar(id, 'DEPOSITO', valor);

  Future<String> sacar(int id, double valor) => _operar(id, 'SAQUE', valor);

  /// Depósito/saque. Online e sem fila para a conta: usa a API de sempre
  /// (`/contas/{id}/depositar|sacar`). Sem conexão - ou se a conta já tem
  /// operações na fila (para não passar na frente delas) - vai para a fila.
  Future<String> _operar(int id, String tipo, double valor) async {
    final nome = tipo == 'DEPOSITO' ? 'Deposito' : 'Saque';
    if (pendentesDa(id).isEmpty) {
      try {
        await _guardar(await _comRede(
            () => tipo == 'DEPOSITO' ? api.depositar(id, valor) : api.sacar(id, valor)));
        return '$nome de ${formatarReais(valor)} confirmado.';
      } on SemConexao {
        // segue para a fila
      }
    }

    final conta = contas[id];
    if (conta == null) {
      throw ErroApi(0, 'Abra a conta com conexao ao menos uma vez antes de operar offline.');
    }
    if (tipo == 'SAQUE' && saldoExibido(id) < valor) {
      throw ErroApi(400, 'Saldo insuficiente (saldo local, ja contando as operacoes pendentes).');
    }
    fila.add(OperacaoPendente(
      id: _novoId(),
      idConta: id,
      tipo: tipo,
      valor: valor,
      vetorBase: List.of(conta.vetor),
      criadaEm: DateTime.now(),
    ));
    await _salvarFila();
    notifyListeners();
    unawaited(sincronizar());
    return '$nome de ${formatarReais(valor)} salvo no aparelho; sera sincronizado ao reconectar.';
  }

  // ---- sincronização da fila -----------------------------------------------------

  /// Envia as operações pendentes, em ordem, para `/sync/operacoes`.
  ///
  /// - 200 (APLICADA/MESCLADA/JA_APLICADA): sai da fila; o saldo/versão do
  ///   servidor substituem o cache e as próximas operações da mesma conta que
  ///   tinham a mesma base passam a usar a versão nova (elas vêm causalmente
  ///   depois desta);
  /// - 409: marca CONFLITO e para de enviar as outras operações da conta até
  ///   o usuário decidir;
  /// - 400/404: REJEITADA (ex.: saldo insuficiente no servidor);
  /// - sem conexão com a agência da conta: continua pendente.
  Future<void> sincronizar() async {
    if (sincronizando || !logado) return;
    if (!fila.any((o) => o.status == StatusOperacao.pendente)) return;
    sincronizando = true;
    notifyListeners();

    final bloqueadas = <int>{
      for (final o in fila)
        if (o.status == StatusOperacao.conflito || o.status == StatusOperacao.rejeitada) o.idConta,
    };
    var aplicadas = 0;
    try {
      for (final op in List.of(fila)) {
        if (op.status != StatusOperacao.pendente || bloqueadas.contains(op.idConta)) continue;
        op.status = StatusOperacao.enviando;
        notifyListeners();
        final baseUsada = List.of(op.vetorBase);
        try {
          final r = await api.sincronizar(op);
          _marcarOnline(true);
          fila.remove(op);
          final conta = r['conta'];
          if (conta is Map) await _guardar(conta.cast<String, dynamic>());
          final novaBase = contas[op.idConta]?.vetor;
          if (novaBase != null) {
            for (final o in fila) {
              if (o.idConta == op.idConta && listEquals(o.vetorBase, baseUsada)) {
                o.vetorBase = List.of(novaBase);
              }
            }
          }
          final status = '${r['status']}';
          final concorrentes = (r['escritasConcorrentes'] as List?)?.length ?? 0;
          _registrar(
            op,
            status,
            status == 'MESCLADA'
                ? 'Mesclado com $concorrentes escrita(s) feitas no servidor enquanto o app estava offline.'
                : null,
          );
          if (status == 'MESCLADA') {
            _avisar(
              'Deposito offline na conta ${op.idConta} mesclado com $concorrentes alteracao(oes) do servidor.',
              TipoAviso.alerta,
            );
          }
          aplicadas++;
        } on ConflitoSincronizacao catch (e) {
          op.status = StatusOperacao.conflito;
          op.conflito = e.corpo;
          final conta = e.corpo?['contaServidor'];
          if (conta is Map) await _guardar(conta.cast<String, dynamic>());
          bloqueadas.add(op.idConta);
          _avisar('Conflito na conta ${op.idConta}: ${e.mensagem}', TipoAviso.erro);
        } on SessaoExpirada {
          op.status = StatusOperacao.pendente;
          _marcarOnline(true);
          await _derrubarSessao();
          _avisar('Sessao expirada: entre de novo para terminar a sincronizacao.', TipoAviso.alerta);
          break;
        } on SemConexao {
          // A agência DESTA conta não respondeu; as de outras agências ainda
          // podem ir.
          op.status = StatusOperacao.pendente;
          bloqueadas.add(op.idConta);
        } on ErroApi catch (e) {
          _marcarOnline(true);
          op.status = StatusOperacao.rejeitada;
          op.erro = e.mensagem;
          bloqueadas.add(op.idConta);
          _avisar('Operacao na conta ${op.idConta} rejeitada: ${e.mensagem}', TipoAviso.erro);
        }
        await _salvarFila();
      }
    } finally {
      sincronizando = false;
      await _salvarFila();
      notifyListeners();
    }
    if (aplicadas > 0) _avisar('$aplicadas operacao(oes) offline sincronizada(s).');
  }

  /// Decisão do usuário sobre uma operação em CONFLITO.
  ///
  /// - reaplicar: refaz a operação sobre a versão ATUAL do servidor (o usuário
  ///   viu o saldo novo e confirmou). As outras operações da conta que tinham a
  ///   mesma base antiga também são rebaseadas.
  /// - descartar: tira da fila; o saldo volta a ser só o do servidor.
  Future<void> resolverConflito(OperacaoPendente op, {required bool reaplicar}) async {
    if (!fila.contains(op)) return;
    if (reaplicar) {
      final servidor = contas[op.idConta]?.vetor;
      if (servidor == null) return;
      final antiga = List.of(op.vetorBase);
      for (final o in fila) {
        if (o.idConta == op.idConta && listEquals(o.vetorBase, antiga)) {
          o.vetorBase = List.of(servidor);
        }
      }
      op
        ..status = StatusOperacao.pendente
        ..conflito = null
        ..erro = null;
    } else {
      fila.remove(op);
      _registrar(op, 'DESCARTADA', 'Descartada pelo usuario apos ${op.erro ?? 'conflito'}.');
    }
    await _salvarFila();
    notifyListeners();
    await sincronizar();
  }

  void _registrar(OperacaoPendente op, String resultado, [String? detalhe]) {
    historico.insert(
      0,
      RegistroSincronizacao(
        idOperacao: op.id,
        idConta: op.idConta,
        tipo: op.tipo,
        valor: op.valor,
        resultado: resultado,
        quando: DateTime.now(),
        detalhe: detalhe,
      ),
    );
    if (historico.length > 30) historico.removeLast();
    unawaited(_armazenamento.salvarHistorico(historico));
  }

  static final Random _aleatorio = Random.secure();

  /// UUID v4 (identifica a operação no servidor - idempotência).
  static String _novoId() {
    final b = List<int>.generate(16, (_) => _aleatorio.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Transferência exige conexão: o dinheiro sai para outra agência (via
  /// RabbitMQ) e não dá para "desfazer" otimisticamente do lado do app.
  Future<String> transferir(int origem, int destino, double valor) async {
    final r = await _comRede(() => api.transferir(origem, destino, valor));
    await abrirConta(origem);
    if (contas.containsKey(destino) &&
        ConfigApp.agenciaDaConta(destino) == ConfigApp.agenciaDaConta(origem)) {
      await abrirConta(destino);
    }
    return '${r['mensagem']}';
  }
}

String formatarReais(double v) {
  final negativo = v < 0;
  final partes = v.abs().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${negativo ? '-' : ''}R\$ $inteiro,${partes[1]}';
}

String formatarHora(DateTime t) {
  final l = t.toLocal();
  String d(int n) => n.toString().padLeft(2, '0');
  return '${d(l.hour)}:${d(l.minute)}:${d(l.second)}';
}
