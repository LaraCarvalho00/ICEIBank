# Evidências - Sprint 1

Prints de tela **reais** (não só código), com a data/hora visível para comprovar
execução recente. No macOS: `Cmd+Shift+4` para recortar uma área da tela.

Rode cada script no **terminal integrado do VSCode** (ele já imprime `date` na
primeira linha) e fotografe a saída. Os `.sh` ficam em `demos/`.

## Backend (terminal)

| Arquivo do print | Como gerar | O que precisa aparecer |
|---|---|---|
| `transferencia-local.png` | `./demos/01-transferencia-local.sh` | data + `Transferencia concluida (mesma agencia)` + saldos + log da Ag0 (DEBITO e CREDITO locais) |
| `transferencia-entre-agencias.png` | `./demos/02-transferencia-entre-agencias.sh` | data + `concluida (entre agencias)` + saldos nas 2 agências + logs da Ag0 **e** da Ag1 (CREDITO_REMOTO) |
| `falha-conhecida.png` | `./demos/03-falha-conhecida.sh` | data + Ag1 derrubada + resposta **HTTP 502** + saldo da origem **não revertido** + log `TRANSFERENCIA_FALHOU` |
| `linha-do-tempo.png` | `./demos/04-linha-do-tempo.sh` | data + saída do `mesclar_logs.py` com timestamps de Lamport repetidos entre agências |
| `auth-sem-token.png` | `./demos/05-auth-sem-token.sh` | data + requisições sem `Authorization` → **HTTP 401** |
| `auth-com-token.png` | `./demos/06-auth-com-token.sh` | data + login retornando `access_token` + operações com token → 200/201 |
| `auth-token-expirado.png` | `./demos/07-auth-token-expirado.sh` | data + token expirado → **HTTP 401** `Token expirado` |

## Frontend (navegador) - `npm run dev`, depois `http://localhost:5173`

Deixe as 3 agências rodando (`agencia/dev-agencias.sh start`). Nos prints do
navegador, deixe visível o relógio do sistema (canto da tela) ou um terminal com
`date` ao lado.

| Arquivo do print | Cena |
|---|---|
| `frontend-login.png` | tela de login preenchida **ou** logo após entrar (banner "Login efetuado.") + seletor de agência visível |
| `frontend-transferencia.png` | uma transferência feita pela interface, com o banner mostrando o resultado (fazer uma local e uma entre agências; pode ser 2 prints) |
| `frontend-erro.png` | um erro tratado na tela: tentar sacar mais que o saldo → banner vermelho "Saldo insuficiente." |

## Funcionalidade adicional

| Arquivo do print | Cena |
|---|---|
| `funcionalidade-adicional.png` | teste do endpoint `GET /contas/{id}/historico` (ver `demos/08-historico.sh`) |
