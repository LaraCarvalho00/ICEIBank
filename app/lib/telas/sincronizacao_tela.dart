import 'package:material_ui/material_ui.dart';

import '../modelos.dart';
import '../servicos/estado_app.dart';
import '../widgets/comum.dart';
import '../widgets/tema.dart';

/// Fila offline: conflitos (409) para o usuário resolver, operações
/// rejeitadas, pendentes e o histórico do que já foi sincronizado.
class SincronizacaoTela extends StatelessWidget {
  const SincronizacaoTela({super.key, required this.estado});

  final EstadoApp estado;

  @override
  Widget build(BuildContext context) {
    final conflitos = estado.fila.where((o) => o.status == StatusOperacao.conflito).toList();
    final rejeitadas = estado.fila.where((o) => o.status == StatusOperacao.rejeitada).toList();
    final pendentes = estado.fila
        .where((o) => o.status == StatusOperacao.pendente || o.status == StatusOperacao.enviando)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              estado.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              color: estado.online ? Cores.destaque : Cores.alerta,
            ),
            title: Text(estado.online ? 'Online' : 'Offline'),
            subtitle: Text(
              '${pendentes.length} pendente(s) · ${conflitos.length} conflito(s) · '
              '${rejeitadas.length} rejeitada(s)',
              style: const TextStyle(color: Cores.textoSuave),
            ),
            trailing: estado.sincronizando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    tooltip: 'Sincronizar agora',
                    icon: const Icon(Icons.sync),
                    onPressed: () => estado.verificarConexao(),
                  ),
          ),
        ),
        if (conflitos.isNotEmpty) ...[
          _Titulo('Conflitos de sincronizacao (HTTP 409)', cor: Cores.erro),
          for (final op in conflitos) _CartaoConflito(estado: estado, op: op),
        ],
        if (rejeitadas.isNotEmpty) ...[
          _Titulo('Rejeitadas pelo servidor', cor: Cores.erro),
          for (final op in rejeitadas)
            Card(
              child: ListTile(
                leading: const Icon(Icons.block, color: Cores.erro),
                title: Text(_descricao(op)),
                subtitle: Text(op.erro ?? '', style: const TextStyle(color: Cores.erro)),
                trailing: TextButton(
                  onPressed: () => estado.resolverConflito(op, reaplicar: false),
                  child: const Text('Descartar'),
                ),
              ),
            ),
        ],
        _Titulo('Na fila (${pendentes.length})'),
        if (pendentes.isEmpty)
          const Text('Nada esperando para sincronizar.', style: TextStyle(color: Cores.textoFraco)),
        for (final op in pendentes)
          Card(
            child: ListTile(
              leading: Icon(
                op.status == StatusOperacao.enviando ? Icons.cloud_upload_outlined : Icons.schedule,
                color: Cores.alerta,
              ),
              title: Text(_descricao(op)),
              subtitle: Text(
                'feita as ${formatarHora(op.criadaEm)} · base ${vetorTexto(op.vetorBase)}',
                style: const TextStyle(color: Cores.textoSuave),
              ),
            ),
          ),
        _Titulo('Historico de sincronizacao'),
        if (estado.historico.isEmpty)
          const Text('Nenhuma operacao offline sincronizada ainda.',
              style: TextStyle(color: Cores.textoFraco)),
        for (final r in estado.historico)
          ListTile(
            dense: true,
            leading: Icon(_iconeResultado(r.resultado), color: _corResultado(r.resultado)),
            title: Text(
                '${r.tipo == 'DEPOSITO' ? 'Deposito' : 'Saque'} ${formatarReais(r.valor)} · conta ${r.idConta}'),
            subtitle: Text(
              '${r.resultado} as ${formatarHora(r.quando)}${r.detalhe == null ? '' : '\n${r.detalhe}'}',
              style: TextStyle(color: _corResultado(r.resultado)),
            ),
          ),
      ],
    );
  }

  static IconData _iconeResultado(String r) => switch (r) {
        'APLICADA' || 'JA_APLICADA' => Icons.check_circle_outline,
        'MESCLADA' => Icons.call_merge,
        _ => Icons.delete_outline,
      };

  static Color _corResultado(String r) => switch (r) {
        'APLICADA' || 'JA_APLICADA' => Cores.destaque,
        'MESCLADA' => Cores.info,
        _ => Cores.textoSuave,
      };
}

String _descricao(OperacaoPendente op) =>
    '${op.tipo == 'DEPOSITO' ? 'Deposito' : 'Saque'} de ${formatarReais(op.valor)} · conta ${op.idConta}';

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, {this.cor = Cores.textoSuave});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
      );
}

/// O 409 explicado: o que o app tinha, o que o servidor tem, o que mudou no
/// meio - e a decisão fica com o usuário.
class _CartaoConflito extends StatelessWidget {
  const _CartaoConflito({required this.estado, required this.op});

  final EstadoApp estado;
  final OperacaoPendente op;

  @override
  Widget build(BuildContext context) {
    final c = op.conflito ?? const {};
    final contaServidor = (c['contaServidor'] as Map?) ?? const {};
    final saldoServidor = (contaServidor['saldo'] as num?)?.toDouble();
    final escritas = (c['escritasConcorrentes'] as List?) ?? const [];
    final vetorServidor = (c['vetorServidor'] as List?)?.map((e) => (e as num).toInt()).toList();

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Cores.erro),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Cores.erro),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_descricao(op), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${c['motivo'] ?? 'Conflito'}', style: const TextStyle(color: Cores.erro)),
            const SizedBox(height: 8),
            Text(
              'Relacao vetorial: ${c['relacao'] ?? '?'}\n'
              'Versao que o app conhecia: ${vetorTexto(op.vetorBase)}\n'
              'Versao atual no servidor: ${vetorServidor == null ? '?' : vetorTexto(vetorServidor)}'
              '${saldoServidor == null ? '' : '\nSaldo atual no servidor: ${formatarReais(saldoServidor)}'}',
              style: const TextStyle(color: Cores.textoSuave, height: 1.4),
            ),
            if (escritas.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Alteracoes que o app nao viu:', style: TextStyle(color: Cores.textoSuave)),
              for (final e in escritas.whereType<Map>())
                Text(
                  '  • ${e['tipo']} ${(e['detalhes'] as Map?)?['valor'] ?? ''} · vetor ${e['vetor']}',
                  style: const TextStyle(color: Cores.textoFraco, fontSize: 12),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => estado.resolverConflito(op, reaplicar: true),
                  child: const Text('Reaplicar sobre o saldo atual'),
                ),
                OutlinedButton(
                  onPressed: () => estado.resolverConflito(op, reaplicar: false),
                  child: const Text('Descartar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
