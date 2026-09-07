// VIEW - criar conta
import { useState } from 'react'
import { agenciaDaConta } from '../api/contas.js'

export default function FormCriarConta({ aoCriar, agenciaAtual }) {
  const [id, setId] = useState('0')
  const [nomeAluno, setNome] = useState('')
  const [saldoInicial, setSaldo] = useState('0')

  const dono = id === '' ? null : agenciaDaConta(id)

  return (
    <section className="cartao">
      <h3>Criar conta</h3>
      <form
        onSubmit={(e) => {
          e.preventDefault()
          aoCriar(Number(id), nomeAluno.trim(), Number(saldoInicial))
        }}
      >
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

      {dono !== null && dono !== agenciaAtual && (
        <p className="dica alerta">
          A conta {id} pertence à Agência {dono} (id % 3). Selecione a Agência {dono} lá
          em cima, ou use outro número.
        </p>
      )}
    </section>
  )
}
