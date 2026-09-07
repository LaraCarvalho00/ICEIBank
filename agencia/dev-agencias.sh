#!/usr/bin/env bash
# Sobe/derruba as 3 agências do ICEIBank de uma vez (conveniência de
# desenvolvimento). O roteiro sugere 3 terminais separados - este script é
# uma alternativa. Os logs de cada agência ficam em data/dev-agencia-N.out
#
#   ./dev-agencias.sh start     # sobe as 3
#   ./dev-agencias.sh stop      # derruba as 3
#   ./dev-agencias.sh stop 1    # derruba só a agência 1 (útil para a falha conhecida)
#   ./dev-agencias.sh status
set -euo pipefail
cd "$(dirname "$0")"

start() {
  for id in 0 1 2; do
    porta=$((4000 + id))
    if lsof -ti tcp:"$porta" >/dev/null 2>&1; then
      echo "agencia $id: porta $porta ja em uso, pulando"
      continue
    fi
    AGENCIA_ID=$id nohup uv run uvicorn src.main:app --port "$porta" \
      > "data/dev-agencia-$id.out" 2>&1 &
    echo "agencia $id: subindo na porta $porta (pid $!)"
  done
  echo "docs: http://localhost:4000/docs  (4001, 4002)"
}

stop() {
  alvo="${1:-}"
  if [ -n "$alvo" ]; then
    porta=$((4000 + alvo))
    lsof -ti tcp:"$porta" | xargs -r kill && echo "agencia $alvo (porta $porta) derrubada"
  else
    pkill -f 'uvicorn src.main:app' && echo "todas as agencias derrubadas" || echo "nada rodando"
  fi
}

status() {
  for id in 0 1 2; do
    porta=$((4000 + id))
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
  status) status ;;
  *) echo "uso: $0 {start|stop [id]|status}"; exit 1 ;;
esac
