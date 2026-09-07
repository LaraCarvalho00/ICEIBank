"""Autenticação via JWT (Parte F).

Decisões de design (detalhadas e justificadas em RESPOSTAS.md):

- **Credenciais:** usuário + senha. Não há cadastro nem banco neste sprint, então
  o store de usuários é fixo em memória, com as senhas guardadas como hash
  PBKDF2-HMAC-SHA256 + salt aleatório por usuário (nunca em texto puro) e
  comparação em tempo constante.
- **Token:** HS256, expira em ``JWT_EXPIRACAO_MIN`` minutos (padrão 30). Claims:
  ``sub`` (usuário), ``escopo``, ``iat``, ``exp``.
- **Chamada interna entre agências** (``creditar-remoto``): usa um token de
  escopo ``"interno"``, emitido pela agência de origem com o mesmo segredo e
  validade curta. Não reaproveita o token do usuário final.
"""
import hashlib
import hmac
import os
import sys
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Header, HTTPException

_SEGREDO_PADRAO = "iceibank-dev-segredo-inseguro-troque-em-producao"
JWT_SEGREDO = os.environ.get("JWT_SEGREDO", _SEGREDO_PADRAO)
JWT_ALGORITMO = "HS256"
JWT_EXPIRACAO_MIN = int(os.environ.get("JWT_EXPIRACAO_MIN", "30"))
TOKEN_INTERNO_EXPIRACAO_SEG = 30

if JWT_SEGREDO == _SEGREDO_PADRAO:
    print(
        "[seguranca] AVISO: usando JWT_SEGREDO padrao (inseguro). "
        "Defina a variavel de ambiente JWT_SEGREDO em producao.",
        file=sys.stderr,
    )


# --- senhas -----------------------------------------------------------------

def _hash_senha(senha: str, salt: bytes) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", senha.encode(), salt, 200_000)


def _novo_usuario(senha: str) -> dict:
    salt = os.urandom(16)
    return {"salt": salt, "hash": _hash_senha(senha, salt)}


# Store fixo: em um sistema real viria de um banco de dados.
_USUARIOS = {
    "lara": _novo_usuario(os.environ.get("SENHA_LARA", "iceibank")),
    "allan": _novo_usuario(os.environ.get("SENHA_ALLAN", "iceibank")),
}


def autenticar(usuario: str, senha: str) -> bool:
    reg = _USUARIOS.get(usuario)
    if reg is None:
        # Gasta o mesmo tempo mesmo com usuário inexistente (evita oráculo de timing).
        _hash_senha(senha, b"0" * 16)
        return False
    return hmac.compare_digest(_hash_senha(senha, reg["salt"]), reg["hash"])


# --- tokens ---------------------------------------------------------------------

def criar_token(sub: str, escopo: str = "usuario", expira_em: timedelta | None = None) -> str:
    agora = datetime.now(timezone.utc)
    if expira_em is None:
        expira_em = timedelta(minutes=JWT_EXPIRACAO_MIN)
    payload = {"sub": sub, "escopo": escopo, "iat": agora, "exp": agora + expira_em}
    return jwt.encode(payload, JWT_SEGREDO, algorithm=JWT_ALGORITMO)


def criar_token_interno(sub: str) -> str:
    """Token curto para a chamada agência-a-agência (escopo 'interno')."""
    return criar_token(
        sub, escopo="interno", expira_em=timedelta(seconds=TOKEN_INTERNO_EXPIRACAO_SEG)
    )


def _decodificar(authorization: str | None) -> dict:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Token ausente. Use 'Authorization: Bearer <token>'.")
    token = authorization[7:].strip()
    try:
        return jwt.decode(token, JWT_SEGREDO, algorithms=[JWT_ALGORITMO])
    except jwt.ExpiredSignatureError:
        raise HTTPException(401, "Token expirado.")
    except jwt.InvalidTokenError:
        raise HTTPException(401, "Token invalido.")


def requer_token(authorization: str | None = Header(default=None)) -> dict:
    """Dependency: exige um JWT válido e não expirado (autenticação)."""
    return _decodificar(authorization)


def requer_token_interno(authorization: str | None = Header(default=None)) -> dict:
    """Dependency da chamada agência-a-agência: exige token de escopo 'interno'."""
    payload = _decodificar(authorization)
    if payload.get("escopo") != "interno":
        raise HTTPException(
            403, "Endpoint interno: requer token de servico (escopo 'interno')."
        )
    return payload
