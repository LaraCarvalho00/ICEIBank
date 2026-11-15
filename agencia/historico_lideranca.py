"""Linha do tempo de lideranças (Sprint 3, Parte C).

Equivalente em Python do ``historico-lideranca.js`` do roteiro. Lê os
``data/eventos-*.jsonl`` das 3 agências, separa os eventos da eleição (Bully)
e reconstrói:

1. o fluxo de eventos de eleição, agência por agência intercalada;
2. os **mandatos**: quem foi líder, de quando até quando e por que o mandato
   terminou (queda detectada pelo heartbeat, ou uma agência de ID maior que
   voltou e tomou a liderança);
3. o **tempo sem líder** de cada failover (da 1a detecção de queda até a
   próxima ``LIDER_ELEITO``);
4. a verificação causal: cada anúncio ``LIDER_ELEITO`` tem de vir ``ANTES``
   (relógio vetorial) do ``NOVO_LIDER`` que o reconhece em outra agência.

A hora de parede só ordena a exibição e mede durações - quem prova a ordem
causal é o vetor.

    uv run python historico_lideranca.py
    uv run python historico_lideranca.py --eventos   # mostra também cada evento
"""
import argparse
import sys
from datetime import datetime

from mesclar_logs import PASTA_DADOS, carregar_eventos
from src.services.relogio_vetorial import comparar

TIPOS_ELEICAO = {
    "ELEICAO_INICIADA",
    "ELEICAO_RECEBIDA",
    "ELEICAO_CEDIDA",
    "ELEICAO_IGNORADA",
    "LIDER_ELEITO",
    "NOVO_LIDER",
    "COORDENADOR_RECUSADO",
    "LIDER_INALCANCAVEL",
}


def id_agencia(evento: dict) -> int:
    return int(evento["agencia"].rsplit("-", 1)[1])


def hora(evento: dict) -> datetime:
    return datetime.fromisoformat(evento["horaParede"])


def curta(evento: dict) -> str:
    return evento["horaParede"][11:23]


def reconstruir_mandatos(eventos: list[dict]) -> list[dict]:
    """Percorre os eventos em ordem de hora de parede e abre/fecha mandatos.

    - ``LIDER_ELEITO`` da agência X abre um mandato de X (se X já era a líder,
      é só um reanúncio - o mandato continua);
    - ``LIDER_INALCANCAVEL`` sobre X (detectado por outra agência) fecha o
      mandato de X: queda;
    - ``LIDER_ELEITO`` de Y != X fecha o mandato de X, se ainda aberto: Y tomou
      a liderança (ex.: X tinha ID menor e Y voltou);
    - ``LIDER_ELEITO`` de X com a posição X do vetor MENOR que a do anúncio
      anterior: X reiniciou (o relógio vive em memória), novo mandato.
    """
    mandatos: list[dict] = []
    atual: dict | None = None

    for e in eventos:
        if e["tipo"] == "LIDER_ELEITO":
            lider = id_agencia(e)
            if atual is not None and atual["lider"] == lider and atual["fim"] is None:
                anterior = atual["ultimoAnuncio"]["timestampVetorial"][lider]
                if e["timestampVetorial"][lider] > anterior:
                    atual["reanuncios"] += 1
                    atual["ultimoAnuncio"] = e
                    continue
                # A própria posição do vetor voltou para trás: a agência
                # reiniciou (o relógio vive em memória) - é outro mandato.
                atual["fim"] = e
                atual["motivoFim"] = f"agencia {lider} reiniciou (vetor zerado)"
            elif atual is not None and atual["fim"] is None:
                atual["fim"] = e
                atual["motivoFim"] = f"agencia {lider} (ID maior) assumiu"
            atual = {"lider": lider, "inicio": e, "ultimoAnuncio": e, "fim": None, "motivoFim": None, "reanuncios": 0}
            mandatos.append(atual)
        elif e["tipo"] == "LIDER_INALCANCAVEL":
            caida = e["detalhes"].get("lider")
            if atual is not None and atual["lider"] == caida and atual["fim"] is None:
                atual["fim"] = e
                atual["motivoFim"] = f"queda detectada pelo heartbeat da agencia {id_agencia(e)}"
    return mandatos


def tempos_sem_lider(eventos: list[dict]) -> list[tuple[dict, dict | None]]:
    """(1a detecção de queda, próxima LIDER_ELEITO) para cada failover."""
    pares = []
    deteccao: dict | None = None
    for e in eventos:
        if e["tipo"] == "LIDER_INALCANCAVEL" and deteccao is None:
            deteccao = e
        elif e["tipo"] == "LIDER_ELEITO" and deteccao is not None:
            pares.append((deteccao, e))
            deteccao = None
    if deteccao is not None:
        pares.append((deteccao, None))
    return pares


