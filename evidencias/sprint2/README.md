# Evidências - Sprint 2

Prints **reais**, com `Get-Date` visível em algum terminal (as janelas abertas
pelo `dev-agencias.ps1` já mostram a data no topo). No Windows: `Win+Shift+S`
para recortar uma área da tela.

Prints capturados em 05/10/2026, numa única execução contínua (instância
CloudAMQP, RabbitMQ 4.3.5), gerados pelos scripts de `demos/`:

| Arquivo | Script | Cena |
|---|---|---|
| `transferencia-assincrona.png` | `demos/01-transferencia-assincrona.ps1` | transferência 0 → 1 via mensageria: `TRANSFERENCIA_PUBLICADA [3,0,0]` na Ag0 e `TRANSFERENCIA_CREDITO_REMOTO [3,2,0]` na Ag1 |
| `resiliencia-fila.png` (montagem das 3 partes abaixo) | `demos/02-resiliencia-fila.ps1` | Ag1 fora do ar → HTTP 200 → mensagem retida → Ag1 volta → `CREDITO_REMOTO_FALHOU` (conta não encontrada) |
| ├ `resiliencia-fila-1-agencia-fora.png` | | Ag1 parada, transferência 200, `fila-agencia-1 mensagens=1 consumidores=0` |
| ├ `resiliencia-fila-2-rabbitmq-manager.png` | | RabbitMQ Manager: `fila-agencia-1` com Ready = 1 (filas com selo DLX) |
| └ `resiliencia-fila-3-agencia-volta.png` | | Ag1 religada: mensagem entregue, `CREDITO_REMOTO_FALHOU [5,1,0]`, mensagem na `fila-agencia-1.dlq` |
| `funcionalidade-adicional.png` | `demos/03-dead-letter-queue.ps1` | `GET /mensagens-mortas` (motivo `rejected`) → conta recriada → `reprocessadas: 1` → saldo 20, DLQ vazia |
| `linha-do-tempo-causal.png` | `demos/04-linha-do-tempo-causal.ps1` | `mesclar_logs.py`: 18 pares concorrentes (ex.: `CRIAR_CONTA [0,1,0] ‖ CRIAR_CONTA [0,0,1]`) e publicação → crédito = `ANTES` |
| `frontend-regressao.png` | navegador | login JWT + transferência Ag0 → Ag1 pelo frontend ("publicada... entrega assincrona"); crédito aplicado na Ag1 (saldo 30, vetor `[7,5,0]`) |

## Como reproduzir com os scripts

Com `agencia/.env.local` configurado, a partir de `agencia/`:

```powershell
.\dev-agencias.ps1 stop
Remove-Item data\eventos-agencia-*.jsonl -ErrorAction SilentlyContinue
.\dev-agencias.ps1 start                                   # 3 janelas, uma por agência
..\evidencias\sprint2\demos\01-transferencia-assincrona.ps1
..\evidencias\sprint2\demos\02-resiliencia-fila.ps1        # pausa para o print antes de religar a Ag1
..\evidencias\sprint2\demos\03-dead-letter-queue.ps1
..\evidencias\sprint2\demos\04-linha-do-tempo-causal.ps1
```

`uv run python ver_filas.py` mostra a quantidade de mensagens em cada fila (a
mesma coluna *Ready* do RabbitMQ Manager).

## Passo a passo manual (sem os scripts)

Dá para fazer tudo numa sequência só, nesta ordem.

### 0. Preparação (uma vez)

- `agencia/.env.local` com `RABBITMQ_URL=amqps://...` (já criado).
- Abra um terminal PowerShell em `agencia/` (o "terminal de comandos") e
  zere os logs antigos com as agências paradas:

```powershell
cd agencia
.\dev-agencias.ps1 stop
Remove-Item data\eventos-agencia-*.jsonl -ErrorAction SilentlyContinue
.\dev-agencias.ps1 start        # abre 3 janelas, uma por agência
```

> Se o PowerShell bloquear o script por política de execução, use
> `powershell -ExecutionPolicy Bypass -File .\dev-agencias.ps1 start`.

No terminal de comandos, faça login e defina um atalho para as requisições
(use `127.0.0.1`, não `localhost`: no Windows o `localhost` tenta IPv6 primeiro
e cada chamada fica lenta):

