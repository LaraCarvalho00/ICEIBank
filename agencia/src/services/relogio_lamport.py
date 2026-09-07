"""Relógio lógico de Lamport (Lamport, 1978).

Contador inteiro por processo, com três regras:

1. Antes de qualquer evento local, o processo incrementa seu contador.
2. Ao enviar uma mensagem, incrementa o contador e anexa o valor à mensagem.
3. Ao receber uma mensagem com timestamp ``t``, ajusta o contador para
   ``max(contador_local, t) + 1``.

Garante: se A "aconteceu antes" de B causalmente, então ``ts(A) < ts(B)``.
NÃO garante a volta: ``ts(A) < ts(B)`` não prova que A influenciou B - eles
podem ser concorrentes. Essa limitação motiva o relógio vetorial do Sprint 2.
"""
import threading


class RelogioLamport:
    def __init__(self) -> None:
        self.contador = 0
        # Um servidor web atende requisições em várias threads ao mesmo tempo e
        # o contador é estado compartilhado entre elas. Sem o lock, dois eventos
        # simultâneos poderiam ler e incrementar o contador de forma
        # inconsistente (condição de corrida). O FastAPI executa rotas
        # síncronas (`def`) em um threadpool, então o cuidado vale mesmo com um
        # único worker Uvicorn.
        self._lock = threading.Lock()

    def evento_local(self) -> int:
        """Regra 1: incrementa antes de um evento puramente local."""
        with self._lock:
            self.contador += 1
            return self.contador

    def ao_enviar(self) -> int:
        """Regra 2: incrementa; o valor retornado vai anexado à mensagem."""
        with self._lock:
            self.contador += 1
            return self.contador

    def ao_receber(self, timestamp_recebido: int) -> int:
        """Regra 3: contador = max(contador_local, timestamp_recebido) + 1."""
        with self._lock:
            self.contador = max(self.contador, timestamp_recebido) + 1
            return self.contador
