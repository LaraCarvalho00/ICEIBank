#!/usr/bin/env bash
# Evidencia: transferencia DENTRO da mesma agencia.
# Rodar no terminal do VSCode e tirar print -> evidencias/sprint1/transferencia-local.png
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

date
nota "Transferencia LOCAL: conta 0 -> conta 3, ambas na Agencia 0 (3 % 3 == 0)."
reiniciar_agencias

titulo "Setup: conta 0 (saldo 100) e conta 3 (saldo 0), ambas na Agencia 0"
req POST "$AG0/contas" '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'
req POST "$AG0/contas" '{"id":3,"nomeAluno":"Rui","saldoInicial":0}'

titulo "Transferencia: 20 da conta 0 para a conta 3"
req POST "$AG0/transferencias" '{"idOrigem":0,"idDestino":3,"valor":20}'

titulo "Saldos depois"
req GET "$AG0/contas/0"
req GET "$AG0/contas/3"

mostrar_logs 0
nota "TRANSFERENCIA_DEBITO e TRANSFERENCIA_CREDITO sao dois eventos LOCAIS"
nota "consecutivos (evento_local): timestamps de Lamport 3 e 4. Nao ha ao_enviar/ao_receber."
