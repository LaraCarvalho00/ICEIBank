"""Configuração e particionamento de contas entre as agências do ICEIBank.

Cada conta pertence a exatamente UMA agência (partição, não replicação): dado o
número da conta, a agência responsável é ``id_conta % NUMERO_AGENCIAS``. Neste
sprint o número de agências é fixo em 3.

Exemplo: conta 0 -> Agência 0, conta 1 -> Agência 1, conta 2 -> Agência 2,
conta 3 -> Agência 0 (de novo), e assim por diante.
"""
import os

# OFFSET pessoal (dois últimos dígitos da matrícula/RA). Só é necessário para
# rodar em máquina compartilhada do laboratório, evitando conflito de portas.
# Pode ser sobrescrito por variável de ambiente, ex.: OFFSET=42
OFFSET = int(os.environ.get("OFFSET", "0"))

NUMERO_AGENCIAS = 3
PORTA_BASE = 4000 + OFFSET

AGENCIAS = [
    {"id": 0, "url": f"http://localhost:{PORTA_BASE}"},
    {"id": 1, "url": f"http://localhost:{PORTA_BASE + 1}"},
    {"id": 2, "url": f"http://localhost:{PORTA_BASE + 2}"},
]


def agencia_responsavel(id_conta: int) -> int:
    """Retorna o id da agência dona da conta informada."""
    return id_conta % NUMERO_AGENCIAS


def url_agencia(id_agencia: int) -> str:
    """URL base de uma agência (usada nas chamadas REST entre agências)."""
    for agencia in AGENCIAS:
        if agencia["id"] == id_agencia:
            return agencia["url"]
    raise ValueError(f"Agência {id_agencia} não configurada em config.py")


def porta_agencia(id_agencia: int) -> int:
    """Porta TCP em que uma agência escuta."""
    return PORTA_BASE + id_agencia
