#!/usr/bin/env bash
# Helpers compartilhados pelos scripts de demonstração do Sprint 1.
# Cada script de demo dá `source ./lib.sh`.
set -euo pipefail

AG0=http://localhost:4000
AG1=http://localhost:4001
AG2=http://localhost:4002
CT='Content-Type: application/json'

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
AGDIR="$RAIZ/agencia"

titulo() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }
nota()   { printf '\033[0;33m# %s\033[0m\n' "$1"; }

# Token JWT usado pelas requisicoes das demos (login como 'lara').
TOKEN=""
obter_token() {
  TOKEN=$(curl -s -X POST "$AG0/auth/login" -H "$CT" \
    -d '{"usuario":"lara","senha":"iceibank"}' \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
  [ -n "$TOKEN" ] || { echo "ERRO: nao consegui obter token de login"; exit 1; }
}

# Reinicia as 3 agências com estado limpo (contas em memória zeradas, logs
# apagados). Deixa a demonstração 100%% reproduzível para o print.
reiniciar_agencias() {
  titulo "Reiniciando as 3 agencias (estado limpo)"
  ( cd "$AGDIR" && ./dev-agencias.sh stop >/dev/null 2>&1 || true )
  rm -f "$AGDIR"/data/eventos-agencia-0.jsonl \
        "$AGDIR"/data/eventos-agencia-1.jsonl \
        "$AGDIR"/data/eventos-agencia-2.jsonl
  if ! ( cd "$AGDIR" && ./dev-agencias.sh start ); then
    echo "ERRO: agencias nao subiram"; exit 1
  fi
  obter_token
}

# req METODO URL [JSON]  -> envia o token JWT (se houver) no Authorization
req() {
  local metodo="$1" url="$2" body="${3:-}"
  printf '\033[0;90m%s %s\033[0m\n' "$metodo" "$url"
  local auth=()
  [ -n "$TOKEN" ] && auth=(-H "Authorization: Bearer $TOKEN")
  if [ -n "$body" ]; then
    curl -s -w '  [HTTP %{http_code}]\n' -X "$metodo" "$url" "${auth[@]}" -H "$CT" -d "$body"
  else
    curl -s -w '  [HTTP %{http_code}]\n' -X "$metodo" "$url" "${auth[@]}"
  fi
}

# req_sem_token METODO URL [JSON]  -> nao envia Authorization (para testar 401)
req_sem_token() {
  local metodo="$1" url="$2" body="${3:-}"
  printf '\033[0;90m%s %s  (sem Authorization)\033[0m\n' "$metodo" "$url"
  if [ -n "$body" ]; then
    curl -s -w '  [HTTP %{http_code}]\n' -X "$metodo" "$url" -H "$CT" -d "$body"
  else
    curl -s -w '  [HTTP %{http_code}]\n' -X "$metodo" "$url"
  fi
}

mostrar_logs() {
  for id in "$@"; do
    titulo "Log da Agencia $id  (data/eventos-agencia-$id.jsonl)"
    cat "$AGDIR/data/eventos-agencia-$id.jsonl" 2>/dev/null || echo "(vazio)"
  done
}
