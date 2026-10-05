"""Mostra quantas mensagens estão paradas em cada fila do ICEIBank no RabbitMQ
(as mesmas contagens da coluna "Ready" do RabbitMQ Manager).

    uv run python ver_filas.py
"""
from src import config
from src.services import mensageria


def main() -> None:
    conexao = mensageria._conectar()
    try:
        canal = conexao.channel()
        for agencia in config.AGENCIAS:
            for fila in (mensageria.nome_fila(agencia["id"]), mensageria.nome_fila_dlq(agencia["id"])):
                info = canal.queue_declare(queue=fila, passive=True).method
                print(f"  {fila:<22} mensagens={info.message_count}  consumidores={info.consumer_count}")
    finally:
        conexao.close()


if __name__ == "__main__":
    main()
