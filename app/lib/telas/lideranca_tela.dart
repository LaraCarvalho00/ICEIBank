import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../modelos.dart';
import '../servicos/estado_app.dart';
import '../servicos/monitor_lideranca.dart';
import '../widgets/comum.dart';
import '../widgets/tema.dart';

/// Painel de liderança: quem é a líder agora, o estado de cada agência e o
/// histórico de transições (failover visível na tela).
class LiderancaTela extends StatelessWidget {
  const LiderancaTela({super.key, required this.monitor});

  final MonitorLideranca monitor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) => RefreshIndicator(
        onRefresh: monitor.consultar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CartaoLider(monitor: monitor),
            const SizedBox(height: 16),
            const Text('Agencias', style: TextStyle(color: Cores.textoSuave)),
            const SizedBox(height: 8),
            for (var i = 0; i < ConfigApp.numeroAgencias; i++)
              _CartaoAgencia(id: i, estado: monitor.estados[i], lider: monitor.lider),
            const SizedBox(height: 16),
            const Text('Historico (visto pelo app)', style: TextStyle(color: Cores.textoSuave)),
            const SizedBox(height: 8),
            if (monitor.eventos.isEmpty)
              const Text('Sem eventos ainda.', style: TextStyle(color: Cores.textoFraco)),
            for (final e in monitor.eventos) _LinhaEvento(evento: e),
          ],
        ),
      ),
    );
  }
}

class _CartaoLider extends StatelessWidget {
  const _CartaoLider({required this.monitor});

  final MonitorLideranca monitor;

  @override
  Widget build(BuildContext context) {
    final (cor, icone, titulo, sub) = switch (monitor.situacao) {
      SituacaoCluster.estavel => (
          Cores.destaque,
          Icons.workspace_premium,
          'Agencia ${monitor.lider}',
          _desde(monitor.estados[monitor.lider!]?.liderDesde),
        ),
      SituacaoCluster.liderSemResposta => (
          Cores.alerta,
          Icons.portable_wifi_off,
          'Lider ${monitor.liderReconhecido} nao responde',
          'As agencias ainda a reconhecem; o heartbeat delas vai convocar uma nova eleicao.',
        ),
      SituacaoCluster.emEleicao => (
          Cores.alerta,
          Icons.how_to_vote_outlined,
          'Eleicao em andamento',
          'As agencias ainda nao convergiram para a mesma lider.',
        ),
      SituacaoCluster.foraDoAr => (
          Cores.erro,
          Icons.cloud_off,
          'Nenhuma agencia responde',
          'Verifique se as agencias estao no ar.',
        ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icone, size: 44, color: cor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LIDER ATUAL', style: TextStyle(color: Cores.textoSuave, fontSize: 12)),
                  Text(titulo,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: cor)),
                  const SizedBox(height: 4),
                  Text(sub, style: const TextStyle(color: Cores.textoSuave)),
                  if (monitor.ultimaConsulta != null)
                    Text('Atualizado as ${formatarHora(monitor.ultimaConsulta!)} (a cada 2 s)',
                        style: const TextStyle(color: Cores.textoFraco, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _desde(DateTime? t) {
    if (t == null) return '';
    final s = DateTime.now().difference(t.toLocal()).inSeconds;
    return 'Lider desde ${formatarHora(t)} (ha ${s < 0 ? 0 : s} s)';
  }
}

class _CartaoAgencia extends StatelessWidget {
  const _CartaoAgencia({required this.id, required this.estado, required this.lider});

  final int id;
  final EstadoAgencia? estado;
  final int? lider;

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final noAr = e != null;
    final ehLider = noAr && e.souLider;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (noAr ? Cores.destaque : Cores.erro).withValues(alpha: 0.18),
          child: Icon(
            ehLider ? Icons.workspace_premium : (noAr ? Icons.dns_outlined : Icons.power_off),
            color: noAr ? Cores.destaque : Cores.erro,
          ),
        ),
        title: Text('Agencia $id · porta ${ConfigApp.portaBase + id}'),
        subtitle: Text(
          !noAr
              ? 'Fora do ar'
              : [
                  e.emEleicao ? 'em eleicao' : 'reconhece lider: ${e.liderAtual ?? '-'}',
                  'vetor ${vetorTexto(e.vetor)}',
                  '${e.latenciaMs} ms',
                ].join(' · '),
          style: TextStyle(color: noAr ? Cores.textoSuave : Cores.erro),
        ),
        trailing: ehLider
            ? const Chip(label: Text('LIDER'), visualDensity: VisualDensity.compact)
            : null,
      ),
    );
  }
}

class _LinhaEvento extends StatelessWidget {
  const _LinhaEvento({required this.evento});

  final EventoLider evento;

  @override
  Widget build(BuildContext context) {
    final cor = switch (evento.tipo) {
      TipoEventoLider.info => Cores.textoSuave,
      TipoEventoLider.alerta => Cores.alerta,
      TipoEventoLider.failover => Cores.destaque,
      TipoEventoLider.retomada => Cores.info,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatarHora(evento.quando),
              style: const TextStyle(color: Cores.textoFraco, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 12),
          Expanded(child: Text(evento.texto, style: TextStyle(color: cor))),
        ],
      ),
    );
  }
}
