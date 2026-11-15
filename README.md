# ICEIBank

Banco simplificado dividido em agências, desenvolvido ao longo de 4 sprints na
disciplina de **Laboratório de Desenvolvimento de Aplicações Móveis e
Distribuídas**.

- Sprint 1: API REST / MVC + Relógio lógico de Lamport + Autenticação JWT + Frontend web.
- Sprint 2: Mensageria / Pub-Sub (RabbitMQ) + Relógio vetorial.
- **Sprint 3 (atual):** App Flutter + Consenso (eleição de líder, Bully) +
  sincronização offline-first.
- Sprint 4: Containers + Transações distribuídas (2PC / Saga).

## Stack

| Camada     | Tecnologia                                  |
|------------|---------------------------------------------|
| Backend    | Python 3.12 + FastAPI + Uvicorn             |
| Mensageria | RabbitMQ (CloudAMQP) via `pika`             |
| Auth       | JWT (PyJWT)                                 |
| Frontend   | React + Vite                                |
| App mobile | Flutter 3.50 (`http`, `shared_preferences`, `connectivity_plus`) |
| Agência -> agência (eleição) | HTTP via `httpx`, timeout de 1 s |
| Testes     | `verificar_vetorial.py`, `historico_lideranca.py`, `app/test/integracao_test.dart`, `curl`, `/docs` |

## Arquitetura

Cada **agência** é uma partição independente de contas. O mesmo código roda 3
vezes, com identidades diferentes (`AGENCIA_ID` = 0, 1, 2). A agência
responsável por uma conta é `id_conta % 3`.

Transferência entre agências (Sprint 2): a agência de origem debita localmente
e **publica** um evento na exchange `iceibank.eventos` (tipo `topic`) com a
routing key `agencia.<destino>.creditar`. A agência de destino **consome** da
sua fila durável `fila-agencia-<id>` quando estiver no ar. Cada evento leva um
**relógio vetorial** de 3 posições.

Eleição de líder (Sprint 3): as agências elegem uma líder com o **algoritmo do
Valentão (Bully)**: vence o maior ID vivo. Cada agência roda um **heartbeat**
que consulta a líder a cada 2 s e, depois de 2 falhas seguidas, convoca uma
nova eleição sozinha. As mensagens de eleição são HTTP entre agências
(`POST /bully/eleicao`, `POST /bully/coordenador`, token de escopo `interno`)
e levam o vetor anexado.

Offline-first (Sprint 3): cada conta guarda a sua **versão**, o vetor da última
escrita. O app Flutter guarda essa versão junto do saldo em cache, enfileira as
operações feitas sem conexão e, ao reconectar, envia cada uma com o
`vetorBase` para `POST /sync/operacoes`. O servidor compara os vetores:
`IGUAIS` aplica; qualquer outra relação é escrita concorrente e responde
**409** com o estado do servidor (depósitos são mesclados, ver funcionalidade
adicional).

```
agencia/
├── src/
│   ├── main.py                       # entrypoint FastAPI + inicia o consumidor RabbitMQ
│   ├── config.py                     # particionamento e portas
│   ├── estado.py                     # estado em memória (contas, relógio, log)
│   ├── esquemas.py                   # modelos Pydantic (requisições e mensagem de crédito)
│   ├── rotas.py                      # mapeia rotas -> controllers
│   ├── seguranca.py                  # JWT (escopos usuario e interno)
│   ├── controllers/                  # regra de negócio (MVC: Controller)
│   │   ├── contas_controller.py           # + versão (vetor) de cada conta
│   │   ├── transferencias_controller.py   # publica / processa créditos remotos
│   │   ├── bully_controller.py            # Sprint 3: /bully/*
│   │   ├── sincronizacao_controller.py    # Sprint 3: /sync/operacoes (+ extra)
│   │   ├── historico_controller.py        # extra do Sprint 1
│   │   └── mensagens_mortas_controller.py # extra do Sprint 2 (DLQ)
│   └── services/
│       ├── bully.py                  # Sprint 3: algoritmo do Valentão
│       ├── heartbeat.py              # Sprint 3: detecção de queda da líder
│       ├── relogio_vetorial.py       # relógio vetorial + comparar()
│       ├── mensageria.py             # RabbitMQ: topologia, publicar, assinar, DLQ
│       └── registro_eventos.py       # log de eventos (.jsonl)
├── data/                             # logs gerados em runtime (não versionado)
├── historico_lideranca.py            # Sprint 3: linha do tempo de lideranças
├── mesclar_logs.py                   # linha do tempo causal + pares concorrentes
├── verificar_vetorial.py             # teste isolado do relógio vetorial
└── .env.local                        # RABBITMQ_URL (NÃO versionado)

app/                                  # Sprint 3: app Flutter (ver app/README.md)
frontend/                             # Sprint 1: frontend web (React)
```

## Como rodar

