// VIEW - criar conta
import { useState } from 'react'
import { agenciaDaConta } from '../api/contas.js'
import { paraInteiroConta, paraNumero } from '../util/numeros.js'

export default function FormCriarConta({ aoCriar, agenciaAtual }) {
  const [id, setId] = useState('0')
  const [nomeAluno, setNome] = useState('')
  const [saldoInicial, setSaldo] = useState('0')
  const [erro, setErro] = useState('')

  const dono = /^\d+$/.test(id.trim()) ? agenciaDaConta(id) : null

  function enviar(e) {
    e.preventDefault()
    const nConta = paraInteiroConta(id)
    const nSaldo = paraNumero(saldoInicial)
    if (Number.isNaN(nConta)) return setErro('Número da conta deve ser um inteiro ≥ 0.')
    if (!nomeAluno.trim()) return setErro('Informe o nome do aluno.')
    if (Number.isNaN(nSaldo) || nSaldo < 0)
      return setErro('Saldo inicial deve ser um número ≥ 0 (use vírgula: 100,00).')
    setErro('')
    aoCriar(nConta, nomeAluno.trim(), nSaldo)
  }

  return (
    <section className="cartao">
      <h3>Criar conta</h3>
      <form onSubmit={enviar}>
        <label>
          Número da conta
          <input value={id} onChange={(e) => setId(e.target.value)} inputMode="numeric" />
        </label>
        <label>
          Nome do aluno
          <input value={nomeAluno} onChange={(e) => setNome(e.target.value)} />
        </label>
        <label>
          Saldo inicial (R$)
          <input
            value={saldoInicial}
            onChange={(e) => setSaldo(e.target.value)}
            inputMode="decimal"
          />
        </label>
        <button>Criar</button>
      </form>

      {erro && <p className="dica alerta">{erro}</p>}

      {dono !== null && dono !== agenciaAtual && (
        <p className="dica alerta">
          A conta {id} pertence à Agência {dono} (id % 3). Selecione a Agência {dono} lá
          em cima, ou use outro número.
        </p>
      )}
    </section>
  )
}
