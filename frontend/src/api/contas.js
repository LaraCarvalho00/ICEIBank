// MODEL - operações de conta (o "o que o sistema faz")
import { requisitar } from './cliente.js'

export const consultarSaldo = (id) => requisitar(`/contas/${id}`)

export const depositar = (id, valor) =>
  requisitar(`/contas/${id}/depositar`, { metodo: 'POST', corpo: { valor } })

export const sacar = (id, valor) =>
  requisitar(`/contas/${id}/sacar`, { metodo: 'POST', corpo: { valor } })

// O frontend NÃO precisa saber se é local ou entre agências: manda sempre para
// /transferencias da agência da conta de origem; o backend resolve.
export const transferir = (idOrigem, idDestino, valor) =>
  requisitar('/transferencias', {
    metodo: 'POST',
    corpo: { idOrigem, idDestino, valor },
  })

export const criarConta = (id, nomeAluno, saldoInicial) =>
  requisitar('/contas', {
    metodo: 'POST',
    corpo: { id, nomeAluno, saldoInicial },
  })

// Mesma regra do backend (id_conta % 3). Só para dar dicas na tela.
export const agenciaDaConta = (id) => (((Number(id) % 3) + 3) % 3)
