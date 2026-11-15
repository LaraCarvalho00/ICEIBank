import 'package:material_ui/material_ui.dart';

import '../servicos/estado_app.dart';
import '../widgets/comum.dart';
import '../widgets/tema.dart';

class LoginTela extends StatefulWidget {
  const LoginTela({super.key, required this.estado});

  final EstadoApp estado;

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _usuario = TextEditingController(text: 'lara');
  final _senha = TextEditingController();
  bool _enviando = false;
  String? _erro;

  Future<void> _entrar() async {
    if (_usuario.text.trim().isEmpty || _senha.text.isEmpty) {
      setState(() => _erro = 'Informe usuario e senha.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.estado.entrar(_usuario.text.trim(), _senha.text);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Configuracoes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => abrirConfiguracoes(context, widget.estado),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.account_balance, size: 56, color: Cores.destaque),
                const SizedBox(height: 12),
                Text('ICEIBank',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('Agencias em ${widget.estado.host}:4000-4002',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Cores.textoSuave)),
                const SizedBox(height: 28),
                TextField(
                  controller: _usuario,
                  decoration: const InputDecoration(labelText: 'Usuario'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _senha,
                  decoration: const InputDecoration(labelText: 'Senha'),
                  obscureText: true,
                  onSubmitted: (_) => _entrar(),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Text(_erro!, style: const TextStyle(color: Cores.erro)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _enviando ? null : _entrar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _enviando
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Entrar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
