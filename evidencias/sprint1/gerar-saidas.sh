#!/usr/bin/env bash
# Roda os 8 scripts de demonstração em sequência e salva a saída COMPLETA de
# cada um (com a data no topo) em evidencias/sprint1/saidas/<n>.txt.
#
# Use quando quiser gerar todas as evidências de uma vez. Depois, para cada
# print: abra o .txt correspondente no VSCode (ou rode `cat` no terminal) e
# tire o print. Ou rode o .sh individual ao vivo - a data no topo é real.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p saidas

DEMOS=(
  "01-transferencia-local"
  "02-transferencia-entre-agencias"
  "03-falha-conhecida"
  "04-linha-do-tempo"
  "05-auth-sem-token"
  "06-auth-com-token"
  "07-auth-token-expirado"
  "08-historico"
)

for nome in "${DEMOS[@]}"; do
  echo "==> gerando saidas/${nome}.txt"
  # remove os codigos de cor ANSI para o arquivo ficar limpo
  ./demos/"${nome}.sh" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "saidas/${nome}.txt"
done

# deixa as 3 agencias no ar ao final
( cd ../../agencia && ./dev-agencias.sh start >/dev/null 2>&1 || true )

echo
echo "Pronto. Arquivos em evidencias/sprint1/saidas/:"
ls -1 saidas/
