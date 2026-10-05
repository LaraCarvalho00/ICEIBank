"""Controller de transferências (MVC: Controller).

- Transferência LOCAL (origem e destino na mesma agência): débito e crédito são
  dois eventos locais - relógio vetorial com ``evento_local()``.
- Transferência ENTRE AGÊNCIAS (Sprint 2): o débito é local; o crédito vira uma
  MENSAGEM publicada no RabbitMQ (routing key ``agencia.<destino>.creditar``),
  com o vetor de envio anexado (regra 2, ``ao_enviar()``). A agência de destino
  consome quando estiver no ar e aplica a regra 3 (``ao_receber()``) em
  ``processar_credito_remoto``.

Mudou o significado da resposta: no Sprint 1, 200 queria dizer "o crédito já foi
aplicado na outra agência"; agora quer dizer só "a mensagem foi aceita pelo
broker". O crédito acontece depois, de forma assíncrona.

LIMITAÇÃO CONHECIDA: se a mensagem chegar e a conta de destino não existir (ex.:
a agência reiniciou e perdeu as contas em memória), o crédito não é aplicado e o
débito na origem também não é desfeito. Compensar isso é assunto do Sprint 4
(Saga). Por enquanto o caso fica registrado como ``CREDITO_REMOTO_FALHOU``.
"""
import uuid

from fastapi import HTTPException
from pydantic import ValidationError

from .. import config
from ..esquemas import MensagemCredito, TransferenciaIn
from ..estado import ID_AGENCIA, contas, registro, relogio
from ..services import mensageria


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

    # ---- Caso 2: entre agências - publica no RabbitMQ ----
    # Em vez de chamar a outra agência (Sprint 1), publica um evento. Mesmo que
    # ela esteja fora do ar agora, a mensagem fica retida na fila durável e é
    # entregue quando ela voltar.
    ts_envio = relogio.ao_enviar()  # regra 2: incrementa e anexa o vetor
    id_mensagem = str(uuid.uuid4())
    routing_key = mensageria.routing_key_credito(agencia_destino)
    try:
        mensageria.publicar(
            routing_key,
            {
                "idMensagem": id_mensagem,
                "idOrigem": dados.idOrigem,
                "idConta": dados.idDestino,
                "valor": dados.valor,
                "vetorEnvio": ts_envio,
                "origemAgencia": ID_AGENCIA,
            },
        )
    except mensageria.ErroMensageria as erro:
        # Aqui dá para desfazer: o broker NÃO aceitou a mensagem, então
        # nenhum crédito vai acontecer do outro lado.
        conta_origem["saldo"] += dados.valor
        registro.registrar(
            "TRANSFERENCIA_DESFEITA",
            relogio.evento_local(),
            {"motivo": "falha ao publicar no RabbitMQ", "idDestino": dados.idDestino, "erro": str(erro)},
        )
        raise HTTPException(503, "Mensageria indisponivel; transferencia nao realizada.")

    registro.registrar(
        "TRANSFERENCIA_PUBLICADA",
        ts_envio,
        {
            "idMensagem": id_mensagem,
            "idOrigem": dados.idOrigem,
            "idDestino": dados.idDestino,
            "valor": dados.valor,
            "routingKey": routing_key,
        },
    )
    return {
        "mensagem": "Transferencia publicada para a agencia de destino (entrega assincrona).",
        "idMensagem": id_mensagem,
        "agenciaDestino": agencia_destino,
        "saldoOrigem": conta_origem["saldo"],
    }


def processar_credito_remoto(conteudo: dict) -> None:
    """Consumidor: crédito vindo de outra agência pela fila desta agência.

    Não passa pelo FastAPI, então não há JWT aqui (ver RESPOSTAS.md, Parte C,
    pergunta 3).
    """
    try:
        msg = MensagemCredito.model_validate(conteudo)
    except ValidationError as erro:
        registro.registrar(
            "MENSAGEM_INVALIDA",
            relogio.evento_local(),
            {"conteudo": conteudo, "camposInvalidos": [".".join(map(str, e["loc"])) for e in erro.errors()]},
        )
        return

    # Regra 3: máximo posição a posição com o vetor recebido + incrementa a
    # própria posição. Vale mesmo que o crédito falhe: a mensagem foi recebida.
    ts = relogio.ao_receber(msg.vetorEnvio)

    conta = contas.get(msg.idConta)
    if conta is None:
        registro.registrar(
            "CREDITO_REMOTO_FALHOU",
            ts,
            {
                "idMensagem": msg.idMensagem,
                "idConta": msg.idConta,
                "valor": msg.valor,
                "origemAgencia": msg.origemAgencia,
                "motivo": "conta nao encontrada",
            },
        )
        return

    conta["saldo"] += msg.valor
    registro.registrar(
        "TRANSFERENCIA_CREDITO_REMOTO",
        ts,
        {
            "idMensagem": msg.idMensagem,
            "idOrigem": msg.idOrigem,
            "idConta": msg.idConta,
            "valor": msg.valor,
            "origemAgencia": msg.origemAgencia,
            "novoSaldo": conta["saldo"],
        },
    )
