"""Controller da eleição de líder (Sprint 3, Parte A).

Só traduz HTTP <-> ``services/bully.py``, onde está o algoritmo.

- ``POST /bully/eleicao`` e ``POST /bully/coordenador`` são rotas agência ->
  agência: exigem JWT de escopo ``"interno"`` (``requer_token_interno``);
- ``GET /bully/lider`` é aberta: o heartbeat das outras agências e o painel do
  app Flutter a consultam sem login.
"""
from ..esquemas import MensagemCoordenador, MensagemEleicao
from ..services import bully


def eleicao(msg: MensagemEleicao) -> dict:
    return bully.receber_eleicao(msg.origemId, msg.vetor)


def coordenador(msg: MensagemCoordenador) -> dict:
    return bully.receber_coordenador(msg.liderId, msg.vetor)


def lider() -> dict:
    return bully.estado_publico()
