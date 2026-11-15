"""Sincronização offline-first (Sprint 3, Parte E).

    POST /sync/operacoes   (JWT de usuário)

O app Flutter guarda as operações feitas sem conexão numa fila local e, ao
reconectar, envia uma por vez, em ordem. Cada uma traz o ``vetorBase``: a
versão da conta (``conta["vetor"]``) que o app conhecia quando o usuário fez
a operação. O servidor compara esse vetor com a versão atual da conta
(``comparar``, a mesma função pura do ``mesclar_logs.py`` do Sprint 2):

- ``IGUAIS``: ninguém mexeu na conta desde que o app a viu. A operação offline
  é o próximo passo natural da história da conta -> aplica (200).
- ``ANTES``: a conta tem escritas que o app NÃO viu (depósito pelo frontend web,
  crédito vindo de outra agência...). Essas escritas e a operação offline são
  CONCORRENTES: nenhuma estava no passado causal da outra. Para um saque, o
  servidor não escolhe por conta própria -> 409 com o estado atual da conta e as escritas
  concorrentes, para o usuário decidir no app (reaplicar ou descartar).
- ``DEPOIS``/``CONCORRENTES``: o app diz conhecer uma versão que o servidor não
  tem. Acontece quando a agência reiniciou (o relógio vive em memória e voltou
  a zero) -> também 409: a base do app não vale mais.

Por que não aplicar sempre e pronto: o saldo que o usuário viu na tela offline
(UI otimista) foi calculado sobre ``vetorBase``. Aplicar um saque sobre uma
versão diferente pode dar um resultado que ninguém viu nem aprovou.

Funcionalidade adicional (seção 2.1): no caso ``ANTES``, um DEPÓSITO é
mesclado automaticamente (200, ``"status": "MESCLADA"``) - ver o comentário
em ``sincronizar``. Saques continuam indo para o 409.

Idempotência: se a resposta se perder no caminho, o app reenvia a mesma
``idOperacao``; o resultado guardado é devolvido sem aplicar de novo.
"""
import json
import os

from fastapi import HTTPException
from fastapi.responses import JSONResponse

from .. import config
from ..esquemas import OperacaoOffline
from ..estado import ID_AGENCIA, INICIO_PROCESSO, contas, operacoes_sincronizadas, registro, relogio, trava_contas
from ..services.relogio_vetorial import comparar
from .contas_controller import aplicar_deposito, aplicar_saque

# Funcionalidade adicional - pode ser desligada (MESCLAR_DEPOSITOS=0) para ver
# o conflito "puro" (409) também em depósitos.
MESCLAR_DEPOSITOS = os.environ.get("MESCLAR_DEPOSITOS", "1") != "0"


def _escritas_nao_vistas(id_conta: int, vetor_base: list[int], limite: int = 20) -> list[dict]:
    """Eventos do log desta agência sobre a conta que NÃO estão no passado
    causal de ``vetor_base`` - as escritas concorrentes com a operação offline."""
    campos = ("id", "idConta", "idOrigem", "idDestino")
    achados: list[dict] = []
    try:
        with open(registro.caminho_arquivo, encoding="utf-8") as arquivo:
            for linha in arquivo:
                linha = linha.strip()
                if not linha:
                    continue
                evento = json.loads(linha)
                detalhes = evento.get("detalhes", {})
                vetor = evento.get("timestampVetorial")
                if not isinstance(vetor, list) or not any(detalhes.get(c) == id_conta for c in campos):
                    continue
                if evento["tipo"].startswith("SYNC_") or evento.get("horaParede", "") < INICIO_PROCESSO:
                    continue
                if comparar(vetor, vetor_base) not in ("ANTES", "IGUAIS"):
                    achados.append(
                        {"tipo": evento["tipo"], "vetor": vetor, "horaParede": evento["horaParede"], "detalhes": detalhes}
                    )
    except FileNotFoundError:
        pass
    return achados[-limite:]


