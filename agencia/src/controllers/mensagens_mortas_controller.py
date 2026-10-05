"""Funcionalidade adicional (seção 2.1): dead-letter queue de créditos remotos.

    GET  /mensagens-mortas?limite=N      lista a DLQ desta agência (sem consumir)
    POST /mensagens-mortas/reprocessar   devolve tudo da DLQ para a fila principal

Um crédito remoto que não pode ser aplicado (conta de destino inexistente,
mensagem malformada) não é confirmado e esquecido: o consumidor o rejeita e o
RabbitMQ o move para ``fila-agencia-<id>.dlq``. Depois de corrigir a causa (ex.:
recriar a conta perdida no reinício da agência), o reprocessamento republica as
mensagens e o consumidor tenta aplicá-las de novo.
"""
from fastapi import HTTPException

from ..estado import ID_AGENCIA, registro, relogio
from ..services import mensageria


def listar(limite: int = 50) -> dict:
    if not 1 <= limite <= 500:
        raise HTTPException(422, "limite deve estar entre 1 e 500.")
    try:
        mensagens = mensageria.listar_mortas(ID_AGENCIA, limite)
    except mensageria.ErroMensageria as erro:
        raise HTTPException(503, str(erro))
    return {
        "agencia": ID_AGENCIA,
        "fila": mensageria.nome_fila_dlq(ID_AGENCIA),
        "total": len(mensagens),
        "mensagens": mensagens,
    }


def reprocessar() -> dict:
    try:
        movidas = mensageria.reprocessar_mortas(ID_AGENCIA)
    except mensageria.ErroMensageria as erro:
        raise HTTPException(503, str(erro))
    if movidas:
        registro.registrar(
            "DLQ_REPROCESSADA", relogio.evento_local(), {"mensagens": movidas}
        )
    return {
        "agencia": ID_AGENCIA,
        "reprocessadas": movidas,
        "mensagem": "Mensagens devolvidas para a fila principal; o consumidor tenta aplica-las de novo."
        if movidas
        else "DLQ vazia.",
    }
