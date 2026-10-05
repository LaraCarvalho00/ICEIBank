# ICEIBank

Banco simplificado dividido em agências, desenvolvido ao longo de 4 sprints na
disciplina de **Laboratório de Desenvolvimento de Aplicações Móveis e
Distribuídas**.

- Sprint 1: API REST / MVC + Relógio lógico de Lamport + Autenticação JWT + Frontend web.
- **Sprint 2 (atual):** Mensageria / Pub-Sub (RabbitMQ) + Relógio vetorial.
- Sprint 3: App Flutter + Consenso (eleição de líder).
- Sprint 4: Containers + Transações distribuídas (2PC / Saga).

## Stack

| Camada     | Tecnologia                                  |
|------------|---------------------------------------------|
| Backend    | Python 3.12 + FastAPI + Uvicorn             |
| Mensageria | RabbitMQ (CloudAMQP) via `pika`             |
| Auth       | JWT (PyJWT)                                 |
| Frontend   | React + Vite                                |
| Testes     | `verificar_vetorial.py`, PowerShell/`curl`, `/docs` |

## Arquitetura

Cada **agência** é uma partição independente de contas. O mesmo código roda 3
vezes, com identidades diferentes (`AGENCIA_ID` = 0, 1, 2). A agência
responsável por uma conta é `id_conta % 3`.

Transferência entre agências (Sprint 2): a agência de origem debita localmente
e **publica** um evento na exchange `iceibank.eventos` (tipo `topic`) com a
routing key `agencia.<destino>.creditar`. A agência de destino **consome** da
sua fila durável `fila-agencia-<id>` quando estiver no ar. Cada evento leva um
**relógio vetorial** de 3 posições.

```
agencia/
├── src/
│   ├── main.py                       # entrypoint FastAPI + inicia o consumidor RabbitMQ
│   ├── config.py                     # particionamento e portas
│   ├── estado.py                     # estado em memória (contas, relógio, log)
│   ├── esquemas.py                   # modelos Pydantic (requisições e mensagem de crédito)
│   ├── rotas.py                      # mapeia rotas -> controllers
│   ├── seguranca.py                  # JWT
│   ├── controllers/                  # regra de negócio (MVC: Controller)
│   │   ├── contas_controller.py
│   │   ├── transferencias_controller.py   # publica / processa créditos remotos
│   │   ├── historico_controller.py        # extra do Sprint 1
│   │   └── mensagens_mortas_controller.py # extra do Sprint 2 (DLQ)
│   └── services/
│       ├── relogio_vetorial.py       # relógio vetorial + comparar()
│       ├── mensageria.py             # RabbitMQ: topologia, publicar, assinar, DLQ
│       └── registro_eventos.py       # log de eventos (.jsonl)
├── data/                             # logs gerados em runtime (não versionado)
├── mesclar_logs.py                   # linha do tempo causal + pares concorrentes
├── verificar_vetorial.py             # teste isolado do relógio vetorial
└── .env.local                        # RABBITMQ_URL (NÃO versionado)
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

- **Sprint 2 - Dead-letter queue com reprocessamento:** créditos remotos que
  falham (ex.: conta não encontrada depois de a agência reiniciar) vão para
  `fila-agencia-<id>.dlq` em vez de serem descartados.
  `GET /mensagens-mortas` lista a DLQ e `POST /mensagens-mortas/reprocessar`
  devolve as mensagens para a fila principal.
- **Sprint 1 - Histórico de transações:** `GET /contas/{id}/historico?limite=N`.

## Documentação da entrega

- `RESPOSTAS.md`: respostas do Sprint 2 (seções 6.4, 7.5 e 8.3 + funcionalidade
  adicional) e, abaixo, as do Sprint 1.
- `evidencias/sprint2/`: prints do Sprint 2.
- `evidencias/sprint1/`: prints do Sprint 1.
