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

Funcionalidade adicional (seção 2.1) - dead-letter queue:

- exchange ``iceibank.dlx`` (``direct``, durável) e uma fila
  ``fila-agencia-<id>.dlq`` por agência;
- cada ``fila-agencia-<id>`` é declarada com ``x-dead-letter-exchange``: uma
  mensagem REJEITADA pelo consumidor (``basic_nack`` sem requeue) não é
  descartada - o broker a move para a DLQ da agência, com o cabeçalho
  ``x-death`` (quando, de qual fila, por quê);
- ``listar_mortas()`` espia a DLQ sem consumir e ``reprocessar_mortas()`` devolve
  as mensagens para a fila principal (ex.: depois de recriar a conta que
  faltava).
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



def _url_rabbitmq() -> str | None:
    """``RABBITMQ_URL`` do ambiente; se não houver, de ``agencia/.env.local``
    (uma linha ``RABBITMQ_URL=amqps://...``, fora do Git - contém a senha)."""
    if os.environ.get("RABBITMQ_URL"):
        return os.environ["RABBITMQ_URL"]
    caminho = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".env.local")
    try:
        with open(caminho, encoding="utf-8-sig") as arquivo:
            for linha in arquivo:
                chave, _, valor = linha.strip().partition("=")
                if chave.strip() == "RABBITMQ_URL" and valor.strip():
                    return valor.strip().strip('"')
    except FileNotFoundError:
        pass
    return None


URL_RABBITMQ = _url_rabbitmq()
EXCHANGE = "iceibank.eventos"
EXCHANGE_DLX = "iceibank.dlx"

if not URL_RABBITMQ:
    raise SystemExit(
        "Defina a variavel de ambiente RABBITMQ_URL com a URL AMQP da sua "
        "instancia CloudAMQP antes de iniciar. No PowerShell:\n"
        '  $env:RABBITMQ_URL="amqps://usuario:senha@host.cloudamqp.com/vhost"\n'
        "ou grave a linha RABBITMQ_URL=amqps://... em agencia/.env.local"
    )

# O pika é muito verboso em INFO (cada handshake vira várias linhas).
logging.getLogger("pika").setLevel(logging.WARNING)


class ErroMensageria(Exception):
    """A mensagem não pôde ser entregue ao broker."""


class MensagemRecusada(Exception):
    """Levantada pelo processador: a mensagem não pode ser aplicada e deve ir
    para a dead-letter queue (em vez de ser confirmada e esquecida)."""


def nome_fila(id_agencia: int) -> str:
    return f"fila-agencia-{id_agencia}"


def nome_fila_dlq(id_agencia: int) -> str:
    return f"fila-agencia-{id_agencia}.dlq"


def routing_key_credito(id_agencia: int) -> str:
    return f"agencia.{id_agencia}.creditar"


def _conectar() -> pika.BlockingConnection:
    parametros = pika.URLParameters(URL_RABBITMQ)
    parametros.connection_attempts = 3
    parametros.retry_delay = 2
    return pika.BlockingConnection(parametros)


def _declarar_topologia(canal) -> None:
    canal.exchange_declare(exchange=EXCHANGE, exchange_type="topic", durable=True)
    canal.exchange_declare(exchange=EXCHANGE_DLX, exchange_type="direct", durable=True)
    for agencia in config.AGENCIAS:
        id_ag = agencia["id"]
        rk = routing_key_credito(id_ag)
        # DLQ: recebe o que for rejeitado na fila principal (mesma routing key).
        canal.queue_declare(queue=nome_fila_dlq(id_ag), durable=True)
        canal.queue_bind(queue=nome_fila_dlq(id_ag), exchange=EXCHANGE_DLX, routing_key=rk)
        try:
            canal.queue_declare(
                queue=nome_fila(id_ag),
                durable=True,
                arguments={"x-dead-letter-exchange": EXCHANGE_DLX},
            )
        except pika.exceptions.ChannelClosedByBroker as erro:
            if erro.reply_code == 406:  # PRECONDITION_FAILED
                raise SystemExit(
                    f"A fila {nome_fila(id_ag)} ja existe no RabbitMQ sem dead-letter "
                    "configurada (criada por uma versao anterior). Apague as filas "
                    "fila-agencia-* no RabbitMQ Manager e suba a agencia de novo."
                ) from erro
            raise
        canal.queue_bind(queue=nome_fila(id_ag), exchange=EXCHANGE, routing_key=rk)


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
            print(f"[mensageria] JSON invalido, enviado para a DLQ: {corpo[:200]!r}", file=sys.stderr)
            canal.basic_nack(entrega.delivery_tag, requeue=False)
            return
        try:
            ao_receber_mensagem(mensagem)
        except Exception as erro:
            # MensagemRecusada (ex.: conta não encontrada) ou bug no
            # processamento. Rejeita SEM recolocar na fila (senão voltaria em
            # loop infinito): o broker move a mensagem para a DLQ.
            print(f"[mensageria] mensagem enviada para {nome_fila_dlq(id_agencia)}: {erro}", flush=True)
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


