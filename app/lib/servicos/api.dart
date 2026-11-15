import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../modelos.dart';

/// Não deu para falar com a agência (fora do ar, sem rede, timeout ou modo
/// offline simulado). Para o app, isso significa "estou offline".
class SemConexao implements Exception {
  SemConexao([this.mensagem = 'Sem conexao com a agencia.']);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// A API respondeu com status != 2xx.
class ErroApi implements Exception {
  ErroApi(this.status, this.mensagem, [this.corpo]);
  final int status;
  final String mensagem;
  final Map<String, dynamic>? corpo;
  @override
  String toString() => mensagem;
}

/// Token ausente, inválido ou expirado (401).
class SessaoExpirada extends ErroApi {
  SessaoExpirada(String mensagem) : super(401, mensagem);
}

/// HTTP 409 de `POST /sync/operacoes`: a conta mudou enquanto o app estava
/// offline. `corpo` traz o estado do servidor e as escritas concorrentes.
class ConflitoSincronizacao extends ErroApi {
  ConflitoSincronizacao(Map<String, dynamic> corpo)
      : super(409, (corpo['motivo'] ?? 'Conflito de sincronizacao') as String, corpo);
}

/// Cliente HTTP do ICEIBank - o equivalente ao `api/cliente.js` do frontend
/// web: ponto único por onde toda requisição passa (escolhe a agência pela
/// conta, injeta o JWT, aplica timeout e traduz erros).
///
/// Reaproveita a API que já existia (Sprints 1-2) sem mudanças: `/auth/login`,
/// `/contas`, `/contas/{id}/depositar|sacar`, `/transferencias`. Do Sprint 3,
/// usa `/bully/lider` (painel de liderança) e `/sync/operacoes` (offline-first).
class Api {
  Api({required this.host});

  String host;
  String? token;

  /// Liga/desliga um "modo avião" só do app: toda requisição falha como se
  /// não houvesse rede. Facilita demonstrar o offline-first sem mexer na rede
  /// do emulador.
  bool offlineSimulado = false;

  final http.Client _http = http.Client();

  Uri _uri(int agencia, String caminho) =>
      Uri.parse('http://$host:${ConfigApp.portaBase + agencia}$caminho');

