"""Relógio vetorial (Fidge, 1988; Mattern, 1989).

Substitui o relógio de Lamport do Sprint 1. Em vez de um único contador, cada
agência mantém um VETOR com um contador por agência (aqui, 3 posições). Regras:

1. Antes de um evento local, a agência incrementa a SUA posição no vetor.
2. Ao enviar uma mensagem, incrementa a sua posição e anexa o vetor inteiro.
3. Ao receber uma mensagem com ``vetor_recebido``, faz ``vetor[i] =
   max(vetor[i], vetor_recebido[i])`` para cada ``i`` e depois incrementa a
   sua própria posição.

Diferente de Lamport, a comparação de dois vetores responde com certeza se um
evento aconteceu antes do outro ou se os dois são concorrentes (ver
``comparar``).
"""
import threading


class RelogioVetorial:
    def __init__(self, id_agencia: int, numero_agencias: int) -> None:
        self.id_agencia = id_agencia
        self.vetor = [0] * numero_agencias
        # Mesmo cuidado do Sprint 1: rotas síncronas do FastAPI rodam em um
        # threadpool e, agora, o consumidor do RabbitMQ roda em outra thread.
        # Todas mexem no mesmo vetor.
        self._lock = threading.Lock()

    def evento_local(self) -> list[int]:
        """Regra 1: incrementa a própria posição antes de um evento local."""
        with self._lock:
            self.vetor[self.id_agencia] += 1
            return list(self.vetor)

    def ao_enviar(self) -> list[int]:
        """Regra 2: incrementa; a cópia retornada vai anexada à mensagem."""
        with self._lock:
            self.vetor[self.id_agencia] += 1
            return list(self.vetor)

    def ao_receber(self, vetor_recebido: list[int]) -> list[int]:
        """Regra 3: máximo posição a posição e depois incrementa a própria."""
        if len(vetor_recebido) != len(self.vetor):
            raise ValueError(
                f"vetor recebido tem {len(vetor_recebido)} posicoes, "
                f"esperado {len(self.vetor)}"
            )
        with self._lock:
            for i in range(len(self.vetor)):
                self.vetor[i] = max(self.vetor[i], vetor_recebido[i])
            self.vetor[self.id_agencia] += 1
            return list(self.vetor)


def comparar(v1: list[int], v2: list[int]) -> str:
    """Relação entre os eventos carimbados com ``v1`` e ``v2``.

    - ``"ANTES"``: v1 <= v2 posição a posição (e diferentes) -> v1 -> v2;
    - ``"DEPOIS"``: o contrário;
    - ``"IGUAIS"``: mesmo vetor (mesmo evento);
    - ``"CONCORRENTES"``: nenhum dos dois é <= o outro - nenhum influenciou o
      outro.
    """
    v1_menor_ou_igual = all(a <= b for a, b in zip(v1, v2))
    v2_menor_ou_igual = all(b <= a for a, b in zip(v1, v2))
    if v1_menor_ou_igual and v2_menor_ou_igual:
        return "IGUAIS"
    if v1_menor_ou_igual:
        return "ANTES"
    if v2_menor_ou_igual:
        return "DEPOIS"
    return "CONCORRENTES"
