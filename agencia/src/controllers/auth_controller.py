"""Controller de autenticação (Parte F).

POST /auth/login: recebe usuário + senha; se válidos, devolve um JWT.
"""
from fastapi import HTTPException

from ..esquemas import LoginIn
from ..seguranca import JWT_EXPIRACAO_MIN, autenticar, criar_token


def login(dados: LoginIn) -> dict:
    if not autenticar(dados.usuario, dados.senha):
        raise HTTPException(401, "Usuario ou senha invalidos.")
    token = criar_token(sub=dados.usuario)
    return {
        "access_token": token,
        "token_type": "bearer",
        "expira_em_min": JWT_EXPIRACAO_MIN,
    }
