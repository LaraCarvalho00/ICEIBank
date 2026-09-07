// VIEW - formulário de valor, reusado em Depósito e Saque
import { useState } from 'react'
import { paraInteiroConta, paraNumero } from '../util/numeros.js'

export default function FormValor({ titulo, rotuloBotao, aoEnviar }) {
  const [id, setId] = useState('0')
  const [valor, setValor] = useState('')
  const [erro, setErro] = useState('')

  function enviar(e) {
    e.preventDefault()
    const nConta = paraInteiroConta(id)
    const nValor = paraNumero(valor)
    if (Number.isNaN(nConta)) return setErro('Número da conta deve ser um inteiro ≥ 0.')
    if (Number.isNaN(nValor) || nValor <= 0)
      return setErro('Valor deve ser maior que zero (use vírgula: 50,00).')
    setErro('')
    aoEnviar(nConta, nValor)
  }

  return (
    <section className="cartao">
      <h3>{titulo}</h3>
      <form onSubmit={enviar}>
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

      {erro && <p className="dica alerta">{erro}</p>}
    </section>
  )
}
