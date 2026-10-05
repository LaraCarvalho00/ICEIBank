# Evidências - Sprint 2

Prints **reais**, com `Get-Date` visível em algum terminal (as janelas abertas
pelo `dev-agencias.ps1` já mostram a data no topo). No Windows: `Win+Shift+S`
para recortar uma área da tela.

| Arquivo | Cena |
|---|---|
| `transferencia-assincrona.png` | transferência 0 → 1 via mensageria, com as janelas da Agência 0 **e** da Agência 1 visíveis (`TRANSFERENCIA_PUBLICADA` numa, `TRANSFERENCIA_CREDITO_REMOTO` na outra) |
| `resiliencia-fila.png` | Agência 1 fora do ar → transferência responde 200 → mensagem retida em `fila-agencia-1` (RabbitMQ Manager) → Agência 1 volta → `CREDITO_REMOTO_FALHOU` (conta não encontrada) |
| `linha-do-tempo-causal.png` | saída do `mesclar_logs.py` com pares concorrentes e a seção "publicacao -> credito remoto ... ANTES" |
| `funcionalidade-adicional.png` | `GET /mensagens-mortas` mostrando a mensagem na DLQ → recriar a conta → `POST /mensagens-mortas/reprocessar` → saldo creditado |
| `frontend-regressao.png` | uma operação feita pelo frontend (ex.: transferência entre agências) mostrando que login/JWT e frontend seguem funcionando |

Dá para fazer tudo numa sequência só, nesta ordem.

## 0. Preparação (uma vez)

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

## 1. `transferencia-assincrona.png`

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

## 2. `resiliencia-fila.png`

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

## 3. `funcionalidade-adicional.png` (dead-letter queue)

```powershell
Get-Date
req GET 4001/mensagens-mortas                                     # a mensagem de 20, motivo "rejected"
req POST 4001/contas '{"id":1,"nomeAluno":"Bia","saldoInicial":0}'  # recria a conta perdida
req POST 4001/mensagens-mortas/reprocessar                         # "reprocessadas": 1
req GET 4001/contas/1                                              # saldo 20
```

No Manager, `fila-agencia-1.dlq` aparece com 1 mensagem antes do reprocessamento
e 0 depois.

## 4. `linha-do-tempo-causal.png`

```powershell
Get-Date
uv run python mesclar_logs.py --limite 10
```

(Se `uv` não for reconhecido: `python -m uv run python mesclar_logs.py --limite 10`.)

Precisa aparecer: a seção **"Pares de eventos CONCORRENTES"** com, por exemplo,
`[agencia-1] CRIAR_CONTA [0, 1, 0] || [agencia-2] CRIAR_CONTA [0, 0, 1]`; e a seção
**"publicacao -> credito remoto"** com `relacao=ANTES (OK, causal)`. O débito
`[2, 0, 0]` e o crédito `[3, 2, 0]` **não** estão entre os concorrentes.

## 5. `frontend-regressao.png`

Com as 3 agências no ar:

```powershell
cd ..\frontend
npm run dev        # http://localhost:5173
```

Entre com `lara` / `iceibank`, escolha a Agência 0 e faça uma transferência da
conta 0 para a conta 1. O banner mostra "Transferencia publicada para a agencia
de destino (entrega assincrona)". Depois troque para a Agência 1 e consulte a
conta 1: o saldo aumentou. Deixe o relógio do sistema visível no print.
