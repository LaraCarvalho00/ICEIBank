"""Gera um JWT já expirado, assinado com o segredo real da aplicação.

Serve para testar o cenário (c) da Parte F: requisição com token expirado -> 401.

    uv run python gerar_token_expirado.py
"""
from datetime import datetime, timedelta, timezone

import jwt

from src.seguranca import JWT_ALGORITMO, JWT_SEGREDO

agora = datetime.now(timezone.utc)
token = jwt.encode(
    {
        "sub": "lara",
        "escopo": "usuario",
        "iat": agora - timedelta(hours=2),
        "exp": agora - timedelta(hours=1),  # expirou há 1 hora
    },
    JWT_SEGREDO,
    algorithm=JWT_ALGORITMO,
)
print(token)
