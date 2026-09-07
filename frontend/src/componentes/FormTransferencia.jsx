// VIEW - formulário de transferência (local e entre agências usam o mesmo form)
import { useState } from 'react'
import { agenciaDaConta } from '../api/contas.js'

export default function FormTransferencia({ aoTransferir, agenciaAtual }) {
  const [origem, setOrigem] = useState('0')
  const [destino, setDestino] = useState('1')
  const [valor, setValor] = useState('')

  const agOrigem = origem === '' ? null : agenciaDaConta(origem)
  const agDestino = destino === '' ? null : agenciaDaConta(destino)
  const mesma = agOrigem !== null && agOrigem === agDestino

  return (
    <section className="cartao">
      <h3>Transferência</h3>
      <form
        onSubmit={(e) => {
          e.preventDefault()
          aoTransferir(Number(origem), Number(destino), Number(valor))
        }}
      >
        <label>
          Conta de origem
          <input value={origem} onChange={(e) => setOrigem(e.target.value)} inputMode="numeric" />
        </label>
        <label>
          Conta de destino
          <input value={destino} onChange={(e) => setDestino(e.target.value)} inputMode="numeric" />
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
        <button>Transferir</button>
      </form>

      {agOrigem !== null && agDestino !== null && (
        <p className="dica">
          {mesma
            ? `Origem e destino na mesma agência (${agOrigem}) → transferência local.`
            : `Agência ${agOrigem} → Agência ${agDestino} → transferência entre agências.`}{' '}
          A conta de origem precisa estar na agência selecionada ({agenciaAtual}).
        </p>
      )}
    </section>
  )
}
