// VIEW - tela de login
import { useState } from 'react'

export default function Login({ aoEntrar, ocupado }) {
  const [usuario, setUsuario] = useState('lara')
  const [senha, setSenha] = useState('')

  function enviar(e) {
    e.preventDefault()
    aoEntrar(usuario.trim(), senha)
  }

  return (
    <form className="cartao login" onSubmit={enviar}>
      <h2>Entrar</h2>
      <label>
        Usuário
        <input value={usuario} onChange={(e) => setUsuario(e.target.value)} autoFocus />
      </label>
      <label>
        Senha
        <input
          type="password"
          value={senha}
          onChange={(e) => setSenha(e.target.value)}
        />
      </label>
      <button disabled={ocupado}>{ocupado ? 'Entrando…' : 'Entrar'}</button>
      <p className="dica">Ambiente de avaliação · usuários <code>lara</code> ou <code>allan</code>, senha <code>iceibank</code></p>
    </form>
  )
}
