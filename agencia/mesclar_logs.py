"""Linha do tempo unificada das 3 agências, ordenada pelo relógio de Lamport.

Lê todos os ``data/eventos-*.jsonl`` e imprime um único fluxo de eventos
ordenado por ``timestampLamport``. Rodar depois de gerar alguns eventos:

    uv run python mesclar_logs.py

Eventos com o MESMO ``timestampLamport`` vindos de agências diferentes são
concorrentes: o relógio de Lamport, sozinho, não define ordem entre eles (é o
que motiva o relógio vetorial do Sprint 2).
"""
import json
import os
import sys

PASTA_DADOS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")


def carregar_eventos() -> list[dict]:
    eventos: list[dict] = []
    if not os.path.isdir(PASTA_DADOS):
        return eventos
    for nome in sorted(os.listdir(PASTA_DADOS)):
        if not (nome.startswith("eventos-") and nome.endswith(".jsonl")):
            continue
        with open(os.path.join(PASTA_DADOS, nome), encoding="utf-8") as arquivo:
            for linha in arquivo:
                linha = linha.strip()
                if linha:
                    eventos.append(json.loads(linha))
    return eventos


def main() -> None:
    eventos = carregar_eventos()
    if not eventos:
        print(f"Nenhum evento encontrado em {PASTA_DADOS}")
        print("Rode algumas operacoes nas agencias primeiro.")
        sys.exit(0)

    # Ordena por timestamp de Lamport. O desempate por nome de agência é
    # arbitrario de proposito: eventos com o mesmo timestamp sao concorrentes e
    # nenhuma ordem entre eles e "mais correta" que a outra.
    eventos.sort(key=lambda e: (e["timestampLamport"], e["agencia"]))

    # Marca os timestamps que aparecem em mais de um evento (candidatos a
    # eventos concorrentes).
    contagem: dict[int, int] = {}
    for e in eventos:
        contagem[e["timestampLamport"]] = contagem.get(e["timestampLamport"], 0) + 1

    print("=== Linha do tempo unificada (ordenada por relogio de Lamport) ===")
    for e in eventos:
        ts = e["timestampLamport"]
        marca = "  <== timestamp repetido" if contagem[ts] > 1 else ""
        detalhes = json.dumps(e["detalhes"], ensure_ascii=False)
        print(
            f"[Lamport {ts:>3}] ({e['horaParede']}) "
            f"{e['agencia']:<10} {e['tipo']:<28} {detalhes}{marca}"
        )

    repetidos = sorted(ts for ts, n in contagem.items() if n > 1)
    if repetidos:
        print(
            f"\nTimestamps de Lamport repetidos (eventos possivelmente "
            f"concorrentes): {repetidos}"
        )
    else:
        print(
            "\nNenhum timestamp repetido nesta execucao. Gere mais eventos "
            "concorrentes (operacoes independentes em agencias diferentes)."
        )


if __name__ == "__main__":
    main()
