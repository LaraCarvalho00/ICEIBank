"""Controller de transferências (MVC: Controller).

- Transferência LOCAL (origem e destino na mesma agência): débito e crédito são
  dois eventos locais - relógio vetorial com ``evento_local()``.
- Transferência ENTRE AGÊNCIAS: o débito é local; o crédito vira uma mensagem
  REST para a agência de destino. Aí entram as regras 2 e 3 do relógio
  (``ao_enviar()`` no remetente, ``ao_receber()`` no destinatário).

LIMITAÇÃO CONHECIDA: se a chamada à agência de destino falhar (agência fora do
ar, rede caiu), o débito já aplicado NÃO é revertido - o dinheiro "some"
temporariamente. Garantir atomicidade sob falha é assunto do Sprint 4
(transação distribuída: 2PC ou Saga). Por enquanto apenas registramos a
inconsistência no log, com o evento ``TRANSFERENCIA_FALHOU``.
"""
import httpx
from fastapi import HTTPException

from .. import config
from ..esquemas import CreditarRemotoIn, TransferenciaIn
from ..estado import ID_AGENCIA, contas, registro, relogio
from ..seguranca import criar_token_interno


def transferir(dados: TransferenciaIn) -> dict:
    conta_origem = contas.get(dados.idOrigem)
    if conta_origem is None:
        raise HTTPException(404, "Conta de origem nao encontrada nesta agencia.")
    if conta_origem["saldo"] < dados.valor:
        raise HTTPException(400, "Saldo insuficiente.")

    agencia_destino = config.agencia_responsavel(dados.idDestino)

    # O débito é SEMPRE local: esta agência é a dona da conta de origem.
    ts_debito = relogio.evento_local()
    conta_origem["saldo"] -= dados.valor
    registro.registrar(
        "TRANSFERENCIA_DEBITO",
        ts_debito,
        {"idOrigem": dados.idOrigem, "idDestino": dados.idDestino, "valor": dados.valor},
    )

    # ---- Caso 1: mesma agência - credita direto (outro evento local) ----
    if agencia_destino == ID_AGENCIA:
        conta_destino = contas.get(dados.idDestino)
        if conta_destino is None:
            conta_origem["saldo"] += dados.valor  # desfaz o débito
            registro.registrar(
                "TRANSFERENCIA_DESFEITA",
                relogio.evento_local(),
                {"motivo": "conta de destino inexistente", "idDestino": dados.idDestino},
            )
            raise HTTPException(404, "Conta de destino nao encontrada.")

        ts_credito = relogio.evento_local()
        conta_destino["saldo"] += dados.valor
        registro.registrar(
            "TRANSFERENCIA_CREDITO",
            ts_credito,
            {"idOrigem": dados.idOrigem, "idDestino": dados.idDestino, "valor": dados.valor},
        )
        return {
            "mensagem": "Transferencia concluida (mesma agencia).",
            "saldoOrigem": conta_origem["saldo"],
            "saldoDestino": conta_destino["saldo"],
        }

    # ---- Caso 2: entre agências - chama a agência de destino via REST ----
    ts_envio = relogio.ao_enviar()  # regra 2: incrementa e anexa à mensagem
    url_destino = config.url_agencia(agencia_destino)
    # Chamada agência-a-agência: token de escopo "interno", não o token do
    # usuário final (ver justificativa em RESPOSTAS.md - Parte F).
    cabecalhos = {"Authorization": f"Bearer {criar_token_interno(f'agencia-{ID_AGENCIA}')}"}
    try:
        resposta = httpx.post(
            f"{url_destino}/contas/{dados.idDestino}/creditar-remoto",
            json={
                "valor": dados.valor,
                "timestampVetorial": ts_envio,
                "origemAgencia": ID_AGENCIA,
            },
            headers=cabecalhos,
            timeout=5.0,
        )
        resposta.raise_for_status()
    except httpx.HTTPError as erro:
        # LIMITAÇÃO CONHECIDA (Sprint 4): o débito acima NÃO é revertido.
        registro.registrar(
            "TRANSFERENCIA_FALHOU",
            relogio.evento_local(),
            {
                "idOrigem": dados.idOrigem,
                "idDestino": dados.idDestino,
                "valor": dados.valor,
                "erro": str(erro),
            },
        )
        raise HTTPException(
            502,
            "Falha ao contatar agencia de destino. Debito ja aplicado - "
            "inconsistencia conhecida (ver Sprint 4).",
        )

    corpo = resposta.json()
    return {
        "mensagem": "Transferencia concluida (entre agencias).",
        "saldoOrigem": conta_origem["saldo"],
        "saldoDestinoRemoto": corpo.get("saldoAtual"),
    }


def creditar_remoto(id_conta: int, dados: CreditarRemotoIn) -> dict:
    # Regra 3: ao RECEBER mensagem de outra agência, máximo posição a posição
    # com o vetor recebido e depois incrementa a própria posição.
    ts = relogio.ao_receber(dados.timestampVetorial)

    conta = contas.get(id_conta)
    if conta is None:
        raise HTTPException(404, "Conta nao encontrada nesta agencia.")

    conta["saldo"] += dados.valor
    registro.registrar(
        "TRANSFERENCIA_CREDITO_REMOTO",
        ts,
        {"idConta": id_conta, "valor": dados.valor, "origemAgencia": dados.origemAgencia},
    )
    return {"mensagem": "Credito remoto aplicado.", "saldoAtual": conta["saldo"]}
