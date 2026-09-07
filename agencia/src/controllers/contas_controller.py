"""Controller de contas (MVC: Controller).

Regra de negócio de criar conta, consultar saldo, depositar e sacar. Toda
operação que altera estado é carimbada com um timestamp do relógio de Lamport
(``relogio.evento_local()``) e registrada no log de eventos.
"""
from fastapi import HTTPException

from .. import config
from ..esquemas import CriarContaIn, ValorIn
from ..estado import ID_AGENCIA, contas, registro, relogio


def criar_conta(dados: CriarContaIn) -> dict:
    responsavel = config.agencia_responsavel(dados.id)
    if responsavel != ID_AGENCIA:
        raise HTTPException(
            status_code=400,
            detail=f"Conta {dados.id} nao pertence a esta agencia "
            f"(pertence a agencia {responsavel}).",
        )
    if dados.id in contas:
        raise HTTPException(status_code=409, detail="Conta ja existe.")

    ts = relogio.evento_local()
    contas[dados.id] = {
        "id": dados.id,
        "nomeAluno": dados.nomeAluno,
        "saldo": dados.saldoInicial or 0,
    }
    registro.registrar(
        "CRIAR_CONTA",
        ts,
        {"id": dados.id, "nomeAluno": dados.nomeAluno, "saldoInicial": dados.saldoInicial},
    )
    return contas[dados.id]


def consultar_saldo(id_conta: int) -> dict:
    conta = contas.get(id_conta)
    if conta is None:
        raise HTTPException(status_code=404, detail="Conta nao encontrada nesta agencia.")
    return conta


def depositar(id_conta: int, dados: ValorIn) -> dict:
    conta = contas.get(id_conta)
    if conta is None:
        raise HTTPException(status_code=404, detail="Conta nao encontrada nesta agencia.")

    ts = relogio.evento_local()
    conta["saldo"] += dados.valor
    registro.registrar(
        "DEPOSITO", ts, {"id": id_conta, "valor": dados.valor, "novoSaldo": conta["saldo"]}
    )
    return conta


def sacar(id_conta: int, dados: ValorIn) -> dict:
    conta = contas.get(id_conta)
    if conta is None:
        raise HTTPException(status_code=404, detail="Conta nao encontrada nesta agencia.")
    if conta["saldo"] < dados.valor:
        raise HTTPException(status_code=400, detail="Saldo insuficiente.")

    ts = relogio.evento_local()
    conta["saldo"] -= dados.valor
    registro.registrar(
        "SAQUE", ts, {"id": id_conta, "valor": dados.valor, "novoSaldo": conta["saldo"]}
    )
    return conta
