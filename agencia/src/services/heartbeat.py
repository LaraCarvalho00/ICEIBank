"""Detecção de falha da líder (Sprint 3, Parte B).

Uma thread daemon por agência que, a cada ``INTERVALO`` segundos:

- se não há líder conhecida (acabou de subir, ou a anterior caiu): convoca
  eleição;
- se a líder é esta própria agência: não faz nada (ninguém vigia a si mesma);
- senão, faz ``GET /bully/lider`` na líder com timeout de 1 s. Depois de
  ``FALHAS_TOLERADAS`` falhas SEGUIDAS, considera a líder morta, registra
  ``LIDER_INALCANCAVEL`` e convoca uma nova eleição - sem intervenção manual.

Tolerar mais de uma falha evita trocar de líder por causa de um único pacote
perdido ou de uma pausa curta (ex.: GC, máquina ocupada). O custo é o tempo de
detecção: no pior caso ~``INTERVALO * FALHAS_TOLERADAS + TIMEOUT``
(2 * 2 + 1 = 5 s com os valores padrão).
"""
import os
import threading
import time

from ..estado import ID_AGENCIA, registro, relogio
from . import bully

INTERVALO = float(os.environ.get("HEARTBEAT_INTERVALO", "2"))
FALHAS_TOLERADAS = int(os.environ.get("HEARTBEAT_FALHAS", "2"))
ATRASO_INICIAL = 1.0  # s - deixa o uvicorn abrir a porta antes da 1a eleição


def _laco() -> None:
    time.sleep(ATRASO_INICIAL)
    bully.iniciar_eleicao("agencia iniciou")

    falhas = 0
    vigiada: int | None = None
    while True:
        time.sleep(INTERVALO)
        if bully.em_eleicao():
            continue

        lider = bully.lider_atual()
        if lider is None:
            bully.iniciar_eleicao("nenhuma lider conhecida")
            continue
        if lider == ID_AGENCIA:
            falhas, vigiada = 0, None
            continue
        if lider != vigiada:  # trocou de líder: zera a contagem
            falhas, vigiada = 0, lider

        if bully.consultar_lider_de(lider) is not None:
            falhas = 0
            continue

        falhas += 1
        if falhas < FALHAS_TOLERADAS:
            continue

        falhas = 0
        if bully.esquecer_lider(lider):
            registro.registrar(
                "LIDER_INALCANCAVEL",
                relogio.evento_local(),
                {"lider": lider, "falhasSeguidas": FALHAS_TOLERADAS, "intervaloS": INTERVALO},
            )
            bully.iniciar_eleicao(f"lider {lider} nao respondeu ao heartbeat")


def iniciar() -> threading.Thread:
    thread = threading.Thread(target=_laco, name=f"heartbeat-agencia-{ID_AGENCIA}", daemon=True)
    thread.start()
    return thread
