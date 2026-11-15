// MODEL - dados que o app guarda localmente (armazenamento offline-first).

/// Conta em cache local: o último estado CONFIRMADO pelo servidor.
///
/// `vetor` é a versão da conta (carimbo vetorial da última escrita no
/// servidor). Toda operação feita offline guarda esse vetor como `vetorBase`,
/// para o servidor detectar se a conta mudou enquanto o app estava offline.
class ContaLocal {
  ContaLocal({
    required this.id,
    required this.nome,
    required this.saldoServidor,
    required this.vetor,
    required this.atualizadaEm,
  });

  final int id;
  String nome;
  double saldoServidor;
  List<int> vetor;
  DateTime atualizadaEm;

  factory ContaLocal.daApi(Map<String, dynamic> json) => ContaLocal(
        id: json['id'] as int,
        nome: (json['nomeAluno'] ?? '') as String,
        saldoServidor: (json['saldo'] as num).toDouble(),
        vetor: _vetor(json['vetor']),
        atualizadaEm: DateTime.now(),
      );

  void atualizarDaApi(Map<String, dynamic> json) {
    nome = (json['nomeAluno'] ?? nome) as String;
    saldoServidor = (json['saldo'] as num).toDouble();
    vetor = _vetor(json['vetor']);
    atualizadaEm = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'saldoServidor': saldoServidor,
        'vetor': vetor,
        'atualizadaEm': atualizadaEm.toIso8601String(),
      };

  factory ContaLocal.fromJson(Map<String, dynamic> json) => ContaLocal(
        id: json['id'] as int,
        nome: json['nome'] as String,
        saldoServidor: (json['saldoServidor'] as num).toDouble(),
        vetor: _vetor(json['vetor']),
        atualizadaEm: DateTime.parse(json['atualizadaEm'] as String),
      );
}

List<int> _vetor(dynamic v) =>
    v is List ? v.map((e) => (e as num).toInt()).toList() : <int>[0, 0, 0];

enum StatusOperacao { pendente, enviando, conflito, rejeitada }

/// Operação feita sem conexão, esperando na fila local.
class OperacaoPendente {
  OperacaoPendente({
    required this.id,
    required this.idConta,
    required this.tipo,
    required this.valor,
    required this.vetorBase,
    required this.criadaEm,
    this.status = StatusOperacao.pendente,
    this.erro,
    this.conflito,
  });

  final String id; // UUID gerado no app (idempotência no servidor)
  final int idConta;
  final String tipo; // DEPOSITO | SAQUE
  final double valor;
  List<int> vetorBase;
  final DateTime criadaEm;
  StatusOperacao status;
  String? erro;

  /// Corpo do HTTP 409 (estado do servidor e escritas concorrentes).
  Map<String, dynamic>? conflito;

  /// Efeito no saldo exibido (UI otimista). Operações em conflito ou
  /// rejeitadas NÃO entram: o saldo otimista "volta atrás" (rollback).
  double get efeitoOtimista {
    if (status == StatusOperacao.conflito || status == StatusOperacao.rejeitada) {
      return 0;
    }
    return tipo == 'DEPOSITO' ? valor : -valor;
  }

  Map<String, dynamic> paraApi() => {
        'idOperacao': id,
        'idConta': idConta,
        'tipo': tipo,
        'valor': valor,
        'vetorBase': vetorBase,
        'criadaEm': criadaEm.toIso8601String(),
      };

  Map<String, dynamic> toJson() => {
        ...paraApi(),
        'status': status.name,
        'erro': erro,
        'conflito': conflito,
      };

  factory OperacaoPendente.fromJson(Map<String, dynamic> json) => OperacaoPendente(
        id: json['idOperacao'] as String,
        idConta: json['idConta'] as int,
        tipo: json['tipo'] as String,
        valor: (json['valor'] as num).toDouble(),
        vetorBase: _vetor(json['vetorBase']),
        criadaEm: DateTime.parse(json['criadaEm'] as String),
        // "enviando" ao abrir o app = o app fechou no meio do envio: volta
        // para pendente (o servidor é idempotente, reenviar é seguro).
        status: StatusOperacao.values.firstWhere(
          (s) => s.name == json['status'] && s != StatusOperacao.enviando,
          orElse: () => StatusOperacao.pendente,
        ),
        erro: json['erro'] as String?,
        conflito: (json['conflito'] as Map?)?.cast<String, dynamic>(),
      );
}

/// Linha do histórico de sincronização (o que aconteceu com cada operação
/// offline depois que saiu da fila).
class RegistroSincronizacao {
  RegistroSincronizacao({
    required this.idOperacao,
    required this.idConta,
    required this.tipo,
    required this.valor,
    required this.resultado,
    required this.quando,
    this.detalhe,
  });

  final String idOperacao;
  final int idConta;
  final String tipo;
  final double valor;
  final String resultado; // APLICADA | MESCLADA | JA_APLICADA | DESCARTADA
  final DateTime quando;
  final String? detalhe;

  Map<String, dynamic> toJson() => {
        'idOperacao': idOperacao,
        'idConta': idConta,
        'tipo': tipo,
        'valor': valor,
        'resultado': resultado,
        'quando': quando.toIso8601String(),
        'detalhe': detalhe,
      };

  factory RegistroSincronizacao.fromJson(Map<String, dynamic> json) => RegistroSincronizacao(
        idOperacao: json['idOperacao'] as String,
        idConta: json['idConta'] as int,
        tipo: json['tipo'] as String,
        valor: (json['valor'] as num).toDouble(),
        resultado: json['resultado'] as String,
        quando: DateTime.parse(json['quando'] as String),
        detalhe: json['detalhe'] as String?,
      );
}

/// Resposta de `GET /bully/lider` de uma agência.
class EstadoAgencia {
  EstadoAgencia({
    required this.idAgencia,
    required this.liderAtual,
    required this.souLider,
    required this.emEleicao,
    required this.liderDesde,
    required this.vetor,
    required this.latenciaMs,
  });

  final int idAgencia;
  final int? liderAtual;
  final bool souLider;
  final bool emEleicao;
  final DateTime? liderDesde;
  final List<int> vetor;
  final int latenciaMs;

  factory EstadoAgencia.daApi(Map<String, dynamic> json, int latenciaMs) => EstadoAgencia(
        idAgencia: json['idAgencia'] as int,
        liderAtual: json['liderAtual'] as int?,
        souLider: json['souLider'] == true,
        emEleicao: json['emEleicao'] == true,
        liderDesde: json['liderDesde'] == null ? null : DateTime.tryParse(json['liderDesde'] as String),
        vetor: _vetor(json['vetor']),
        latenciaMs: latenciaMs,
      );
}
