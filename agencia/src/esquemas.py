"""Modelos Pydantic dos corpos de requisição (a camada de entrada da API).

Os nomes dos campos seguem o roteiro (camelCase) para casar com o JSON usado
nos exemplos de teste.
"""
from pydantic import BaseModel, Field


class CriarContaIn(BaseModel):
    id: int
    nomeAluno: str
    saldoInicial: float = 0


class ValorIn(BaseModel):
    valor: float = Field(gt=0, description="Valor da operação, sempre positivo.")


class TransferenciaIn(BaseModel):
    idOrigem: int
    idDestino: int
    valor: float = Field(gt=0)


class CreditarRemotoIn(BaseModel):
    valor: float = Field(gt=0)
    timestampLamport: int
    origemAgencia: int


class LoginIn(BaseModel):
    usuario: str
    senha: str
