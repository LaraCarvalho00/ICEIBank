#!/usr/bin/env bash
# Evidencia: a falha conhecida (Parte D) - agencia de destino cai no meio da
# transferencia. Mostra a resposta 502 e o log da inconsistencia.
# Rodar no terminal do VSCode e tirar print -> evidencias/sprint1/falha-conhecida.png
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

date
nota "Falha conhecida: a Agencia de destino e derrubada no meio da transferencia."
reiniciar_agencias

titulo "Setup: conta 0 (saldo 100) na Ag0, conta 1 (saldo 50) na Ag1"
req POST "$AG0/contas" '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'
req POST "$AG1/contas" '{"id":1,"nomeAluno":"Bia","saldoInicial":50}'

titulo "Saldo da conta 0 ANTES da falha"
req GET "$AG0/contas/0"

titulo "Derrubando a Agencia 1 (destino)"
( cd "$AGDIR" && ./dev-agencias.sh stop 1 )
sleep 1
( cd "$AGDIR" && ./dev-agencias.sh status )

titulo "Transferencia de 25 (conta 0 -> conta 1) com a Ag1 FORA DO AR -> espera HTTP 502"
req POST "$AG0/transferencias" '{"idOrigem":0,"idDestino":1,"valor":25}'

titulo "Saldo da conta 0 DEPOIS da falha"
req GET "$AG0/contas/0"
nota "O debito de 25 foi aplicado e NAO foi revertido: 100 -> 75. O dinheiro"
nota "'sumiu' temporariamente (a Ag1 nunca creditou)."

mostrar_logs 0
nota "O evento TRANSFERENCIA_FALHOU registra a inconsistencia, sem escondê-la."
nota "Corrigir isso sob falha (atomicidade) e o objetivo do Sprint 4 (2PC / Saga)."

titulo "Subindo a Agencia 1 de volta"
( cd "$AGDIR" && ./dev-agencias.sh start )
