import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../modelos.dart';
import '../servicos/estado_app.dart';
import '../widgets/comum.dart';
import '../widgets/tema.dart';
import 'conta_tela.dart';

/// Lista das contas abertas neste aparelho (cache local) + abrir/criar conta.
class ContasTela extends StatefulWidget {
  const ContasTela({super.key, required this.estado});

  final EstadoApp estado;

  @override
  State<ContasTela> createState() => _ContasTelaState();
}

class _ContasTelaState extends State<ContasTela> {
  final _numero = TextEditingController();
  bool _abrindo = false;

  Future<void> _abrir() async {
    final id = int.tryParse(_numero.text.trim());
    if (id == null || id < 0) {
      avisar(context, 'Informe o numero da conta (inteiro >= 0).', cor: Cores.alerta);
      return;
    }
    setState(() => _abrindo = true);
    try {
      await widget.estado.abrirConta(id);
      _numero.clear();
      if (mounted) _irPara(id);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _abrindo = false);
    }
  }

  void _irPara(int id) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ContaTela(estado: widget.estado, idConta: id)),
      );

  Future<void> _novaConta() async {
    final criada = await showDialog<int>(
      context: context,
      builder: (_) => _DialogoNovaConta(estado: widget.estado),
    );
    if (criada != null && mounted) {
      avisar(context, 'Conta $criada criada na agencia ${ConfigApp.agenciaDaConta(criada)}.');
      _irPara(criada);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    final contas = estado.contasOrdenadas;
    return RefreshIndicator(
      onRefresh: () async {
        try {
          await estado.atualizarContas();
        } catch (e) {
          if (context.mounted) avisarErro(context, e);
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _numero,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Numero da conta',
                    helperText: 'A agencia e definida por numero % 3',
                  ),
                  onSubmitted: (_) => _abrir(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _abrindo ? null : _abrir,
                child: const Text('Abrir'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _novaConta,
              icon: const Icon(Icons.add),
              label: const Text('Criar nova conta'),
            ),
          ),
          const SizedBox(height: 8),
          if (contas.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Text(
                'Nenhuma conta aberta neste aparelho ainda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Cores.textoSuave),
              ),
            ),
          for (final c in contas) _CartaoConta(estado: estado, conta: c, aoTocar: () => _irPara(c.id)),
        ],
      ),
    );
  }
}

class _CartaoConta extends StatelessWidget {
  const _CartaoConta({required this.estado, required this.conta, required this.aoTocar});

  final EstadoApp estado;
  final ContaLocal conta;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: aoTocar,
        title: Text('Conta ${conta.id} · ${conta.nome}'),
        subtitle: Text(
          'Agencia ${ConfigApp.agenciaDaConta(conta.id)} · versao ${vetorTexto(conta.vetor)}'
          '${estado.pendentesDa(conta.id).isEmpty ? '' : '\n${estado.pendentesDa(conta.id).length} operacao(oes) na fila'}',
          style: TextStyle(
            color: estado.pendentesDa(conta.id).isEmpty ? Cores.textoSuave : Cores.alerta,
          ),
        ),
        trailing: Text(
          formatarReais(estado.saldoExibido(conta.id)),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _DialogoNovaConta extends StatefulWidget {
  const _DialogoNovaConta({required this.estado});

  final EstadoApp estado;

  @override
  State<_DialogoNovaConta> createState() => _DialogoNovaContaState();
}

class _DialogoNovaContaState extends State<_DialogoNovaConta> {
  final _id = TextEditingController();
  final _nome = TextEditingController();
  final _saldo = TextEditingController(text: '0');
  String? _erro;
  bool _enviando = false;

  Future<void> _criar() async {
    final id = int.tryParse(_id.text.trim());
    final saldo = double.tryParse(_saldo.text.trim().replaceAll(',', '.'));
    if (id == null || id < 0 || _nome.text.trim().isEmpty || saldo == null || saldo < 0) {
      setState(() => _erro = 'Preencha numero (>= 0), nome e saldo inicial (>= 0).');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.estado.criarConta(id, _nome.text.trim(), saldo);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova conta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _id,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Numero da conta'),
          ),
          const SizedBox(height: 8),
          TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome do titular')),
          const SizedBox(height: 8),
          TextField(
            controller: _saldo,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Saldo inicial (R\$)'),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 8),
            Text(_erro!, style: const TextStyle(color: Cores.erro)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _enviando ? null : _criar, child: const Text('Criar')),
      ],
    );
  }
}
