"""Teste isolado do relógio de Lamport, antes de plugá-lo na API
(roteiro, seção 6: "implementar e testar isoladamente, antes de plugar na API").

Rodar com:  uv run python verificar_lamport.py
"""
from src.services.relogio_lamport import RelogioLamport


def cenario_regras_basicas() -> None:
    r = RelogioLamport()
    assert r.evento_local() == 1
    assert r.evento_local() == 2
    assert r.ao_enviar() == 3            # regra 2: incrementa; anexa 3 à mensagem
    assert r.ao_receber(10) == 11        # regra 3: max(3, 10) + 1
    assert r.evento_local() == 12
    print("OK  regras basicas (evento_local / ao_enviar / ao_receber)")


def cenario_pergunta_6_4_2() -> None:
    """Agência 0 está no contador 10 e recebe uma mensagem com timestamp 3
    (de uma agência mais 'atrasada')."""
    r = RelogioLamport()
    for _ in range(10):
        r.evento_local()
    assert r.contador == 10
    novo = r.ao_receber(3)               # max(10, 3) + 1
    assert novo == 11
    print(f"OK  pergunta 6.4.2: contador 10 recebe ts 3 -> {novo} "
          "(a mensagem 'atrasada' nao puxa o relogio para tras; ele so avanca)")


def cenario_causalidade_entre_agencias() -> None:
    """Envio em A precede o recebimento em B: ts(envio) < ts(recebimento)."""
    a, b = RelogioLamport(), RelogioLamport()
    a.evento_local()                    # a=1
    ts_envio = a.ao_enviar()            # a=2, mensagem carrega 2
    b.evento_local()                    # b=1
    b.evento_local()                    # b=2
    ts_receb = b.ao_receber(ts_envio)   # b = max(2, 2) + 1 = 3
    assert ts_envio == 2 and ts_receb == 3
    assert ts_envio < ts_receb          # relação causal preservada
    print(f"OK  causalidade: ts(envio)={ts_envio} < ts(recebimento)={ts_receb}")


if __name__ == "__main__":
    cenario_regras_basicas()
    cenario_pergunta_6_4_2()
    cenario_causalidade_entre_agencias()
    print("\nTodos os cenarios passaram.")
