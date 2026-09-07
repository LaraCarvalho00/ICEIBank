"""Mapa de rotas -> controllers (MVC: a camada de roteamento).

Mantém a definição das URLs separada da regra de negócio (que fica nos
controllers).
"""
from fastapi import APIRouter

from .controllers import contas_controller, transferencias_controller

router = APIRouter()

# ---- Contas ----
router.add_api_route(
    "/contas", contas_controller.criar_conta, methods=["POST"], status_code=201, tags=["contas"]
)
router.add_api_route(
    "/contas/{id_conta}", contas_controller.consultar_saldo, methods=["GET"], tags=["contas"]
)
router.add_api_route(
    "/contas/{id_conta}/depositar",
    contas_controller.depositar,
    methods=["POST"],
    tags=["contas"],
)
router.add_api_route(
    "/contas/{id_conta}/sacar", contas_controller.sacar, methods=["POST"], tags=["contas"]
)

# ---- Transferências ----
router.add_api_route(
    "/transferencias",
    transferencias_controller.transferir,
    methods=["POST"],
    tags=["transferencias"],
)
router.add_api_route(
    "/contas/{id_conta}/creditar-remoto",
    transferencias_controller.creditar_remoto,
    methods=["POST"],
    tags=["transferencias"],
)
