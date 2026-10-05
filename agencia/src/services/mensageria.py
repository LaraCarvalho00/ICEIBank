"""Mensageria entre agências via RabbitMQ (Parte C - Publish/Subscribe).

Topologia (igual à do roteiro):

- exchange ``iceibank.eventos`` do tipo ``topic``, durável;
- uma fila durável por agência: ``fila-agencia-0``, ``fila-agencia-1``,
  ``fila-agencia-2``, ligada à exchange pela routing key
  ``agencia.<id>.creditar``.

Quem publica não conhece quem consome: a agência de origem só publica em
``agencia.<destino>.creditar``; a exchange entrega na fila certa.

Detalhes de robustez (além do exemplo em Node do roteiro):

- **Toda agência declara as 3 filas**, não só a própria. Se a agência de
  destino nunca tiver subido, a fila dela já existe e a mensagem fica retida
  - sem isso a exchange descartaria a mensagem por não ter fila ligada.
- **Publisher confirms + ``mandatory``**: ``publicar()`` só retorna depois que o
  broker confirmou que gravou a mensagem em uma fila. Se falhar, levanta
  ``ErroMensageria`` e o controller desfaz o débito.
- **pika não é thread-safe**: o publicador usa uma conexão protegida por lock
  (as rotas do FastAPI rodam em um threadpool) e o consumidor roda em uma
  thread própria, com a sua própria conexão, reconectando sozinho se cair.
"""
import json
import logging
import os
import sys
import threading
import time
from typing import Callable

import pika
from pika.exceptions import AMQPError

from .. import config

URL_RABBITMQ = os.environ.get("RABBITMQ_URL")
EXCHANGE = "iceibank.eventos"

if not URL_RABBITMQ:
    raise SystemExit(
        "Defina a variavel de ambiente RABBITMQ_URL com a URL AMQP da sua "
        "instancia CloudAMQP antes de iniciar. No PowerShell:\n"
        '  $env:RABBITMQ_URL="amqps://usuario:senha@host.cloudamqp.com/vhost"'
    )

# O pika é muito verboso em INFO (cada handshake vira várias linhas).
logging.getLogger("pika").setLevel(logging.WARNING)


class ErroMensageria(Exception):
    """A mensagem não pôde ser entregue ao broker."""


def nome_fila(id_agencia: int) -> str:
    return f"fila-agencia-{id_agencia}"


def routing_key_credito(id_agencia: int) -> str:
    return f"agencia.{id_agencia}.creditar"


def _conectar() -> pika.BlockingConnection:
    parametros = pika.URLParameters(URL_RABBITMQ)
    parametros.connection_attempts = 3
    parametros.retry_delay = 2
    return pika.BlockingConnection(parametros)


def _declarar_topologia(canal) -> None:
    canal.exchange_declare(exchange=EXCHANGE, exchange_type="topic", durable=True)
    for agencia in config.AGENCIAS:
        fila = nome_fila(agencia["id"])
        canal.queue_declare(queue=fila, durable=True)
        canal.queue_bind(
            queue=fila, exchange=EXCHANGE, routing_key=routing_key_credito(agencia["id"])
        )


# --- publicação ------------------------------------------------------------------

_lock_publicacao = threading.Lock()
_conexao_pub: pika.BlockingConnection | None = None
_canal_pub = None


def _canal_publicacao():
    global _conexao_pub, _canal_pub
    if _canal_pub is None or _canal_pub.is_closed or _conexao_pub.is_closed:
        _conexao_pub = _conectar()
        _canal_pub = _conexao_pub.channel()
        _canal_pub.confirm_delivery()
        _declarar_topologia(_canal_pub)
    return _canal_pub


def _descartar_conexao_publicacao() -> None:
    global _conexao_pub, _canal_pub
    try:
        if _conexao_pub is not None and _conexao_pub.is_open:
            _conexao_pub.close()
    except AMQPError:
        pass
    _conexao_pub = _canal_pub = None


def publicar(routing_key: str, mensagem: dict) -> None:
    """Publica ``mensagem`` (JSON, persistente) e espera a confirmação do broker.

    Tenta 2 vezes: a conexão de publicação fica ociosa entre transferências e o
    broker pode tê-la fechado por falta de heartbeat; aí basta reconectar.
    """
    corpo = json.dumps(mensagem).encode()
    propriedades = pika.BasicProperties(
        content_type="application/json",
        delivery_mode=pika.DeliveryMode.Persistent,
    )
    ultimo_erro: Exception | None = None
    with _lock_publicacao:
        for _ in range(2):
            try:
                _canal_publicacao().basic_publish(
                    exchange=EXCHANGE,
                    routing_key=routing_key,
                    body=corpo,
                    properties=propriedades,
                    mandatory=True,
                )
                return
            except pika.exceptions.UnroutableError as erro:
                # Nenhuma fila ligada a essa routing key: não adianta repetir.
                raise ErroMensageria(f"mensagem sem fila de destino ({routing_key})") from erro
            except AMQPError as erro:
                ultimo_erro = erro
                _descartar_conexao_publicacao()
    raise ErroMensageria(f"falha ao publicar no RabbitMQ: {ultimo_erro!r}") from ultimo_erro


# --- consumo ---------------------------------------------------------------------

def assinar(id_agencia: int, ao_receber_mensagem: Callable[[dict], None]) -> threading.Thread:
    """Consome ``fila-agencia-<id>`` em uma thread daemon.

    ``ao_receber_mensagem`` recebe o JSON já decodificado. A mensagem só é
    confirmada (ack) DEPOIS de processada: se a agência cair no meio, o
    RabbitMQ entrega de novo quando ela voltar.
    """

    def ao_chegar(canal, entrega, _propriedades, corpo: bytes) -> None:
        try:
            mensagem = json.loads(corpo)
        except json.JSONDecodeError:
            print(f"[mensageria] mensagem invalida descartada: {corpo[:200]!r}", file=sys.stderr)
            canal.basic_ack(entrega.delivery_tag)
            return
        try:
            ao_receber_mensagem(mensagem)
        except Exception as erro:
            # Bug no processamento: rejeita sem recolocar na fila, senão a mesma
            # mensagem voltaria em loop infinito.
            print(f"[mensageria] erro ao processar {mensagem}: {erro!r}", file=sys.stderr)
            canal.basic_nack(entrega.delivery_tag, requeue=False)
            return
        canal.basic_ack(entrega.delivery_tag)

    def laco() -> None:
        while True:
            conexao = None
            try:
                conexao = _conectar()
                canal = conexao.channel()
                _declarar_topologia(canal)
                canal.basic_qos(prefetch_count=1)  # uma mensagem por vez
                canal.basic_consume(queue=nome_fila(id_agencia), on_message_callback=ao_chegar)
                print(f"[mensageria] consumindo {nome_fila(id_agencia)}", flush=True)
                canal.start_consuming()
            except AMQPError as erro:
                print(f"[mensageria] conexao perdida ({erro!r}); reconectando em 5 s", file=sys.stderr)
            finally:
                if conexao is not None and conexao.is_open:
                    try:
                        conexao.close()
                    except AMQPError:
                        pass
            time.sleep(5)

    thread = threading.Thread(target=laco, name=f"consumidor-agencia-{id_agencia}", daemon=True)
    thread.start()
    return thread