def verificar_anuncios(eventos: list[dict]) -> list[tuple[dict, dict, str]]:
    """Casa cada ``LIDER_ELEITO`` de X com o primeiro ``NOVO_LIDER {lider: X}``
    de cada outra agência que veio depois dele (e antes do próximo anúncio de
    X) e compara os dois vetores. Um anúncio não reconhecido (ex.: a outra
    agência estava fora do ar) simplesmente não aparece."""
    resultado = []
    anuncios = [e for e in eventos if e["tipo"] == "LIDER_ELEITO"]
    for i, anuncio in enumerate(anuncios):
        x = id_agencia(anuncio)
        proximo = next((a for a in anuncios[i + 1:] if id_agencia(a) == x), None)
        ja_casadas: set[str] = set()
        for receb in eventos:
            if receb["tipo"] != "NOVO_LIDER" or receb["detalhes"].get("lider") != x:
                continue
            if receb["agencia"] in ja_casadas or hora(receb) < hora(anuncio):
                continue
            if proximo is not None and hora(receb) >= hora(proximo):
                break
            ja_casadas.add(receb["agencia"])
            rel = comparar(anuncio["timestampVetorial"], receb["timestampVetorial"])
            resultado.append((anuncio, receb, rel))
    return resultado


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--eventos", action="store_true", help="lista cada evento de eleicao")
    args = parser.parse_args()

    eventos = [e for e in carregar_eventos() if e["tipo"] in TIPOS_ELEICAO]
    if not eventos:
        print(f"Nenhum evento de eleicao em {PASTA_DADOS}. Suba as agencias primeiro.")
        sys.exit(0)
    eventos.sort(key=hora)

    if args.eventos:
        print("=== Eventos de eleicao (ordem de hora de parede) ===")
        for e in eventos:
            print(f"{curta(e)}  {e['agencia']:<10} vetor={str(e['timestampVetorial']):<12} {e['tipo']:<22} {e['detalhes']}")
        print()

    contagem: dict[str, int] = {}
    for e in eventos:
        contagem[e["tipo"]] = contagem.get(e["tipo"], 0) + 1
    print("=== Resumo ===")
    for tipo in sorted(contagem):
        print(f"  {tipo:<22} {contagem[tipo]}")

    print("\n=== Linha do tempo de liderancas ===")
    mandatos = reconstruir_mandatos(eventos)
    for n, m in enumerate(mandatos, 1):
        inicio = m["inicio"]
        if m["fim"] is None:
            fim, duracao, motivo = "(atual)     ", "", "ainda e a lider"
        else:
            fim = curta(m["fim"])
            duracao = f"{(hora(m['fim']) - hora(inicio)).total_seconds():.1f} s"
            motivo = m["motivoFim"]
        extra = f", {m['reanuncios']} reanuncio(s)" if m["reanuncios"] else ""
        print(
            f"#{n:<2} Agencia {m['lider']}  {curta(inicio)} -> {fim}  {duracao:>8}  "
            f"eleita com vetor {inicio['timestampVetorial']}{extra} | fim: {motivo}"
        )

    print("\n=== Failovers: tempo sem lider (deteccao da queda -> nova lider eleita) ===")
    pares = tempos_sem_lider(eventos)
    if not pares:
        print("(nenhuma queda de lider nos logs - derrube a lider e rode de novo)")
    for deteccao, eleita in pares:
        caida = deteccao["detalhes"].get("lider")
        if eleita is None:
            print(f"queda da agencia {caida} detectada as {curta(deteccao)} - nenhuma lider eleita depois ainda")
            continue
        segundos = (hora(eleita) - hora(deteccao)).total_seconds()
        print(
            f"agencia {caida} caiu: detectada as {curta(deteccao)} por {deteccao['agencia']}; "
            f"agencia {id_agencia(eleita)} eleita as {curta(eleita)} ({segundos:.2f} s sem lider)"
        )

    print("\n=== Verificacao causal: anuncio (LIDER_ELEITO) -> reconhecimento (NOVO_LIDER) ===")
    verificacoes = verificar_anuncios(eventos)
    erros = 0
    for anuncio, receb, rel in verificacoes:
        ok = rel == "ANTES"
        erros += not ok
        print(
            f"[{anuncio['agencia']}] LIDER_ELEITO {anuncio['timestampVetorial']} -> "
            f"[{receb['agencia']}] NOVO_LIDER {receb['timestampVetorial']}  relacao={rel} "
            f"({'OK, causal' if ok else 'INESPERADO'})"
        )
    if not verificacoes:
        print("(nenhum anuncio reconhecido nos logs)")
    elif erros == 0:
        print(f"Todos os {len(verificacoes)} reconhecimentos vem causalmente DEPOIS do anuncio.")


if __name__ == "__main__":
    main()
