"""Funcionalidade adicional (seção 2.1): histórico de transações por conta.

    GET /contas/{id}/historico?limite=N   (padrão N = 20)

Lê o log de eventos da agência (``data/eventos-agencia-<id>.jsonl``) e devolve,
na ordem em que foram registrados, os eventos que envolvem a conta informada:
criação, depósitos, saques e as pontas de transferência (débito, crédito,
crédito remoto e falha). Serve para auditoria e para conferir o extrato de uma
conta sem precisar abrir o arquivo de log à mão.

Comportamento novo e observável: um endpoint que antes não existia, com uma
regra própria (filtrar o log por conta) e um parâmetro de consulta (``limite``).
"""
import json

from fastapi import HTTPException

from ..estado import ID_AGENCIA, contas, registro

# Campos de "detalhes" que podem apontar para uma conta.
_CAMPOS_CONTA = ("id", "idConta", "idOrigem", "idDestino")


def _envolve_conta(evento: dict, id_conta: int) -> bool:
    detalhes = evento.get("detalhes", {})
    return any(detalhes.get(campo) == id_conta for campo in _CAMPOS_CONTA)


def historico(id_conta: int, limite: int = 20) -> dict:
    if id_conta not in contas:
        raise HTTPException(404, "Conta nao encontrada nesta agencia.")
    if not 1 <= limite <= 500:
        raise HTTPException(422, "limite deve estar entre 1 e 500.")

    eventos: list[dict] = []
    try:
        with open(registro.caminho_arquivo, encoding="utf-8") as arquivo:
            for linha in arquivo:
                linha = linha.strip()
                if not linha:
                    continue
                evento = json.loads(linha)
                if _envolve_conta(evento, id_conta):
                    eventos.append(evento)
    except FileNotFoundError:
        eventos = []

    # O arquivo é só desta agência e é escrito em ordem (append sob lock), e a
    # posição própria do vetor cresce a cada evento - a ordem das linhas já é a
    # ordem causal local. Não é preciso reordenar.
    return {
        "agencia": ID_AGENCIA,
        "conta": id_conta,
        "total": len(eventos),
        "limite": limite,
        "eventos": eventos[-limite:],
    }
