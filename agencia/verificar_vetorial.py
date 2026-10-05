"""Teste isolado do relógio vetorial, antes de plugá-lo na API
(roteiro do Sprint 2, seção 3: "implemente e teste isoladamente antes de
integrar").

Rodar com:  uv run python verificar_vetorial.py
"""
from src.services.relogio_vetorial import RelogioVetorial, comparar


def cenario_regras_basicas() -> None:
    r = RelogioVetorial(id_agencia=0, numero_agencias=3)
    assert r.evento_local() == [1, 0, 0]
    assert r.ao_enviar() == [2, 0, 0]               # regra 2: anexa [2,0,0]
    assert r.ao_receber([0, 5, 1]) == [3, 5, 1]     # regra 3: max + incrementa a propria
    assert r.evento_local() == [4, 5, 1]
    print("OK  regras basicas (evento_local / ao_enviar / ao_receber)")


def cenario_copia_independente() -> None:
    """O vetor retornado é uma cópia: mexer nele não altera o relógio."""
    r = RelogioVetorial(1, 3)
    v = r.evento_local()
    v[1] = 99
    assert r.vetor == [0, 1, 0]
    print("OK  vetores retornados sao copias")


def cenario_transferencia_entre_agencias() -> None:
    """Ag0 envia para Ag1: o envio vem ANTES do recebimento (causal)."""
    a0, a1 = RelogioVetorial(0, 3), RelogioVetorial(1, 3)
    a0.evento_local()                      # a0 cria conta       [1,0,0]
    a1.evento_local()                      # a1 cria conta       [0,1,0]
    envio = a0.ao_enviar()                 # a0 publica credito  [2,0,0]
    receb = a1.ao_receber(envio)           # a1 consome          [2,2,0]
    assert envio == [2, 0, 0] and receb == [2, 2, 0]
    assert comparar(envio, receb) == "ANTES"
    print(f"OK  causal: envio {envio} -> recebimento {receb}")


def cenario_concorrentes() -> None:
    """Contas criadas em agências diferentes, sem mensagem entre elas."""
    a0, a2 = RelogioVetorial(0, 3), RelogioVetorial(2, 3)
    e0 = a0.evento_local()                 # [1,0,0]
    e2 = a2.evento_local()                 # [0,0,1]
    assert comparar(e0, e2) == "CONCORRENTES"
    print(f"OK  concorrentes: {e0} || {e2}")


def cenario_perguntas_6_4() -> None:
    assert comparar([3, 1, 0], [3, 2, 0]) == "ANTES"         # pergunta 2
    assert comparar([3, 1, 0], [1, 3, 0]) == "CONCORRENTES"  # pergunta 3
    print("OK  perguntas 6.4: [3,1,0] -> [3,2,0];  [3,1,0] || [1,3,0]")


def cenario_vetor_tamanho_errado() -> None:
    r = RelogioVetorial(0, 3)
    try:
        r.ao_receber([1, 2])
    except ValueError:
        print("OK  vetor recebido com tamanho errado e rejeitado")
    else:
        raise AssertionError("deveria rejeitar vetor de tamanho errado")


if __name__ == "__main__":
    cenario_regras_basicas()
    cenario_copia_independente()
    cenario_transferencia_entre_agencias()
    cenario_concorrentes()
    cenario_perguntas_6_4()
    cenario_vetor_tamanho_errado()
    print("\nTodos os cenarios passaram.")
