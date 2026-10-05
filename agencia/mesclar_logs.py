"""Linha do tempo causal das 3 agências (Parte D - relógio vetorial).

Lê todos os ``data/eventos-*.jsonl`` e:

1. imprime um único fluxo de eventos ordenado por hora de parede (só para
   leitura - a hora de parede NÃO decide causalidade);
2. lista os pares de eventos de agências DIFERENTES que são comprovadamente
   CONCORRENTES (nenhum vetor é <= o outro);
3. confere as transferências entre agências: cada ``TRANSFERENCIA_PUBLICADA``
   é casada (pelo ``idMensagem``) com o crédito na agência de destino, e o par
   tem de dar ``ANTES`` - relação causal, nunca concorrente.

Rodar depois de gerar alguns eventos:

    uv run python mesclar_logs.py              # mostra até 50 pares concorrentes
    uv run python mesclar_logs.py --limite 0   # mostra todos
"""
import argparse
import json
import os
import sys
from itertools import combinations

from src.services.relogio_vetorial import comparar

PASTA_DADOS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")

TIPOS_CREDITO_REMOTO = {"TRANSFERENCIA_CREDITO_REMOTO", "CREDITO_REMOTO_FALHOU"}


def carregar_eventos() -> list[dict]:
    eventos: list[dict] = []
    ignorados = 0
    if not os.path.isdir(PASTA_DADOS):
        return eventos
    for nome in sorted(os.listdir(PASTA_DADOS)):
        if not (nome.startswith("eventos-") and nome.endswith(".jsonl")):
            continue
        with open(os.path.join(PASTA_DADOS, nome), encoding="utf-8") as arquivo:
            for linha in arquivo:
                linha = linha.strip()
                if not linha:
                    continue
                evento = json.loads(linha)
                if "timestampVetorial" not in evento:  # log antigo (Lamport)
                    ignorados += 1
                    continue
                eventos.append(evento)
    if ignorados:
        print(f"(aviso: {ignorados} evento(s) sem timestampVetorial ignorados - logs do Sprint 1?)\n")
    return eventos


def rotulo(e: dict) -> str:
    return f"[{e['agencia']}] {e['tipo']} {e['timestampVetorial']}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--limite", type=int, default=50, help="máx. de pares concorrentes exibidos (0 = todos)")
    args = parser.parse_args()

    eventos = carregar_eventos()
    if not eventos:
        print(f"Nenhum evento encontrado em {PASTA_DADOS}")
        print("Rode algumas operacoes nas agencias primeiro.")
        sys.exit(0)

    eventos.sort(key=lambda e: e["horaParede"])

    print("=== Linha do tempo (ordenada por hora de parede) ===")
    for e in eventos:
        detalhes = json.dumps(e["detalhes"], ensure_ascii=False)
        print(f"{e['horaParede'][11:23]}  {e['agencia']:<10} vetor={str(e['timestampVetorial']):<10} {e['tipo']:<30} {detalhes}")

    # ---- Pares concorrentes entre agências diferentes ----
    concorrentes = [
        (e1, e2)
        for e1, e2 in combinations(eventos, 2)
        if e1["agencia"] != e2["agencia"]
        and comparar(e1["timestampVetorial"], e2["timestampVetorial"]) == "CONCORRENTES"
    ]
    print(f"\n=== Pares de eventos CONCORRENTES entre agencias diferentes ({len(concorrentes)}) ===")
    if not concorrentes:
        print("(nenhum par concorrente encontrado - gere eventos independentes em agencias diferentes e rode de novo)")
    exibir = concorrentes if args.limite <= 0 else concorrentes[: args.limite]
    for e1, e2 in exibir:
        print(f"{rotulo(e1)}  ||  {rotulo(e2)}")
    if len(exibir) < len(concorrentes):
        print(f"... e mais {len(concorrentes) - len(exibir)} (use --limite 0 para ver todos)")

    # ---- Transferências entre agências: o par envio/recebimento é causal ----
    publicadas = {e["detalhes"].get("idMensagem"): e for e in eventos if e["tipo"] == "TRANSFERENCIA_PUBLICADA"}
    creditos = [e for e in eventos if e["tipo"] in TIPOS_CREDITO_REMOTO]
    print(f"\n=== Transferencias entre agencias: publicacao -> credito remoto ({len(publicadas)}) ===")
    if not publicadas:
        print("(nenhuma transferencia entre agencias nos logs)")
    for id_msg, envio in publicadas.items():
        recebimentos = [c for c in creditos if c["detalhes"].get("idMensagem") == id_msg]
        if not recebimentos:
            print(f"{rotulo(envio)}  ->  (ainda nao consumida / sem registro no destino)")
            continue
        for receb in recebimentos:
            relacao = comparar(envio["timestampVetorial"], receb["timestampVetorial"])
            ok = "OK, causal" if relacao == "ANTES" else "INESPERADO"
            print(f"{rotulo(envio)}  ->  {rotulo(receb)}   relacao={relacao} ({ok})")


if __name__ == "__main__":
    main()
