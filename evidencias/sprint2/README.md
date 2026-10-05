# Evidências - Sprint 2

Prints de tela **reais**, capturados em 05/10/2026 numa única execução contínua
(as 3 agências rodando localmente, RabbitMQ 4.3.5 no CloudAMQP). Cada print
tem a data/hora visível: `Get-Date` no topo do terminal, `Fim da demo - <data>`
no final ou o relógio do Windows.

Estado inicial: logs `data/eventos-*.jsonl` apagados e filas vazias. As contas
usadas são: conta 0 (Ana, Agência 0), conta 1 (Bia, Agência 1) e conta 2
(Caio, Agência 2), lembrando que `id_conta % 3` define a agência.

| Arquivo do print | Cena | O que precisa aparecer |
|---|---|---|
| `transferencia-assincrona.png` | Contas criadas nas 3 agências; transferência de 30 da conta 0 (Ag0) para a conta 1 (Ag1), ambas no ar | `HTTP 200` "Transferencia publicada... (entrega assincrona)"; saldos 70 e 30; log da Ag0 com `TRANSFERENCIA_PUBLICADA [3, 0, 0]` e log da Ag1 com `TRANSFERENCIA_CREDITO_REMOTO [3, 2, 0]` (regra 3: `max([0,1,0], [3,0,0]) = [3,1,0]`, +1 na própria posição) |
| `resiliencia-fila.png` | Montagem de 3 partes, de cima para baixo: (1) Ag1 derrubada e transferência de 20 para a conta 1; (2) Ag1 religada; (3) RabbitMQ Manager com a Ag1 fora do ar | (1) `HTTP 200` mesmo sem consumidor e `fila-agencia-1 mensagens=1 consumidores=0`; (2) a mensagem é entregue quando a Ag1 volta, mas a conta 1 sumiu no reinício: `CREDITO_REMOTO_FALHOU [5, 1, 0]` "conta nao encontrada", e a mensagem vai para `fila-agencia-1.dlq`; (3) `fila-agencia-1` com *Ready* = 1 e o selo **DLX** nas filas principais |
| `funcionalidade-adicional.png` | Dead-letter queue: listar a DLQ, recriar a conta 1 e reprocessar | `GET /mensagens-mortas` com a mensagem de 20 e `"motivo":"rejected"`; conta 1 recriada (`HTTP 201`); `"reprocessadas":1`; conta 1 com saldo 20; DLQ vazia |
| `linha-do-tempo-causal.png` | `uv run python mesclar_logs.py --limite 10` sobre os logs das 3 agências | Linha do tempo com os vetores; 18 pares **concorrentes** (ex.: `CRIAR_CONTA [0, 1, 0] ‖ CRIAR_CONTA [0, 0, 1]`, contas criadas em agências sem nenhuma mensagem entre elas); pares publicação → crédito com `relacao=ANTES (OK, causal)`; o débito `[2, 0, 0]` e o crédito `[3, 2, 0]` **não** aparecem entre os concorrentes |
| `frontend-regressao.png` | Regressão do Sprint 1: login `lara` pelo frontend e transferência de 10 da conta 0 (Ag0) para a conta 1 (Ag1) | Banner "Transferencia publicada para a agencia de destino (entrega assincrona). Saldo da origem: R$ 40.00"; relógio do Windows visível. O crédito foi aplicado na Ag1 (saldo 30, vetor `[7, 5, 0]` no log) |

As respostas que interpretam esses prints estão em `RESPOSTAS.md` (Sprint 2,
Partes C e D, e funcionalidade adicional).
