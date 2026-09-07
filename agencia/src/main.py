"""Entrypoint da agência do ICEIBank (FastAPI).

Rodar cada agência com um AGENCIA_ID diferente:

    AGENCIA_ID=0 uv run uvicorn src.main:app --port 4000
    AGENCIA_ID=1 uv run uvicorn src.main:app --port 4001
    AGENCIA_ID=2 uv run uvicorn src.main:app --port 4002

Docs interativas: http://localhost:400X/docs
"""
from fastapi import FastAPI

from . import estado
from .rotas import router

app = FastAPI(
    title=f"ICEIBank - Agencia {estado.ID_AGENCIA}",
    description="Sprint 1 - API REST/MVC com relogio de Lamport",
    version="1.0.0",
)
app.include_router(router)


@app.get("/", tags=["meta"])
def raiz() -> dict:
    return {"servico": "ICEIBank - agencia", "idAgencia": estado.ID_AGENCIA}
