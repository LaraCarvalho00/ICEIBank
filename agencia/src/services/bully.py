"""Eleição de líder entre as agências - algoritmo do Valentão (Bully).

Garcia-Molina (1982). Regra única de desempate: **vence o maior ID vivo**.

Mensagens (HTTP, JSON, sempre com o relógio vetorial anexado):

- ``POST /bully/eleicao``     ``{"origemId": i, "vetor": [...]}``
  enviada pela agência ``i`` a todas as agências de ID MAIOR. Quem recebe e
  está viva responde ``{"ok": true}`` ("eu assumo daqui") e convoca a sua
  própria eleição.
- ``POST /bully/coordenador`` ``{"liderId": j, "vetor": [...]}``
  enviada pela vencedora a todas as outras: "a líder agora sou eu".
- ``GET  /bully/lider``       consulta (aberta) de quem esta agência reconhece
  como líder - usada pelo heartbeat e pelo painel do app Flutter.

Fluxo de ``iniciar_eleicao``:

1. manda ELEIÇÃO para todas as agências de ID maior (timeout de 1 s cada);
2. se NENHUMA respondeu: ninguém maior está vivo -> esta agência vira líder e
   manda COORDENADOR para as outras;
3. se alguma respondeu: cede e espera o COORDENADOR por até
   ``ESPERA_COORDENADOR`` segundos. Se ele não chegar (a maior caiu no meio da
   eleição), recomeça do passo 1.

Concorrência: o estado (``_lider_atual``, ``_em_eleicao``) é lido e escrito
pela thread do heartbeat, pelas threads de eleição disparadas por mensagens
recebidas e pelo threadpool das rotas do FastAPI. Todo acesso passa por
``_lock`` - o mesmo cuidado que o relógio vetorial já tinha no Sprint 2.
"""
import threading
from datetime import datetime, timezone

import httpx

from .. import config
from ..estado import ID_AGENCIA, registro, relogio
from ..seguranca import cabecalho_interno

TIMEOUT_HTTP = 1.0          # s - sem resposta nesse prazo, a agência é tratada como morta
ESPERA_COORDENADOR = 3.0    # s - depois de ceder, quanto esperar o anúncio da vencedora

_lock = threading.Lock()
_lider_atual: int | None = None
_lider_desde: str | None = None
_em_eleicao = False
_coordenador_chegou = threading.Event()


# --- leitura do estado ---------------------------------------------------------------

def lider_atual() -> int | None:
    with _lock:
        return _lider_atual


def em_eleicao() -> bool:
    with _lock:
        return _em_eleicao


def estado_publico() -> dict:
    """Corpo de ``GET /bully/lider``."""
    with _lock:
        lider, desde, eleicao = _lider_atual, _lider_desde, _em_eleicao
    return {
        "idAgencia": ID_AGENCIA,
        "liderAtual": lider,
        "souLider": lider == ID_AGENCIA,
        "liderDesde": desde,
        "emEleicao": eleicao,
        "vetor": relogio.atual(),
    }


def _definir_lider(novo: int | None) -> int | None:
    """Troca a líder reconhecida; devolve a anterior."""
    global _lider_atual, _lider_desde
    with _lock:
        anterior = _lider_atual
        _lider_atual = novo
        if novo != anterior:
            _lider_desde = datetime.now(timezone.utc).isoformat() if novo is not None else None
        return anterior


def esquecer_lider(id_lider: int) -> bool:
    """Chamado pelo heartbeat: a líder ``id_lider`` parou de responder.

    Só apaga se ela ainda for a líder reconhecida (pode ter chegado um
    COORDENADOR novo enquanto o heartbeat esperava o timeout).
    """
    global _lider_atual, _lider_desde
    with _lock:
        if _lider_atual != id_lider:
            return False
        _lider_atual = None
        _lider_desde = None
        return True


# --- envio -----------------------------------------------------------------------------

def _post(id_destino: int, caminho: str, corpo: dict) -> dict | None:
    """POST para outra agência. ``None`` = não respondeu (fora do ar, timeout,
    conexão recusada ou erro HTTP) - para o Bully, tudo isso é "morta"."""
    try:
        resposta = httpx.post(
            config.url_agencia(id_destino) + caminho,
            json=corpo,
            headers=cabecalho_interno(ID_AGENCIA),
            timeout=TIMEOUT_HTTP,
        )
        if resposta.status_code != 200:
            return None
        return resposta.json()
    except (httpx.HTTPError, ValueError):
        return None


def consultar_lider_de(id_agencia: int) -> dict | None:
    """``GET /bully/lider`` de outra agência (heartbeat e painel do cluster)."""
    try:
        resposta = httpx.get(config.url_agencia(id_agencia) + "/bully/lider", timeout=TIMEOUT_HTTP)
        if resposta.status_code != 200:
            return None
        return resposta.json()
    except (httpx.HTTPError, ValueError):
        return None


