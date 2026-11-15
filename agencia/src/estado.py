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
import threading
from datetime import datetime, timezone

from . import config
from .services.registro_eventos import RegistroEventos
from .services.relogio_vetorial import RelogioVetorial

ID_AGENCIA = int(os.environ.get("AGENCIA_ID", "0"))

if not any(a["id"] == ID_AGENCIA for a in config.AGENCIAS):
    raise SystemExit(
        f"Agencia {ID_AGENCIA} nao configurada em config.py "
        f"(validas: {[a['id'] for a in config.AGENCIAS]})"
    )

# Instante em que este processo subiu: o log .jsonl acumula execuções
# anteriores, cujos vetores (que recomeçam do zero) não são comparáveis aos atuais.
INICIO_PROCESSO = datetime.now(timezone.utc).isoformat()

relogio = RelogioVetorial(ID_AGENCIA, config.NUMERO_AGENCIAS)
registro = RegistroEventos(f"agencia-{ID_AGENCIA}")

# id_conta -> {"id": int, "nomeAluno": str, "saldo": float, "vetor": list[int]}
#
# Sprint 3: "vetor" é a VERSÃO da conta - o carimbo vetorial da última
# operação que alterou o saldo. O app Flutter guarda essa versão junto do saldo
# em cache e a devolve na sincronização offline-first (POST /sync/operacoes),
# para o servidor detectar se a conta mudou enquanto o app estava offline.
contas: dict[int, dict] = {}

# Protege "ler saldo/versão -> decidir -> alterar" contra o threadpool do
# FastAPI e a thread do consumidor RabbitMQ. Reentrante porque a sincronização
# reaproveita as mesmas regras de depósito/saque.
trava_contas = threading.RLock()

# Sprint 3: resultados das operações offline já sincronizadas (idOperacao ->
# resposta). Torna POST /sync/operacoes idempotente: se o app reenviar uma
# operação porque a resposta se perdeu, ela não é aplicada duas vezes.
operacoes_sincronizadas: dict[str, dict] = {}
