import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../servicos/estado_app.dart';
import '../widgets/comum.dart';
import '../widgets/tema.dart';

/// Detalhe de uma conta: saldo, depósito, saque e transferência.
class ContaTela extends StatefulWidget {
  const ContaTela({super.key, required this.estado, required this.idConta});

  final EstadoApp estado;
  final int idConta;

  @override
  State<ContaTela> createState() => _ContaTelaState();
}

class _ContaTelaState extends State<ContaTela> {
  bool _ocupado = false;

  EstadoApp get _estado => widget.estado;

  Future<void> _executar(Future<String> Function() acao) async {
    setState(() => _ocupado = true);
    try {
      final msg = await acao();
      if (mounted) avisar(context, msg);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _depositar() async {
    final v = await pedirValor(context, 'Depositar');
    if (v != null) await _executar(() => _estado.depositar(widget.idConta, v));
  }

  Future<void> _sacar() async {
    final v = await pedirValor(context, 'Sacar');
    if (v != null) await _executar(() => _estado.sacar(widget.idConta, v));
  }

  Future<void> _transferir() async {
    final dados = await showDialog<(int, double)>(
      context: context,
      builder: (_) => _DialogoTransferencia(origem: widget.idConta),
    );
    if (dados != null) {
      await _executar(() => _estado.transferir(widget.idConta, dados.$1, dados.$2));
    }
  }

  Future<void> _atualizar() async {
    try {
      await _estado.abrirConta(widget.idConta);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _estado,
      builder: (context, _) {
        final conta = _estado.contas[widget.idConta];
        if (conta == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Conta removida.')));
        }
        final agencia = ConfigApp.agenciaDaConta(conta.id);
        return Scaffold(
          appBar: AppBar(
            title: Text('Conta ${conta.id}'),
            actions: [
              IconButton(
                tooltip: 'Remover deste aparelho',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await _estado.esquecerConta(conta.id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _atualizar,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${conta.nome} · Agencia $agencia',
                            style: const TextStyle(color: Cores.textoSuave)),
                        const SizedBox(height: 8),
                        Text(
                          formatarReais(_estado.saldoExibido(conta.id)),
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        ..._detalhesSaldo(conta.id),
                        const SizedBox(height: 12),
                        Text(
                          'Versao no servidor ${vetorTexto(conta.vetor)} · '
                          'atualizado as ${formatarHora(conta.atualizadaEm)}',
                          style: const TextStyle(color: Cores.textoFraco, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _ocupado ? null : _depositar,
                        icon: const Icon(Icons.add),
                        label: const Text('Depositar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _ocupado ? null : _sacar,
                        icon: const Icon(Icons.remove),
                        label: const Text('Sacar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : _transferir,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Transferir'),
                ),
                if (_ocupado) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
                ..._pendencias(conta.id),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Linhas extras sob o saldo (preenchidas pelo modo offline-first).
  List<Widget> _detalhesSaldo(int id) => const [];

  /// Operações desta conta ainda na fila (preenchidas pelo modo offline-first).
  List<Widget> _pendencias(int id) => const [];
}

class _DialogoTransferencia extends StatefulWidget {
  const _DialogoTransferencia({required this.origem});

  final int origem;

  @override
  State<_DialogoTransferencia> createState() => _DialogoTransferenciaState();
}

class _DialogoTransferenciaState extends State<_DialogoTransferencia> {
  final _destino = TextEditingController();
  final _valor = TextEditingController();
  String? _erro;

  void _confirmar() {
    final destino = int.tryParse(_destino.text.trim());
    final valor = lerValor(_valor.text);
    if (destino == null || destino < 0) {
      setState(() => _erro = 'Conta de destino invalida.');
      return;
    }
    if (destino == widget.origem) {
      setState(() => _erro = 'Origem e destino devem ser contas diferentes.');
      return;
    }
    if (valor == null) {
      setState(() => _erro = 'Informe um valor maior que zero.');
      return;
    }
    Navigator.pop(context, (destino, valor));
  }

  @override
  Widget build(BuildContext context) {
    final destino = int.tryParse(_destino.text.trim());
    final dica = destino == null
        ? 'A agencia de destino e numero % 3'
        : ConfigApp.agenciaDaConta(destino) == ConfigApp.agenciaDaConta(widget.origem)
            ? 'Mesma agencia: credito imediato'
            : 'Agencia ${ConfigApp.agenciaDaConta(destino)}: credito assincrono (RabbitMQ)';
    return AlertDialog(
      title: Text('Transferir da conta ${widget.origem}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _destino,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Conta de destino', helperText: dica),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _valor,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor (R\$)'),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 8),
            Text(_erro!, style: const TextStyle(color: Cores.erro)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirmar, child: const Text('Transferir')),
      ],
    );
  }
}