```powershell
Get-Date
$login = Invoke-RestMethod -Method Post -Uri http://127.0.0.1:4000/auth/login -ContentType 'application/json' -Body '{"usuario":"lara","senha":"iceibank"}'
$H = @{ Authorization = "Bearer $($login.access_token)" }
function req($metodo, $caminho, $corpo) {
  Invoke-RestMethod -Method $metodo -Uri "http://127.0.0.1:$caminho" -Headers $H -ContentType 'application/json' -Body $corpo | ConvertTo-Json -Depth 6
}
```

### 1. `transferencia-assincrona.png`

Criação das contas (em agências diferentes, sem relação entre si; isso também
alimenta os pares concorrentes da Parte D):

```powershell
req POST 4000/contas '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'
req POST 4001/contas '{"id":1,"nomeAluno":"Bia","saldoInicial":0}'
req POST 4002/contas '{"id":2,"nomeAluno":"Caio","saldoInicial":50}'

req POST 4000/transferencias '{"idOrigem":0,"idDestino":1,"valor":30}'
req GET 4001/contas/1          # saldo 30: o crédito chegou pela fila
```

**Print:** terminal de comandos + janela da Agência 0 (`[Vetor [3, 0, 0]]
TRANSFERENCIA_PUBLICADA`) + janela da Agência 1 (`[Vetor [3, 2, 0]]
TRANSFERENCIA_CREDITO_REMOTO`).

### 2. `resiliencia-fila.png`

```powershell
Get-Date
.\dev-agencias.ps1 stop 1                                        # fecha a janela da Agência 1
req POST 4000/transferencias '{"idOrigem":0,"idDestino":1,"valor":20}'   # ainda responde 200
```

Agora abra o **RabbitMQ Manager** (painel do CloudAMQP → botão *RabbitMQ
Manager*) → aba **Queues**: `fila-agencia-1` com **Ready = 1**. Deixe essa aba
visível para o print.

```powershell
.\dev-agencias.ps1 start 1
```

Na janela nova da Agência 1 aparece, logo depois de `consumindo
fila-agencia-1`:

```
[Vetor [5, 1, 0]] CREDITO_REMOTO_FALHOU {... 'idConta': 1, 'valor': 20.0, ... 'motivo': 'conta nao encontrada'}
[mensageria] mensagem enviada para fila-agencia-1.dlq: conta 1 nao encontrada
```

**Print** (pode ser uma montagem de 2 recortes): o 200 com a Agência 1 parada +
a fila com 1 mensagem no Manager + o log da Agência 1 ao voltar.

### 3. `funcionalidade-adicional.png` (dead-letter queue)

```powershell
Get-Date
req GET 4001/mensagens-mortas                                     # a mensagem de 20, motivo "rejected"
req POST 4001/contas '{"id":1,"nomeAluno":"Bia","saldoInicial":0}'  # recria a conta perdida
req POST 4001/mensagens-mortas/reprocessar                         # "reprocessadas": 1
req GET 4001/contas/1                                              # saldo 20
```

No Manager, `fila-agencia-1.dlq` aparece com 1 mensagem antes do reprocessamento
e 0 depois.

### 4. `linha-do-tempo-causal.png`

```powershell
Get-Date
uv run python mesclar_logs.py --limite 10
```

(Se `uv` não for reconhecido: `python -m uv run python mesclar_logs.py --limite 10`.)

Precisa aparecer: a seção **"Pares de eventos CONCORRENTES"** com, por exemplo,
`[agencia-1] CRIAR_CONTA [0, 1, 0] || [agencia-2] CRIAR_CONTA [0, 0, 1]`; e a seção
**"publicacao -> credito remoto"** com `relacao=ANTES (OK, causal)`. O débito
`[2, 0, 0]` e o crédito `[3, 2, 0]` **não** estão entre os concorrentes.

### 5. `frontend-regressao.png`

Com as 3 agências no ar:

```powershell
cd ..\frontend
npm run dev        # http://localhost:5173
```

Entre com `lara` / `iceibank`, escolha a Agência 0 e faça uma transferência da
conta 0 para a conta 1. O banner mostra "Transferencia publicada para a agencia
de destino (entrega assincrona)". Depois troque para a Agência 1 e consulte a
conta 1: o saldo aumentou. Deixe o relógio do sistema visível no print.
