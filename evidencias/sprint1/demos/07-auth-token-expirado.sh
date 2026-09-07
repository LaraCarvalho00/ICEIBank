#!/usr/bin/env bash
# Evidencia Parte F, cenario (c): requisicao com token EXPIRADO -> HTTP 401.
# Print -> evidencias/sprint1/auth-token-expirado.png
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

date
nota "Cenario (c): token expirado e rejeitado com 401."
reiniciar_agencias

titulo "Setup (com token valido): cria a conta 0 na Ag0"
req POST "$AG0/contas" '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'

titulo "Gerando um JWT ja expirado (assinado com o segredo real)"
TOKEN_EXP="$(cd "$AGDIR" && uv run python gerar_token_expirado.py)"
echo "token expirado: ${TOKEN_EXP:0:40}..."

titulo "Requisicao com o token EXPIRADO -> espera 401 'Token expirado'"
printf '\033[0;90mGET %s\033[0m\n' "$AG0/contas/0"
curl -s -w '  [HTTP %{http_code}]\n' "$AG0/contas/0" -H "Authorization: Bearer $TOKEN_EXP"

titulo "Requisicao com um token INVALIDO (lixo) -> espera 401 'Token invalido'"
printf '\033[0;90mGET %s\033[0m\n' "$AG0/contas/0"
curl -s -w '  [HTTP %{http_code}]\n' "$AG0/contas/0" -H "Authorization: Bearer nao-e-um-token"

titulo "Para comparar: com um token VALIDO (recem obtido) -> 200"
req GET "$AG0/contas/0" || true

nota "O servidor so aceita o token enquanto a claim 'exp' esta no futuro; depois disso, 401."