# --- dead-letter queue (funcionalidade adicional) ----------------------------------
# Operações administrativas e raras: cada chamada abre a sua própria conexão, o
# que evita disputar o canal do publicador ou o do consumidor.

def _resumo_morte(propriedades) -> dict:
    mortes = (propriedades.headers or {}).get("x-death") or []
    if not mortes:
        return {}
    ultima = mortes[0]
    instante = ultima.get("time")
    return {
        "motivo": ultima.get("reason"),
        "filaOriginal": ultima.get("queue"),
        "vezes": ultima.get("count"),
        "quando": instante.isoformat() if hasattr(instante, "isoformat") else str(instante),
    }


def listar_mortas(id_agencia: int, limite: int = 50) -> list[dict]:
    """Espia a DLQ sem consumir: pega sem ack e fecha o canal, o que devolve
    as mensagens para a fila."""
    try:
        conexao = _conectar()
    except AMQPError as erro:
        raise ErroMensageria(f"falha ao conectar no RabbitMQ: {erro!r}") from erro
    try:
        canal = conexao.channel()
        _declarar_topologia(canal)
        mensagens = []
        for _ in range(limite):
            entrega, propriedades, corpo = canal.basic_get(nome_fila_dlq(id_agencia), auto_ack=False)
            if entrega is None:
                break
            try:
                conteudo = json.loads(corpo)
            except json.JSONDecodeError:
                conteudo = corpo.decode(errors="replace")
            mensagens.append({"conteudo": conteudo, "morte": _resumo_morte(propriedades)})
        return mensagens
    except AMQPError as erro:
        raise ErroMensageria(f"falha ao ler a DLQ: {erro!r}") from erro
    finally:
        if conexao.is_open:
            conexao.close()


def reprocessar_mortas(id_agencia: int) -> int:
    """Republica cada mensagem da DLQ na exchange principal (mesma routing key
    de crédito) e só então a remove da DLQ. Retorna quantas foram movidas."""
    try:
        conexao = _conectar()
    except AMQPError as erro:
        raise ErroMensageria(f"falha ao conectar no RabbitMQ: {erro!r}") from erro
    try:
        canal = conexao.channel()
        canal.confirm_delivery()
        _declarar_topologia(canal)
        # Limita ao tamanho atual: se uma mensagem falhar de novo e voltar para
        # a DLQ durante o laço, ela não é reprocessada outra vez agora.
        pendentes = canal.queue_declare(queue=nome_fila_dlq(id_agencia), passive=True).method.message_count
        movidas = 0
        for _ in range(pendentes):
            entrega, propriedades, corpo = canal.basic_get(nome_fila_dlq(id_agencia), auto_ack=False)
            if entrega is None:
                break
            canal.basic_publish(
                exchange=EXCHANGE,
                routing_key=routing_key_credito(id_agencia),
                body=corpo,
                properties=pika.BasicProperties(
                    content_type=propriedades.content_type,
                    delivery_mode=pika.DeliveryMode.Persistent,
                ),
                mandatory=True,
            )
            canal.basic_ack(entrega.delivery_tag)
            movidas += 1
        return movidas
    except AMQPError as erro:
        raise ErroMensageria(f"falha ao reprocessar a DLQ: {erro!r}") from erro
    finally:
        if conexao.is_open:
            conexao.close()