  Future<dynamic> _requisitar(
    int agencia,
    String metodo,
    String caminho, {
    Object? corpo,
    Duration? timeout,
    bool autenticar = true,
  }) async {
    if (offlineSimulado) {
      throw SemConexao('Modo offline simulado ligado.');
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (autenticar && token != null) headers['Authorization'] = 'Bearer $token';

    http.Response resposta;
    try {
      final req = http.Request(metodo, _uri(agencia, caminho))..headers.addAll(headers);
      if (corpo != null) req.body = jsonEncode(corpo);
      final stream = await _http.send(req).timeout(timeout ?? ConfigApp.timeoutRequisicao);
      resposta = await http.Response.fromStream(stream);
    } on TimeoutException {
      throw SemConexao('A agencia $agencia nao respondeu a tempo.');
    } catch (_) {
      // http.ClientException (conexão recusada, sem rede, DNS...) e afins.
      throw SemConexao('Nao foi possivel falar com a agencia $agencia.');
    }

    dynamic dados;
    if (resposta.body.isNotEmpty) {
      try {
        dados = jsonDecode(utf8.decode(resposta.bodyBytes));
      } catch (_) {
        dados = null;
      }
    }

    if (resposta.statusCode >= 200 && resposta.statusCode < 300) return dados;

    if (resposta.statusCode == 401) {
      throw SessaoExpirada(_detalhe(dados) ?? 'Sessao expirada. Entre novamente.');
    }
    if (resposta.statusCode == 409 && dados is Map && dados['status'] == 'CONFLITO') {
      throw ConflitoSincronizacao(dados.cast<String, dynamic>());
    }
    throw ErroApi(
      resposta.statusCode,
      _detalhe(dados) ?? 'Erro ${resposta.statusCode}',
      dados is Map ? dados.cast<String, dynamic>() : null,
    );
  }

  /// O FastAPI devolve `detail` como texto ou, no 422, como lista de erros.
  String? _detalhe(dynamic dados) {
    if (dados is! Map) return null;
    final d = dados['detail'];
    if (d is String) return d;
    if (d is List) {
      return d.map((e) {
        if (e is! Map) return '$e';
        final loc = e['loc'];
        final campo = loc is List && loc.isNotEmpty ? loc.last : null;
        final msg = '${e['msg'] ?? ''}'.replaceFirst(RegExp(r'^Value error,\s*'), '');
        return campo != null && campo != 'body' ? '$campo: $msg' : msg;
      }).join(' · ');
    }
    return null;
  }

  // ---- autenticação ---------------------------------------------------------

  /// Todas as agências validam o mesmo segredo: tenta a 0, depois a 1 e a 2
  /// (assim o login funciona mesmo com uma agência fora do ar).
  Future<String> login(String usuario, String senha) async {
    SemConexao? ultimo;
    for (var ag = 0; ag < ConfigApp.numeroAgencias; ag++) {
      try {
        final dados = await _requisitar(ag, 'POST', '/auth/login',
            corpo: {'usuario': usuario, 'senha': senha}, autenticar: false);
        return (dados as Map)['access_token'] as String;
      } on SemConexao catch (e) {
        ultimo = e;
      }
    }
    throw ultimo ?? SemConexao();
  }

  // ---- contas (API dos Sprints 1-2, sem mudanças) ------------------------------

  Future<Map<String, dynamic>> consultarConta(int id) async =>
      ((await _requisitar(ConfigApp.agenciaDaConta(id), 'GET', '/contas/$id')) as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> criarConta(int id, String nome, double saldoInicial) async =>
      ((await _requisitar(ConfigApp.agenciaDaConta(id), 'POST', '/contas',
              corpo: {'id': id, 'nomeAluno': nome, 'saldoInicial': saldoInicial})) as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> depositar(int id, double valor) async =>
      ((await _requisitar(ConfigApp.agenciaDaConta(id), 'POST', '/contas/$id/depositar',
              corpo: {'valor': valor})) as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> sacar(int id, double valor) async =>
      ((await _requisitar(ConfigApp.agenciaDaConta(id), 'POST', '/contas/$id/sacar',
              corpo: {'valor': valor})) as Map)
          .cast<String, dynamic>();

  /// Sempre para a agência da conta de ORIGEM; o backend decide se é local ou
  /// se publica no RabbitMQ.
  Future<Map<String, dynamic>> transferir(int origem, int destino, double valor) async =>
      ((await _requisitar(ConfigApp.agenciaDaConta(origem), 'POST', '/transferencias',
              corpo: {'idOrigem': origem, 'idDestino': destino, 'valor': valor})) as Map)
          .cast<String, dynamic>();

  // ---- Sprint 3 -------------------------------------------------------------------

  /// `POST /sync/operacoes` na agência dona da conta. 200 = APLICADA,
  /// MESCLADA ou JA_APLICADA; 409 vira [ConflitoSincronizacao].
  Future<Map<String, dynamic>> sincronizar(OperacaoPendente op) async =>
      ((await _requisitar(ConfigApp.agenciaDaConta(op.idConta), 'POST', '/sync/operacoes',
              corpo: op.paraApi())) as Map)
          .cast<String, dynamic>();

  /// `GET /bully/lider` (aberta). `null` = agência fora do ar.
  Future<EstadoAgencia?> consultarLider(int agencia) async {
    final inicio = DateTime.now();
    try {
      final dados = await _requisitar(agencia, 'GET', '/bully/lider',
          timeout: ConfigApp.timeoutLider, autenticar: false);
      final ms = DateTime.now().difference(inicio).inMilliseconds;
      return EstadoAgencia.daApi((dados as Map).cast<String, dynamic>(), ms);
    } on SemConexao {
      return null;
    } on ErroApi {
      return null;
    }
  }

  /// Alguma agência responde? (detecção de "voltei a ficar online").
  Future<bool> algumaAgenciaNoAr() async {
    final respostas = await Future.wait(
      List.generate(ConfigApp.numeroAgencias, consultarLider),
    );
    return respostas.any((r) => r != null);
  }
}
