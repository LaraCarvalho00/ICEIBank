import 'package:material_ui/material_ui.dart';

import 'servicos/estado_app.dart';
import 'servicos/monitor_lideranca.dart';
import 'telas/inicio_tela.dart';
import 'telas/login_tela.dart';
import 'widgets/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final estado = await EstadoApp.iniciar()
    // Offline-first: tenta reconectar e esvaziar a fila sozinho.
    ..iniciarSincronizacaoAutomatica();
  // O painel de liderança não depende de login (GET /bully/lider é aberta).
  final monitor = MonitorLideranca(estado.api)..iniciar();
  runApp(IceibankApp(estado: estado, monitor: monitor));
}

class IceibankApp extends StatelessWidget {
  const IceibankApp({super.key, required this.estado, required this.monitor});

  final EstadoApp estado;
  final MonitorLideranca monitor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICEIBank',
      debugShowCheckedModeBanner: false,
      theme: temaIceibank(),
      // Sem token -> login. Com token salvo, abre direto (inclusive offline:
      // o app funciona com o cache local mesmo sem conseguir logar de novo).
      home: ListenableBuilder(
        listenable: estado,
        builder: (context, _) =>
            estado.logado ? InicioTela(estado: estado, monitor: monitor) : LoginTela(estado: estado),
      ),
    );
  }
}