def sincronizar(op: OperacaoOffline):
    dono = config.agencia_responsavel(op.idConta)
    if dono != ID_AGENCIA:
        raise HTTPException(400, f"Conta {op.idConta} pertence a agencia {dono}; sincronize la.")

    with trava_contas:
        if op.idOperacao in operacoes_sincronizadas:
            return {**operacoes_sincronizadas[op.idOperacao], "status": "JA_APLICADA"}

        conta = contas.get(op.idConta)
        if conta is None:
            raise HTTPException(404, "Conta nao encontrada nesta agencia.")

        versao = conta["vetor"]
        relacao = comparar(op.vetorBase, versao)

        # Funcionalidade adicional (seção 2.1): mesclagem automática de
        # operações comutativas. Um DEPÓSITO concorrente com escritas que o app
        # não viu pode ser aplicado sobre a versão atual sem risco: somar um
        # valor positivo nunca invalida o saldo que essas escritas produziram,
        # e a ordem entre somas não muda o resultado (o mesmo princípio de um
        # contador CRDT). O conflito continua DETECTADO e registrado
        # (SYNC_MESCLADA, com as escritas concorrentes), só não exige decisão
        # do usuário. Um SAQUE nunca é mesclado: ele depende do saldo que o
        # usuário viu, e esse saldo mudou.
        if relacao == "ANTES" and op.tipo == "DEPOSITO" and MESCLAR_DEPOSITOS:
            nao_vistas = _escritas_nao_vistas(op.idConta, op.vetorBase)
            extra = {
                "origem": "sync-offline-mesclada",
                "idOperacao": op.idOperacao,
                "vetorBase": op.vetorBase,
                "vetorServidorAntes": versao,
            }
            atualizada = aplicar_deposito(op.idConta, op.valor, extra)
            registro.registrar(
                "SYNC_MESCLADA",
                relogio.evento_local(),
                {"idOperacao": op.idOperacao, "idConta": op.idConta, "valor": op.valor,
                 "vetorBase": op.vetorBase, "vetorServidorAntes": versao, "relacao": relacao},
            )
            resultado = {
                "status": "MESCLADA",
                "motivo": "Deposito concorrente aplicado sobre a versao atual (operacao comutativa).",
                "idOperacao": op.idOperacao,
                "relacao": relacao,
                "vetorBase": op.vetorBase,
                "vetorServidorAntes": versao,
                "escritasConcorrentes": nao_vistas,
                "conta": atualizada,
            }
            operacoes_sincronizadas[op.idOperacao] = resultado
            return resultado

        if relacao != "IGUAIS":
            if relacao == "ANTES":
                motivo = "A conta foi alterada enquanto o app estava offline (escritas concorrentes)."
            else:
                motivo = "O app conhece uma versao que o servidor nao tem (a agencia reiniciou?)."
            nao_vistas = _escritas_nao_vistas(op.idConta, op.vetorBase) if relacao == "ANTES" else []
            registro.registrar(
                "SYNC_CONFLITO",
                relogio.evento_local(),
                {
                    "idOperacao": op.idOperacao,
                    "idConta": op.idConta,
                    "tipo": op.tipo,
                    "valor": op.valor,
                    "vetorBase": op.vetorBase,
                    "vetorServidor": versao,
                    "relacao": relacao,
                },
            )
            return JSONResponse(
                status_code=409,
                content={
                    "status": "CONFLITO",
                    "motivo": motivo,
                    "relacao": relacao,
                    "idOperacao": op.idOperacao,
                    "vetorBase": op.vetorBase,
                    "vetorServidor": versao,
                    "contaServidor": dict(conta),
                    "escritasConcorrentes": nao_vistas,
                },
            )

        extra = {"origem": "sync-offline", "idOperacao": op.idOperacao, "vetorBase": op.vetorBase}
        if op.tipo == "DEPOSITO":
            atualizada = aplicar_deposito(op.idConta, op.valor, extra)
        else:
            atualizada = aplicar_saque(op.idConta, op.valor, extra)  # 400 se faltar saldo

        resultado = {"status": "APLICADA", "idOperacao": op.idOperacao, "relacao": relacao, "conta": atualizada}
        operacoes_sincronizadas[op.idOperacao] = resultado
        return resultado
