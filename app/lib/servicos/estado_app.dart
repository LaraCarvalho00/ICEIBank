import 'package:flutter/foundation.dart';

import '../config.dart';
import '../modelos.dart';
import 'api.dart';
import 'armazenamento.dart';

/// Estado central do app (CONTROLLER no MVC do app): as telas só leem daqui e
/// chamam métodos daqui; quem fala com a API e com o armazenamento local é
/// este objeto.
class EstadoApp extends ChangeNotifier {
  EstadoApp._(this._armazenamento, this.api);

  static Future<EstadoApp> iniciar() async {
    final armazenamento = await Armazenamento.abrir();
    final api = Api(host: armazenamento.host ?? ConfigApp.hostPadrao())
      ..token = armazenamento.token;
    final estado = EstadoApp._(armazenamento, api)
      ..usuario = armazenamento.usuario
      ..contas.addAll(armazenamento.lerContas());
    return estado;
  }

  final Armazenamento _armazenamento;
  final Api api;

  String? usuario;

  /// `false` depois de uma falha de rede; volta a `true` na próxima resposta.
  bool online = true;

  /// Contas em cache local (último estado confirmado pelo servidor).
  final Map<int, ContaLocal> contas = {};

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
      api.token = null;
      await _armazenamento.salvarSessao(null, null);
      notifyListeners();
      rethrow;
    } on ErroApi {
      _marcarOnline(true);
      rethrow;
    }
  }

  void _marcarOnline(bool valor) {
    if (online == valor) return;
    online = valor;
    notifyListeners();
  }

  // ---- contas ------------------------------------------------------------------

  /// Saldo que a tela mostra.
  double saldoExibido(int id) => contas[id]?.saldoServidor ?? 0;

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

  Future<String> depositar(int id, double valor) async {
    await _guardar(await _comRede(() => api.depositar(id, valor)));
    return 'Deposito de ${formatarReais(valor)} confirmado.';
  }

  Future<String> sacar(int id, double valor) async {
    await _guardar(await _comRede(() => api.sacar(id, valor)));
    return 'Saque de ${formatarReais(valor)} confirmado.';
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
