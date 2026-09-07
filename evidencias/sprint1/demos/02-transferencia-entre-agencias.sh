#!/usr/bin/env bash
# Evidencia: transferencia ENTRE agencias diferentes, com os logs das duas.
# Rodar no terminal do VSCode e tirar print -> evidencias/sprint1/transferencia-entre-agencias.png
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

date
nota "Transferencia ENTRE AGENCIAS: conta 0 (Agencia 0) -> conta 1 (Agencia 1)."
reiniciar_agencias

titulo "Setup: conta 0 (saldo 100) na Ag0, conta 1 (saldo 50) na Ag1"
req POST "$AG0/contas" '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'
req POST "$AG1/contas" '{"id":1,"nomeAluno":"Bia","saldoInicial":50}'

titulo "Transferencia: 30 da conta 0 (Ag0) para a conta 1 (Ag1)"
req POST "$AG0/transferencias" '{"idOrigem":0,"idDestino":1,"valor":30}'

titulo "Saldos depois (consultando cada agencia)"
req GET "$AG0/contas/0"
req GET "$AG1/contas/1"

mostrar_logs 0 1
nota "Ag0 registra TRANSFERENCIA_DEBITO e chama ao_enviar() (regra 2 de Lamport)."
nota "Ag1 recebe a mensagem e chama ao_receber() (regra 3): o timestamp do"
nota "TRANSFERENCIA_CREDITO_REMOTO = max(contador_local_da_Ag1, ts_recebido) + 1,"
nota "por isso o relogio da Ag1 'salta' para perto do valor da Ag0."
