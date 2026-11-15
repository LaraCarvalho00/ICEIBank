import 'package:material_ui/material_ui.dart';

import '../servicos/api.dart';
import '../servicos/estado_app.dart';
import 'tema.dart';

/// Mensagem rápida no rodapé (verde = ok, vermelho = erro, amarelo = aviso).
void avisar(BuildContext context, String texto, {Color cor = Cores.destaque}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto, style: const TextStyle(color: Colors.black)),
      backgroundColor: cor,
      behavior: SnackBarBehavior.floating,
    ));
}

/// Traduz uma exceção da API para uma frase para o usuário.
String mensagemDeErro(Object erro) {
  if (erro is SemConexao) return 'Sem conexao: ${erro.mensagem}';
  if (erro is SessaoExpirada) return 'Sessao expirada. Entre novamente.';
  if (erro is ErroApi) return erro.mensagem;
  return '$erro';
}

void avisarErro(BuildContext context, Object erro) =>
    avisar(context, mensagemDeErro(erro), cor: Cores.erro);

double? lerValor(String texto) {
  final v = double.tryParse(texto.trim().replaceAll(',', '.'));
  if (v == null || v <= 0) return null;
  return double.parse(v.toStringAsFixed(2));
}

/// Diálogo de valor (depósito/saque).
Future<double?> pedirValor(BuildContext context, String titulo) async {
  final ctrl = TextEditingController();
  String? erro;
  return showDialog<double>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Valor (R\$)', errorText: erro),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = lerValor(ctrl.text);
              if (v == null) {
                setState(() => erro = 'Informe um valor maior que zero');
                return;
              }
              Navigator.pop(context, v);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ),
  );
}

/// Configurações: endereço das agências.
Future<void> abrirConfiguracoes(BuildContext context, EstadoApp estado) async {
  final ctrl = TextEditingController(text: estado.host);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Configuracoes'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Host das agencias',
              helperText: 'Portas 4000, 4001 e 4002.\nEmulador Android: 10.0.2.2',
              helperMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            await estado.definirHost(ctrl.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}

/// Vetor no formato do backend: [3, 1, 0].
String vetorTexto(List<int> v) => '[${v.join(', ')}]';
