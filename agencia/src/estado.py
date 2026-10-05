"""Estado em memória do processo - uma instância por agência.

Cada agência é o MESMO código, identificada pela variável de ambiente
``AGENCIA_ID`` (0, 1 ou 2). Este módulo é importado uma única vez por processo,
então ``relogio``, ``registro`` e ``contas`` são efetivamente singletons da
agência.

Ainda não há banco de dados (proposital): reiniciar o processo zera as contas.
No Sprint 2 isso tem uma consequência visível - um crédito que fica retido na
fila do RabbitMQ enquanto a agência está fora do ar chega, na volta, a uma
agência que já não tem a conta (ver RESPOSTAS.md, Parte C).
"""
import os

from . import config
from .services.registro_eventos import RegistroEventos
from .services.relogio_vetorial import RelogioVetorial

ID_AGENCIA = int(os.environ.get("AGENCIA_ID", "0"))

if not any(a["id"] == ID_AGENCIA for a in config.AGENCIAS):
    raise SystemExit(
        f"Agencia {ID_AGENCIA} nao configurada em config.py "
        f"(validas: {[a['id'] for a in config.AGENCIAS]})"
    )

relogio = RelogioVetorial(ID_AGENCIA, config.NUMERO_AGENCIAS)
registro = RegistroEventos(f"agencia-{ID_AGENCIA}")

# id_conta -> {"id": int, "nomeAluno": str, "saldo": float}
contas: dict[int, dict] = {}
