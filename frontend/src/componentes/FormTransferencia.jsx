// VIEW - formulário de transferência (local e entre agências usam o mesmo form)
import { useState } from 'react'
import { agenciaDaConta } from '../api/contas.js'
import { paraInteiroConta, paraNumero } from '../util/numeros.js'

export default function FormTransferencia({ aoTransferir, agenciaAtual }) {
  const [origem, setOrigem] = useState('0')
  const [destino, setDestino] = useState('1')
  const [valor, setValor] = useState('')
  const [erro, setErro] = useState('')

  const agOrigem = /^\d+$/.test(origem.trim()) ? agenciaDaConta(origem) : null
  const agDestino = /^\d+$/.test(destino.trim()) ? agenciaDaConta(destino) : null
  const mesma = agOrigem !== null && agOrigem === agDestino

  function enviar(e) {
    e.preventDefault()
    const nOrigem = paraInteiroConta(origem)
    const nDestino = paraInteiroConta(destino)
    const nValor = paraNumero(valor)
    if (Number.isNaN(nOrigem) || Number.isNaN(nDestino))
      return setErro('Contas de origem e destino devem ser inteiros ≥ 0.')
    if (nOrigem === nDestino)
      return setErro('Origem e destino não podem ser a mesma conta.')
    if (Number.isNaN(nValor) || nValor <= 0)
      return setErro('Valor deve ser maior que zero (use vírgula: 30,00).')
    setErro('')
    aoTransferir(nOrigem, nDestino, nValor)
  }

  return (
    <section className="cartao">
      <h3>Transferência</h3>
      <form onSubmit={enviar}>
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

      {erro && <p className="dica alerta">{erro}</p>}

      {agOrigem !== null && agDestino !== null && !erro && (
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
