// VIEW - consulta de saldo
import { useState } from 'react'
import { agenciaDaConta } from '../api/contas.js'

export default function ConsultaSaldo({ aoConsultar, conta, agenciaAtual }) {
  const [id, setId] = useState('0')
  const dono = id === '' ? null : agenciaDaConta(id)

  return (
    <section className="cartao">
      <h3>Consultar saldo</h3>
      <form
        onSubmit={(e) => {
          e.preventDefault()
          aoConsultar(Number(id))
        }}
      >
        <label>
          Número da conta
          <input
            value={id}
            onChange={(e) => setId(e.target.value)}
            inputMode="numeric"
          />
        </label>
        <button>Consultar</button>
      </form>

      {dono !== null && dono !== agenciaAtual && (
        <p className="dica alerta">
          A conta {id} pertence à Agência {dono}. Selecione a Agência {dono} lá em cima
          para operá-la.
        </p>
      )}

      {conta && (
        <p className="saldo">
          Conta {conta.id} ({conta.nomeAluno}):{' '}
          <strong>R$ {Number(conta.saldo).toFixed(2)}</strong>
        </p>
      )}
    </section>
  )
}
