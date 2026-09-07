#!/usr/bin/env bash
# Evidencia da FUNCIONALIDADE ADICIONAL (secao 2.1): historico de transacoes por conta.
# Print -> evidencias/sprint1/funcionalidade-adicional.png
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

date
nota "Funcionalidade adicional: GET /contas/{id}/historico?limite=N"
reiniciar_agencias

titulo "Gera movimento na conta 0 (deposito, saque, transferencia entre agencias e local)"
req POST "$AG0/contas" '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'
req POST "$AG1/contas" '{"id":1,"nomeAluno":"Bia","saldoInicial":0}'
req POST "$AG0/contas" '{"id":3,"nomeAluno":"Rui","saldoInicial":0}'
req POST "$AG0/contas/0/depositar" '{"valor":50}'
req POST "$AG0/contas/0/sacar" '{"valor":20}'
req POST "$AG0/transferencias" '{"idOrigem":0,"idDestino":1,"valor":30}'   # entre agencias
req POST "$AG0/transferencias" '{"idOrigem":0,"idDestino":3,"valor":10}'   # local

titulo "Historico completo da conta 0 (todos os eventos que a envolvem)"
req GET "$AG0/contas/0/historico"

titulo "Historico da conta 0 limitado aos 3 ultimos (?limite=3)"
req GET "$AG0/contas/0/historico?limite=3"

titulo "Historico de conta inexistente -> 404"
req GET "$AG0/contas/99/historico"

titulo "Sem token -> 401 (o endpoint tambem e protegido)"
req_sem_token GET "$AG0/contas/0/historico"

nota "O historico e montado a partir do log .jsonl da agencia, filtrando por"
nota "id/idConta/idOrigem/idDestino e ordenando por timestamp de Lamport."
