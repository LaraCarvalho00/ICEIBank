import 'package:material_ui/material_ui.dart';

import '../servicos/estado_app.dart';
import '../servicos/monitor_lideranca.dart';
import '../widgets/comum.dart';
import '../widgets/tema.dart';
import 'contas_tela.dart';
import 'lideranca_tela.dart';

/// Tela principal: barra superior com o estado da conexão e navegação entre
/// as seções do app.
class InicioTela extends StatefulWidget {
  const InicioTela({super.key, required this.estado, required this.monitor});

  final EstadoApp estado;
  final MonitorLideranca monitor;

  @override
  State<InicioTela> createState() => _InicioTelaState();
}

class _InicioTelaState extends State<InicioTela> {
  int _aba = 0;

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    return ListenableBuilder(
      listenable: estado,
      builder: (context, _) {
        final abas = <({String rotulo, IconData icone, Widget tela})>[
          (rotulo: 'Contas', icone: Icons.account_balance_wallet_outlined, tela: ContasTela(estado: estado)),
          (rotulo: 'Lideranca', icone: Icons.workspace_premium_outlined, tela: LiderancaTela(monitor: widget.monitor)),
        ];
        final aba = _aba < abas.length ? _aba : 0;
        return Scaffold(
          appBar: AppBar(
            title: Text('ICEIBank · ${estado.usuario ?? ''}'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(22),
              child: _LiderNaBarra(monitor: widget.monitor),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Tooltip(
                  message: estado.online ? 'Online' : 'Offline',
                  child: Icon(
                    estado.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    color: estado.online ? Cores.destaque : Cores.alerta,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'config') abrirConfiguracoes(context, estado);
                  if (v == 'sair') estado.sair();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'config', child: Text('Configuracoes')),
                  PopupMenuItem(value: 'sair', child: Text('Sair')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (!estado.online)
                const _Faixa(
                  cor: Cores.alerta,
                  icone: Icons.cloud_off,
                  texto: 'Sem conexao com as agencias. Mostrando o ultimo saldo salvo no aparelho.',
                ),
              Expanded(child: abas[aba].tela),
            ],
          ),
          bottomNavigationBar: abas.length < 2
              ? null
              : NavigationBar(
                  selectedIndex: aba,
                  onDestinationSelected: (i) => setState(() => _aba = i),
                  destinations: [
                    for (final a in abas) NavigationDestination(icon: Icon(a.icone), label: a.rotulo),
                  ],
                ),
        );
      },
    );
  }
}

class _Faixa extends StatelessWidget {
  const _Faixa({required this.cor, required this.icone, required this.texto});

  final Color cor;
  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cor.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icone, color: cor, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: TextStyle(color: cor))),
          ],
        ),
      ),
    );
  }
}

/// Linha fina sob o título: a líder aparece em todas as abas, então o failover
/// fica visível mesmo com o usuário na tela de contas.
class _LiderNaBarra extends StatelessWidget {
  const _LiderNaBarra({required this.monitor});

  final MonitorLideranca monitor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final (texto, cor) = switch (monitor.situacao) {
          SituacaoCluster.estavel => ('Lider: Agencia ${monitor.lider}', Cores.destaque),
          SituacaoCluster.liderSemResposta =>
            ('Lider ${monitor.liderReconhecido} sem resposta - reeleicao a caminho', Cores.alerta),
          SituacaoCluster.emEleicao => ('Eleicao em andamento...', Cores.alerta),
          SituacaoCluster.foraDoAr => ('Agencias fora do ar', Cores.erro),
        };
        return Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 6),
          child: Row(
            children: [
              Icon(Icons.circle, size: 9, color: cor),
              const SizedBox(width: 6),
              Text(texto, style: TextStyle(color: cor, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}
