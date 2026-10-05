"""Mapa de rotas -> controllers (MVC: a camada de roteamento).

Mantém a definição das URLs separada da regra de negócio (que fica nos
controllers) e da autenticação (Parte F):

- ``/auth/login`` é aberta;
- as rotas de conta e ``/transferencias`` exigem um JWT de usuário
  (``Authorization: Bearer <token>``).

A rota interna ``/contas/{id}/creditar-remoto`` do Sprint 1 deixou de existir:
no Sprint 2 o crédito vindo de outra agência chega pelo RabbitMQ (ver
``main.py`` e ``services/mensageria.py``).
"""
from fastapi import APIRouter, Depends

from .controllers import (
    auth_controller,
    contas_controller,
    historico_controller,
    transferencias_controller,
)
from .seguranca import requer_token

router = APIRouter()

# ---- Autenticação (aberta) ----
router.add_api_route("/auth/login", auth_controller.login, methods=["POST"], tags=["auth"])

# ---- Contas (exigem token de usuário) ----
_usuario = [Depends(requer_token)]
router.add_api_route(
    "/contas",
    contas_controller.criar_conta,
    methods=["POST"],
    status_code=201,
    dependencies=_usuario,
    tags=["contas"],
)
router.add_api_route(
    "/contas/{id_conta}",
    contas_controller.consultar_saldo,
    methods=["GET"],
    dependencies=_usuario,
    tags=["contas"],
)
router.add_api_route(
    "/contas/{id_conta}/depositar",
    contas_controller.depositar,
    methods=["POST"],
    dependencies=_usuario,
    tags=["contas"],
)
router.add_api_route(
    "/contas/{id_conta}/sacar",
    contas_controller.sacar,
    methods=["POST"],
    dependencies=_usuario,
    tags=["contas"],
)
# Funcionalidade adicional (seção 2.1): histórico de transações por conta.
router.add_api_route(
    "/contas/{id_conta}/historico",
    historico_controller.historico,
    methods=["GET"],
    dependencies=_usuario,
    tags=["contas"],
)

# ---- Transferências ----
router.add_api_route(
    "/transferencias",
    transferencias_controller.transferir,
    methods=["POST"],
    dependencies=_usuario,
    tags=["transferencias"],
)
