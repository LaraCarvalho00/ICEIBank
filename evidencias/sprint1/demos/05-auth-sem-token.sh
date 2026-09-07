#!/usr/bin/env bash
# Evidencia Parte F, cenario (a): requisicao SEM token -> HTTP 401.
# Print -> evidencias/sprint1/auth-sem-token.png
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

date
nota "Cenario (a): rotas de conta protegidas rejeitam requisicao sem token (401)."
reiniciar_agencias

titulo "Setup (com token): cria a conta 0 na Ag0"
req POST "$AG0/contas" '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'

titulo "Agora SEM token: consultar saldo -> espera 401"
req_sem_token GET "$AG0/contas/0"

titulo "SEM token: depositar -> espera 401"
req_sem_token POST "$AG0/contas/0/depositar" '{"valor":10}'

titulo "SEM token: criar conta -> espera 401"
req_sem_token POST "$AG0/contas" '{"id":3,"nomeAluno":"Rui","saldoInicial":0}'

titulo "SEM token: transferencia -> espera 401"
req_sem_token POST "$AG0/transferencias" '{"idOrigem":0,"idDestino":3,"valor":10}'

nota "Todas as rotas que leem ou alteram contas exigem Authorization: Bearer <token>."
