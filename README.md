# ICEIBank

Banco simplificado dividido em agências, desenvolvido ao longo de 4 sprints na
disciplina de **Laboratório de Desenvolvimento de Aplicações Móveis e
Distribuídas** (U2 - Desenvolvimento Web: arquitetura MVC e serviços REST).

- **Sprint 1 (atual):** API REST / MVC + Relógio lógico de Lamport + Autenticação JWT + Frontend web.
- Sprint 2: Mensageria / Pub-Sub + Relógio vetorial.
- Sprint 3: App Flutter + Consenso (eleição de líder).
- Sprint 4: Containers + Transações distribuídas (2PC / Saga).

## Stack (Sprint 1)

| Camada    | Tecnologia                    |
|-----------|-------------------------------|
| Backend   | Python 3.12 + FastAPI + Uvicorn |
| Auth      | JWT (PyJWT)                   |
| Frontend  | React + Vite                  |
| Testes    | `curl` / navegador `/docs`    |

## Arquitetura

Cada **agência** é uma partição independente de contas. O mesmo código roda 3
vezes, com identidades diferentes (`AGENCIA_ID` = 0, 1, 2). A agência
responsável por uma conta é `id_conta % 3`.

```
agencia/
├── src/
│   ├── main.py                 # entrypoint FastAPI
│   ├── config.py               # particionamento e portas
│   ├── estado.py               # estado em memória (contas, relógio, log)
│   ├── esquemas.py             # modelos Pydantic (corpos de requisição)
│   ├── rotas.py                # mapeia rotas -> controllers
│   ├── controllers/            # regra de negócio (MVC: Controller)
│   │   ├── contas_controller.py
│   │   └── transferencias_controller.py
│   └── services/
│       ├── relogio_lamport.py  # relógio lógico de Lamport
│       └── registro_eventos.py # log de eventos (.jsonl)
├── data/                       # logs gerados em runtime (não versionado)
└── mesclar_logs.py             # linha do tempo unificada das 3 agências
```

## Como rodar

Pré-requisitos: Python 3.12 e [uv](https://docs.astral.sh/uv/). Node 20+ para o frontend.

```bash
cd agencia
uv sync                         # cria .venv e instala dependências

# 3 terminais, um por agência:
AGENCIA_ID=0 uv run uvicorn src.main:app --port 4000
AGENCIA_ID=1 uv run uvicorn src.main:app --port 4001
AGENCIA_ID=2 uv run uvicorn src.main:app --port 4002
```

Documentação interativa de cada agência em `http://localhost:400X/docs`.

### Autenticação (JWT)

As rotas de conta e `/transferencias` exigem `Authorization: Bearer <token>`.
Obtenha um token em `POST /auth/login` (usuários de teste: `lara` / `allan`,
senha `iceibank`):

```bash
curl -s -X POST http://localhost:4000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"usuario":"lara","senha":"iceibank"}'
```

Variáveis de ambiente opcionais: `JWT_SEGREDO` (troque em produção),
`JWT_EXPIRACAO_MIN` (padrão 30), `SENHA_LARA`, `SENHA_ALLAN`.
A chamada interna `creditar-remoto` usa um token de escopo `interno` emitido
pela agência de origem (ver `RESPOSTAS.md` - Parte F).

Linha do tempo unificada (depois de gerar alguns eventos):

```bash
cd agencia && uv run python mesclar_logs.py
```

Frontend (com as 3 agências já rodando):

```bash
cd frontend
npm install
npm run dev            # http://localhost:5173
```

Login com `lara` / `iceibank`. O seletor "Agência de entrada" no topo escolhe
qual das 3 agências responde (cada agência só conhece as contas sob sua
responsabilidade: `id_conta % 3`).

MVC do frontend: **Model** em `src/api/` (acesso à API, token, tratamento de
erro), **View** em `src/componentes/` (formulários e banner de mensagem),
**Controller** em `src/App.jsx` (estado + orquestração). Detalhes em
`RESPOSTAS.md` - Parte G.

## Funcionalidade adicional (seção 2.1)

`GET /contas/{id}/historico?limite=N` - histórico de transações de uma conta,
montado a partir do log de eventos da agência e ordenado por relógio de Lamport.
Ver `RESPOSTAS.md` e `evidencias/sprint1/demos/08-historico.sh`.

## Documentação da entrega

- `RESPOSTAS.md` - respostas às questões das seções 6.4, 8.3, 10.3, 11.3 e 12.3,
  descrição da funcionalidade adicional e justificativas de design (Partes F e G).
- `evidencias/sprint1/` - prints de teste.
