#!/usr/bin/env bash
# Evidencia: linha do tempo unificada (Parte E). Gera eventos concorrentes nas 3
# agencias e mescla os logs num unico fluxo ordenado por Lamport.
# Rodar no terminal do VSCode e tirar print -> evidencias/sprint1/linha-do-tempo.png
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

date
nota "Gera eventos independentes nas 3 agencias (varios cairao no mesmo timestamp"
nota "de Lamport = concorrentes) e roda o mesclar_logs.py."
reiniciar_agencias

titulo "Rodada 1: criar uma conta em cada agencia (cada uma vai para ts=1)"
req POST "$AG0/contas" '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'
req POST "$AG1/contas" '{"id":1,"nomeAluno":"Bia","saldoInicial":100}'
req POST "$AG2/contas" '{"id":2,"nomeAluno":"Caio","saldoInicial":100}'

titulo "Rodada 2: um deposito em cada agencia, disparados quase ao mesmo tempo (ts=2)"
curl -s -o /dev/null -X POST "$AG0/contas/0/depositar" -H "$CT" -d '{"valor":10}' &
curl -s -o /dev/null -X POST "$AG1/contas/1/depositar" -H "$CT" -d '{"valor":10}' &
curl -s -o /dev/null -X POST "$AG2/contas/2/depositar" -H "$CT" -d '{"valor":10}' &
wait

titulo "Rodada 3: transferencia entre agencias 0 -> 1 (mensagem: ao_enviar/ao_receber)"
req POST "$AG0/transferencias" '{"idOrigem":0,"idDestino":1,"valor":25}'

titulo "Rodada 4: mais um saque na Ag2 (sem relacao causal com o resto)"
req POST "$AG2/contas/2/sacar" '{"valor":5}'

titulo "LINHA DO TEMPO UNIFICADA (mesclar_logs.py)"
( cd "$AGDIR" && uv run python mesclar_logs.py )

nota "Procure dois eventos com o mesmo [Lamport N] vindos de agencias diferentes:"
nota "sao concorrentes (nenhum causou o outro). Compare a ordem por horaParede"
nota "com a ordem por Lamport - elas nao precisam coincidir."
