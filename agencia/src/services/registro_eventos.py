"""Registro de eventos de uma agência em arquivo ``.jsonl`` (uma linha JSON por
evento). Esses arquivos são a matéria-prima da linha do tempo unificada
(``mesclar_logs.py``, seção 10 do roteiro).

Cada evento guarda dois carimbos de tempo:

- ``timestampLamport``: o relógio lógico - usado para ordenar a linha do tempo;
- ``horaParede``: o relógio físico da máquina, apenas para comparação. NÃO é
  usado para nenhuma decisão do sistema.
"""
import json
import os
import threading
from datetime import datetime, timezone


class RegistroEventos:
    def __init__(self, nome_agencia: str) -> None:
        self.nome_agencia = nome_agencia
        pasta_dados = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..", "..", "data"
        )
        os.makedirs(pasta_dados, exist_ok=True)
        self.caminho_arquivo = os.path.join(
            pasta_dados, f"eventos-{nome_agencia}.jsonl"
        )
        self._lock = threading.Lock()

    def registrar(self, tipo: str, timestamp_lamport: int, detalhes: dict) -> dict:
        evento = {
            "agencia": self.nome_agencia,
            "tipo": tipo,
            "timestampLamport": timestamp_lamport,
            "horaParede": datetime.now(timezone.utc).isoformat(),
            "detalhes": detalhes,
        }
        with self._lock:
            with open(self.caminho_arquivo, "a", encoding="utf-8") as arquivo:
                arquivo.write(json.dumps(evento, ensure_ascii=False) + "\n")
        print(f"[Lamport {timestamp_lamport}] {tipo} {detalhes}")
        return evento