Pré-requisitos: Python 3.12, [uv](https://docs.astral.sh/uv/) e uma instância
RabbitMQ. Usamos o plano gratuito *Little Lemur* do
[CloudAMQP](https://www.cloudamqp.com/). Node 20+ para o frontend.

1. Copie a **AMQP URL** da instância e grave em `agencia/.env.local`, que fica
   fora do Git porque contém a senha:

   ```
   RABBITMQ_URL=amqps://usuario:senha@host.cloudamqp.com/vhost
   ```

   Alternativa do roteiro: definir `$env:RABBITMQ_URL="amqps://..."` em cada
   terminal. A variável de ambiente tem prioridade sobre o arquivo.

2. Instale as dependências e suba as agências, um terminal PowerShell por
   agência, todos em `agencia/`:

   ```powershell
   uv sync                        # uma vez: cria .venv e instala dependências
   $env:AGENCIA_ID=0; uv run uvicorn src.main:app --port 4000
   $env:AGENCIA_ID=1; uv run uvicorn src.main:app --port 4001
   $env:AGENCIA_ID=2; uv run uvicorn src.main:app --port 4002
   ```

   No macOS/Linux, `./dev-agencias.sh start` sobe as 3 de uma vez
   (`stop [id]`, `status`, `restart`).

Documentação interativa de cada agência em `http://127.0.0.1:400X/docs`.
Exchanges e filas aparecem no **RabbitMQ Manager** (botão no painel do
CloudAMQP).

### Autenticação (JWT)

As rotas de conta, `/transferencias` e `/mensagens-mortas` exigem
`Authorization: Bearer <token>`. Obtenha um token em `POST /auth/login`
(usuários de teste: `lara` / `allan`, senha `iceibank`):

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:4000/auth/login `
  -ContentType 'application/json' -Body '{"usuario":"lara","senha":"iceibank"}'
```

Variáveis de ambiente opcionais: `JWT_SEGREDO` (troque em produção),
`JWT_EXPIRACAO_MIN` (padrão 30), `SENHA_LARA`, `SENHA_ALLAN`, `OFFSET` (portas).
O crédito vindo de outra agência não passa mais por HTTP: chega pelo RabbitMQ
(ver `RESPOSTAS.md` - Sprint 2, Parte C, pergunta 3).

### Relógio vetorial e linha do tempo causal

```powershell
cd agencia
uv run python verificar_vetorial.py          # teste isolado das 3 regras
uv run python mesclar_logs.py                # linha do tempo + pares concorrentes
```

### Eleição de líder e failover (Sprint 3)

```bash
curl -s localhost:4000/bully/lider          # quem a agência 0 reconhece como líder
./dev-agencias.sh stop 2                    # derruba a líder (maior ID)
# ~4 s depois: LIDER_INALCANCAVEL + nova eleição -> líder 1
./dev-agencias.sh start                     # a 2 volta e retoma a liderança (bully)
uv run python historico_lideranca.py        # mandatos, tempo sem líder, verificação causal
```

Variáveis opcionais: `HEARTBEAT_INTERVALO` (s, padrão 2) e `HEARTBEAT_FALHAS`
(padrão 2).

### Sincronização offline-first (Sprint 3)

`POST /sync/operacoes` (JWT) recebe
`{"idOperacao", "idConta", "tipo": "DEPOSITO"|"SAQUE", "valor", "vetorBase"}`:

| Relação `vetorBase` x versão da conta | Resposta |
|---|---|
| `IGUAIS` | 200 `APLICADA` |
| `ANTES` + depósito | 200 `MESCLADA` (funcionalidade adicional) |
| `ANTES` + saque | **409** `CONFLITO` + estado do servidor + escritas concorrentes |
| `DEPOIS` / `CONCORRENTES` (agência reiniciou) | **409** `CONFLITO` |
| `idOperacao` repetida | 200 `JA_APLICADA` (idempotente) |

`MESCLAR_DEPOSITOS=0` desliga a mesclagem, e então depósitos também caem no 409.

### App Flutter (Sprint 3)

```bash
cd app && flutter pub get && flutter run -d chrome   # ou macos / emulador
```

Detalhes (host por plataforma, testes) em `app/README.md`.

### Frontend

Com as 3 agências já rodando:

```bash
cd frontend
npm install
npm run dev            # http://localhost:5173
```

Login com `lara` / `iceibank`. O seletor "Agência de entrada" no topo escolhe
qual das 3 agências responde (cada agência só conhece as contas sob sua
responsabilidade: `id_conta % 3`). Uma transferência entre agências agora
responde "publicada (entrega assíncrona)": o crédito aparece na outra agência
logo em seguida. MVC do frontend: ver `RESPOSTAS.md` - Sprint 1, Parte G.

## Funcionalidades adicionais (seção 2.1)

- **Sprint 3 - Mesclagem automática de depósitos offline concorrentes:** na
  sincronização, um depósito cujo `vetorBase` ficou para trás (relação
  `ANTES`) é aplicado sobre a versão atual em vez de virar 409, porque somar um
  valor positivo é comutativo e nunca invalida o saldo produzido pelas escritas
  concorrentes. O conflito continua detectado e registrado (`SYNC_MESCLADA`),
  e o app mostra a operação como `MESCLADA`. Saques continuam indo para o 409.
- **Sprint 2 - Dead-letter queue com reprocessamento:** créditos remotos que
  falham (ex.: conta não encontrada depois de a agência reiniciar) vão para
  `fila-agencia-<id>.dlq` em vez de serem descartados.
  `GET /mensagens-mortas` lista a DLQ e `POST /mensagens-mortas/reprocessar`
  devolve as mensagens para a fila principal.
- **Sprint 1 - Histórico de transações:** `GET /contas/{id}/historico?limite=N`.

## Documentação da entrega

- `RESPOSTAS.md`: respostas do Sprint 3 e, abaixo, as dos Sprints 2 e 1.
- `evidencias/sprint3/`: prints do Sprint 3.
- `evidencias/sprint2/`: prints do Sprint 2 (o que cada um mostra em `evidencias/sprint2/README.md`).
- `evidencias/sprint1/`: prints do Sprint 1.
