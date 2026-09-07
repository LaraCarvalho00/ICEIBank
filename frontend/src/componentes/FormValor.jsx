// VIEW - formulário de valor, reusado em Depósito e Saque
import { useState } from 'react'

export default function FormValor({ titulo, rotuloBotao, aoEnviar }) {
  const [id, setId] = useState('0')
  const [valor, setValor] = useState('')

  return (
    <section className="cartao">
      <h3>{titulo}</h3>
      <form
        onSubmit={(e) => {
          e.preventDefault()
          aoEnviar(Number(id), Number(valor))
        }}
      >
        <label>
          Conta
          <input value={id} onChange={(e) => setId(e.target.value)} inputMode="numeric" />
        </label>
        <label>
          Valor (R$)
          <input
            value={valor}
            onChange={(e) => setValor(e.target.value)}
            inputMode="decimal"
            placeholder="0,00"
          />
        </label>
        <button>{rotuloBotao}</button>
      </form>
    </section>
  )
}
