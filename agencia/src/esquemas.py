"""Modelos Pydantic dos corpos de requisição (a camada de entrada da API).

Os nomes dos campos seguem o roteiro (camelCase) para casar com o JSON usado
nos exemplos de teste. As restrições (`Field(...)`, validadores) rejeitam
entradas inválidas com HTTP 422 antes de chegar ao controller.
"""
from pydantic import BaseModel, Field, model_validator


class CriarContaIn(BaseModel):
    id: int = Field(ge=0, description="Número da conta (inteiro >= 0).")
    nomeAluno: str = Field(min_length=1)
    saldoInicial: float = Field(default=0, ge=0)


class ValorIn(BaseModel):
    valor: float = Field(gt=0, description="Valor da operação, sempre positivo.")


class TransferenciaIn(BaseModel):
    idOrigem: int = Field(ge=0)
    idDestino: int = Field(ge=0)
    valor: float = Field(gt=0)

    @model_validator(mode="after")
    def _contas_diferentes(self):
        if self.idOrigem == self.idDestino:
            raise ValueError("idOrigem e idDestino devem ser contas diferentes")
        return self


class CreditarRemotoIn(BaseModel):
    valor: float = Field(gt=0)
    timestampLamport: int
    origemAgencia: int


class LoginIn(BaseModel):
    usuario: str = Field(min_length=1)
    senha: str = Field(min_length=1)
