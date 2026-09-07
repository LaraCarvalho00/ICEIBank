"""Estado em memória do processo - uma instância por agência.

Cada agência é o MESMO código, identificada pela variável de ambiente
``AGENCIA_ID`` (0, 1 ou 2). Este módulo é importado uma única vez por processo,
então ``relogio``, ``registro`` e ``contas`` são efetivamente singletons da
agência.

Não há banco de dados neste sprint (proposital: o foco é REST/MVC + relógio de
Lamport). Reiniciar o processo zera as contas - é esperado.
"""
import os

from . import config
from .services.registro_eventos import RegistroEventos
from .services.relogio_lamport import RelogioLamport

ID_AGENCIA = int(os.environ.get("AGENCIA_ID", "0"))

if not any(a["id"] == ID_AGENCIA for a in config.AGENCIAS):
    raise SystemExit(
        f"Agencia {ID_AGENCIA} nao configurada em config.py "
        f"(validas: {[a['id'] for a in config.AGENCIAS]})"
    )

relogio = RelogioLamport()
registro = RegistroEventos(f"agencia-{ID_AGENCIA}")

# id_conta -> {"id": int, "nomeAluno": str, "saldo": float}
contas: dict[int, dict] = {}
