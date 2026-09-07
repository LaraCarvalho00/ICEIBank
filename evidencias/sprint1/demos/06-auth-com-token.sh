#!/usr/bin/env bash
# Evidencia Parte F, cenario (b): requisicao COM token valido -> funciona normal.
# Print -> evidencias/sprint1/auth-com-token.png
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

date
nota "Cenario (b): com um token valido, as operacoes funcionam normalmente."
reiniciar_agencias

titulo "Login: POST /auth/login (usuario 'lara')"
curl -s -X POST "$AG0/auth/login" -H "$CT" -d '{"usuario":"lara","senha":"iceibank"}'
echo
nota "O token acima ja foi capturado pelo script (variavel TOKEN) e vai no header das proximas chamadas."

titulo "Com token: criar conta 0, depositar, sacar"
req POST "$AG0/contas" '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'
req POST "$AG0/contas/0/depositar" '{"valor":50}'
req POST "$AG0/contas/0/sacar" '{"valor":30}'
req GET  "$AG0/contas/0"

titulo "Com token: conta 1 na Ag1 e transferencia entre agencias 0 -> 1"
req POST "$AG1/contas" '{"id":1,"nomeAluno":"Bia","saldoInicial":0}'
req POST "$AG0/transferencias" '{"idOrigem":0,"idDestino":1,"valor":20}'
req GET  "$AG1/contas/1"

nota "A transferencia entre agencias funcionou: a Ag0 chamou o creditar-remoto da"
nota "Ag1 usando um token de escopo 'interno' (nao o token da 'lara')."