def _em_paralelo(destinos: list[int], funcao) -> dict[int, object]:
    """Chama ``funcao(destino)`` para cada destino ao mesmo tempo: o tempo de uma
    rodada fica em ~1 timeout, e não em 1 timeout por agência morta."""
    resultados: dict[int, object] = {}

    def chamar(destino: int) -> None:
        resultados[destino] = funcao(destino)

    threads = [threading.Thread(target=chamar, args=(d,), daemon=True) for d in destinos]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return resultados


# --- o algoritmo -------------------------------------------------------------------------

def iniciar_eleicao(motivo: str) -> None:
    """Convoca uma eleição (bloqueia até ela terminar, do ponto de vista desta
    agência). Se já houver uma em andamento aqui, não faz nada."""
    global _em_eleicao
    with _lock:
        if _em_eleicao:
            return
        _em_eleicao = True
        _coordenador_chegou.clear()
    try:
        while True:
            maiores = [a["id"] for a in config.AGENCIAS if a["id"] > ID_AGENCIA]
            ts = relogio.ao_enviar()
            registro.registrar("ELEICAO_INICIADA", ts, {"motivo": motivo, "consultadas": maiores})

            corpo = {"origemId": ID_AGENCIA, "vetor": ts}
            respostas = _em_paralelo(maiores, lambda d: _post(d, "/bully/eleicao", corpo))
            vivas = sorted(d for d, r in respostas.items() if isinstance(r, dict) and r.get("ok"))

            if not vivas:
                _tornar_lider()
                return

            # Alguém maior está vivo e assumiu a eleição: cede e espera o anúncio.
            registro.registrar("ELEICAO_CEDIDA", relogio.evento_local(), {"responderam": vivas})
            if _coordenador_chegou.wait(ESPERA_COORDENADOR):
                return
            motivo = f"agencia(s) {vivas} responderam OK mas nenhum COORDENADOR chegou em {ESPERA_COORDENADOR:.0f} s"
    finally:
        with _lock:
            _em_eleicao = False


def _tornar_lider() -> None:
    anterior = _definir_lider(ID_AGENCIA)
    ts = relogio.ao_enviar()
    outras = [a["id"] for a in config.AGENCIAS if a["id"] != ID_AGENCIA]
    registro.registrar("LIDER_ELEITO", ts, {"lider": ID_AGENCIA, "anterior": anterior, "notificadas": outras})
    corpo = {"liderId": ID_AGENCIA, "vetor": ts}
    # Avisa TODAS as outras, não só as menores: se uma maior estiver viva mas
    # tiver demorado a responder, ela recusa o anúncio e convoca nova eleição
    # (que vence) - a convergência para o maior ID vivo continua garantida.
    _em_paralelo(outras, lambda d: _post(d, "/bully/coordenador", corpo))


def _eleicao_em_segundo_plano(motivo: str) -> None:
    threading.Thread(target=iniciar_eleicao, args=(motivo,), name="eleicao", daemon=True).start()


def receber_eleicao(origem_id: int, vetor: list[int]) -> dict:
    """Uma agência menor convocou eleição. Respondo OK e assumo a eleição."""
    ts = relogio.ao_receber(vetor)
    if origem_id >= ID_AGENCIA:
        # Pelo protocolo, só agências de ID maior recebem ELEIÇÃO. Não deveria
        # acontecer; responde sem "ok" para não fazer a origem ceder à toa.
        registro.registrar("ELEICAO_IGNORADA", ts, {"de": origem_id})
        return {"ok": False, "respondente": ID_AGENCIA}
    registro.registrar("ELEICAO_RECEBIDA", ts, {"de": origem_id})
    # A resposta não pode esperar a minha própria eleição terminar (a origem
    # tem só 1 s de timeout): dispara em outra thread e responde já.
    _eleicao_em_segundo_plano(f"eleicao recebida da agencia {origem_id}")
    return {"ok": True, "respondente": ID_AGENCIA}


def receber_coordenador(lider_id: int, vetor: list[int]) -> dict:
    """A agência ``lider_id`` se declarou líder."""
    ts = relogio.ao_receber(vetor)
    if lider_id < ID_AGENCIA:
        # Eu tenho ID maior e estou viva: pela regra do Bully a líder deveria
        # ser eu (acontece quando eu volto de uma queda). Recuso e "valento".
        registro.registrar("COORDENADOR_RECUSADO", ts, {"liderId": lider_id})
        _eleicao_em_segundo_plano(f"agencia {lider_id} se declarou lider, mas tenho ID maior")
        return {"aceito": False, "idAgencia": ID_AGENCIA}

    anterior = _definir_lider(lider_id)
    _coordenador_chegou.set()
    registro.registrar("NOVO_LIDER", ts, {"lider": lider_id, "anterior": anterior})
    return {"aceito": True, "idAgencia": ID_AGENCIA}
