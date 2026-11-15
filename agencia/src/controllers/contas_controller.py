"""Controller de contas (MVC: Controller).

Regra de negócio de criar conta, consultar saldo, depositar e sacar. Toda
operação que altera estado é carimbada com o relógio vetorial
(``relogio.evento_local()``) e registrada no log de eventos.

Sprint 3: o carimbo da última alteração fica guardado na própria conta
(``conta["vetor"]``, a versão da conta) e volta em todas as respostas - é o que
o app Flutter usa como ``vetorBase`` das operações feitas offline.
"""
from fastapi import HTTPException

from .. import config
from ..esquemas import CriarContaIn, ValorIn
from ..estado import ID_AGENCIA, contas, registro, relogio, trava_contas


def criar_conta(dados: CriarContaIn) -> dict:
    responsavel = config.agencia_responsavel(dados.id)
    if responsavel != ID_AGENCIA:
        raise HTTPException(
            status_code=400,
            detail=f"Conta {dados.id} nao pertence a esta agencia "
            f"(pertence a agencia {responsavel}).",
        )
    with trava_contas:
        if dados.id in contas:
            raise HTTPException(status_code=409, detail="Conta ja existe.")

        ts = relogio.evento_local()
        contas[dados.id] = {
            "id": dados.id,
            "nomeAluno": dados.nomeAluno,
            "saldo": dados.saldoInicial or 0,
            "vetor": ts,
        }
        registro.registrar(
            "CRIAR_CONTA",
            ts,
            {"id": dados.id, "nomeAluno": dados.nomeAluno, "saldoInicial": dados.saldoInicial},
        )
        return dict(contas[dados.id])


def _conta_ou_404(id_conta: int) -> dict:
    conta = contas.get(id_conta)
    if conta is None:
        raise HTTPException(status_code=404, detail="Conta nao encontrada nesta agencia.")
    return conta


def consultar_saldo(id_conta: int) -> dict:
    with trava_contas:
        return dict(_conta_ou_404(id_conta))


def aplicar_deposito(id_conta: int, valor: float, extra: dict | None = None) -> dict:
    """Regra de depósito, compartilhada com a sincronização offline."""
    with trava_contas:
        conta = _conta_ou_404(id_conta)
        ts = relogio.evento_local()
        conta["saldo"] += valor
        conta["vetor"] = ts
        registro.registrar(
            "DEPOSITO", ts, {"id": id_conta, "valor": valor, "novoSaldo": conta["saldo"], **(extra or {})}
        )
        return dict(conta)


def aplicar_saque(id_conta: int, valor: float, extra: dict | None = None) -> dict:
    """Regra de saque, compartilhada com a sincronização offline."""
    with trava_contas:
        conta = _conta_ou_404(id_conta)
        if conta["saldo"] < valor:
            raise HTTPException(status_code=400, detail="Saldo insuficiente.")
        ts = relogio.evento_local()
        conta["saldo"] -= valor
        conta["vetor"] = ts
        registro.registrar(
            "SAQUE", ts, {"id": id_conta, "valor": valor, "novoSaldo": conta["saldo"], **(extra or {})}
        )
        return dict(conta)


def depositar(id_conta: int, dados: ValorIn) -> dict:
    return aplicar_deposito(id_conta, dados.valor)


def sacar(id_conta: int, dados: ValorIn) -> dict:
    return aplicar_saque(id_conta, dados.valor)
