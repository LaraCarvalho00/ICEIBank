"""Entrypoint da agência do ICEIBank (FastAPI).

Rodar cada agência com um AGENCIA_ID diferente:

    AGENCIA_ID=0 uv run uvicorn src.main:app --port 4000
    AGENCIA_ID=1 uv run uvicorn src.main:app --port 4001
    AGENCIA_ID=2 uv run uvicorn src.main:app --port 4002

Antes, em cada terminal, definir a URL do RabbitMQ (CloudAMQP):

    $env:RABBITMQ_URL="amqps://usuario:senha@host.cloudamqp.com/vhost"

Docs interativas: http://localhost:400X/docs
"""
import threading
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import estado
from .controllers import transferencias_controller
from .rotas import router
from .services import bully, mensageria


@asynccontextmanager
async def ciclo_de_vida(_app: FastAPI):
    # Consumidor: processa créditos vindos de outras agências via RabbitMQ.
    # Roda em uma thread própria, em paralelo ao servidor HTTP.
    mensageria.assinar(estado.ID_AGENCIA, transferencias_controller.processar_credito_remoto)

    # Sprint 3: ao subir, a agência convoca uma eleição. Espera 1 s para o
    # uvicorn já estar aceitando conexões (as outras vão responder a ela).
    def eleicao_inicial() -> None:
        time.sleep(1.0)
        bully.iniciar_eleicao("agencia iniciou")

    threading.Thread(target=eleicao_inicial, name="eleicao-inicial", daemon=True).start()
    yield


app = FastAPI(
    lifespan=ciclo_de_vida,
    title=f"ICEIBank - Agencia {estado.ID_AGENCIA}",
    description="Sprint 3 - API REST/MVC, relogio vetorial, mensageria (RabbitMQ), eleicao de lider (Bully) e sincronizacao offline-first",
    version="3.0.0",
)

# CORS: o frontend (Vite) roda em http://localhost:5173 e chama esta API em
# outra porta. Config permissiva de desenvolvimento - restringir em producao.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)


@app.get("/", tags=["meta"])
def raiz() -> dict:
    return {"servico": "ICEIBank - agencia", "idAgencia": estado.ID_AGENCIA}
