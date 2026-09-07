#!/usr/bin/env bash
# Sobe/derruba as 3 agências do ICEIBank de uma vez (conveniência de
# desenvolvimento). O roteiro sugere 3 terminais separados - este script é
# uma alternativa. Os logs de cada agência ficam em data/dev-agencia-N.out
#
#   ./dev-agencias.sh start     # sobe as 3
#   ./dev-agencias.sh stop      # derruba as 3
#   ./dev-agencias.sh stop 1    # derruba só a agência 1 (útil para a falha conhecida)
#   ./dev-agencias.sh status
#   ./dev-agencias.sh restart   # derruba tudo, espera as portas liberarem, sobe de novo
set -uo pipefail
cd "$(dirname "$0")"

PORTAS=(4000 4001 4002)

porta_livre() { ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

mata_porta() {
  local pids
  pids=$(lsof -tnP -iTCP:"$1" 2>/dev/null || true)
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
}

espera_portas_livres() {
  for _ in $(seq 1 40); do
    local ocupada=0
    for p in "${PORTAS[@]}"; do porta_livre "$p" || ocupada=1; done
    [ "$ocupada" = 0 ] && return 0
    sleep 0.25
  done
  return 1
}

sobe_uma() {
  local id="$1" porta=$((4000 + $1))
  if curl -sf "http://localhost:$porta/" >/dev/null 2>&1; then
    echo "agencia $id: ja no ar na porta $porta"; return 0
  fi
  porta_livre "$porta" || mata_porta "$porta"
  AGENCIA_ID="$id" nohup uv run uvicorn src.main:app --port "$porta" \
    > "data/dev-agencia-$id.out" 2>&1 &
  # espera esta agência responder
  for _ in $(seq 1 60); do
    curl -sf "http://localhost:$porta/" >/dev/null 2>&1 && { echo "agencia $id: no ar na porta $porta"; return 0; }
    sleep 0.25
  done
  echo "agencia $id: NAO subiu na porta $porta (ver data/dev-agencia-$id.out)"
  return 1
}

start() {
  local falhou=0
  for id in 0 1 2; do sobe_uma "$id" || falhou=1; done
  echo "docs: http://localhost:4000/docs  (4001, 4002)"
  return "$falhou"
}

stop() {
  local alvo="${1:-}"
  if [ -n "$alvo" ]; then
    mata_porta "$((4000 + alvo))"
    echo "agencia $alvo (porta $((4000 + alvo))) derrubada"
  else
    pkill -9 -f 'uvicorn src.main:app' 2>/dev/null || true
    for p in "${PORTAS[@]}"; do mata_porta "$p"; done
    espera_portas_livres && echo "todas as agencias derrubadas" || echo "aviso: alguma porta ainda ocupada"
  fi
}

status() {
  for id in 0 1 2; do
    local porta=$((4000 + id))
    if curl -sf "http://localhost:$porta/" >/dev/null 2>&1; then
      echo "agencia $id (porta $porta): NO AR"
    else
      echo "agencia $id (porta $porta): parada"
    fi
  done
}

case "${1:-}" in
  start) start ;;
  stop) stop "${2:-}" ;;
  restart) stop; espera_portas_livres; start ;;
  status) status ;;
  *) echo "uso: $0 {start|stop [id]|restart|status}"; exit 1 ;;
esac
