// ---------------------------------------------------------------------------
// CONTROLLER
// ---------------------------------------------------------------------------
// Guarda o estado da tela, liga os eventos da View (componentes) às funções do
// Model (src/api) e decide o que exibir. O wrapper executar() concentra o fluxo
// comum: marca "ocupado", limpa mensagens, chama o Model, transforma
// sucesso/erro em mensagem VISÍVEL e desloga quando a sessão expira.
import { useState } from 'react'
import {
  AGENCIAS,
  getAgenciaId,
  setAgenciaId,
  getToken,
  setToken,
  SessaoExpirada,
} from './api/cliente.js'
import { login } from './api/auth.js'
import * as contasApi from './api/contas.js'
import Login from './componentes/Login.jsx'
import Mensagem from './componentes/Mensagem.jsx'
import ConsultaSaldo from './componentes/ConsultaSaldo.jsx'
import FormCriarConta from './componentes/FormCriarConta.jsx'
import FormValor from './componentes/FormValor.jsx'
import FormTransferencia from './componentes/FormTransferencia.jsx'

export default function App() {
  const [autenticado, setAutenticado] = useState(!!getToken())
  const [agencia, setAgencia] = useState(getAgenciaId())
  const [msg, setMsg] = useState(null)
  const [conta, setConta] = useState(null)
  const [ocupado, setOcupado] = useState(false)

  const ok = (texto) => setMsg({ tipo: 'ok', texto })
  const erro = (texto) => setMsg({ tipo: 'erro', texto })

  async function executar(fn, mensagemSucesso) {
    setOcupado(true)
    setMsg(null)
    try {
      const r = await fn()
      if (mensagemSucesso) {
        ok(typeof mensagemSucesso === 'function' ? mensagemSucesso(r) : mensagemSucesso)
      }
      return r
    } catch (e) {
      if (e instanceof SessaoExpirada) {
        setAutenticado(false) // volta para a tela de login
      }
      erro(e.message) // mensagem visível em qualquer caso
      return undefined
    } finally {
      setOcupado(false)
    }
  }

  function trocarAgencia(id) {
    setAgencia(id)
    setAgenciaId(id)
    setConta(null)
    setMsg(null)
  }

  async function aoEntrar(usuario, senha) {
    const r = await executar(() => login(usuario, senha), 'Login efetuado.')
    if (r) setAutenticado(true)
  }

  function sair() {
    setToken(null)
    setAutenticado(false)
    setConta(null)
    ok('Você saiu.')
  }

  async function aoCriar(id, nomeAluno, saldoInicial) {
    const c = await executar(
      () => contasApi.criarConta(id, nomeAluno, saldoInicial),
      (c) => `Conta ${c.id} criada para ${c.nomeAluno}. Saldo: R$ ${Number(c.saldo).toFixed(2)}`,
    )
    if (c) setConta(c)
  }

  async function aoConsultar(id) {
    const c = await executar(
      () => contasApi.consultarSaldo(id),
      (c) => `Saldo da conta ${c.id}: R$ ${Number(c.saldo).toFixed(2)}`,
    )
    if (c) setConta(c)
  }

  async function aoDepositar(id, valor) {
    const c = await executar(
      () => contasApi.depositar(id, valor),
      (c) => `Depósito ok. Novo saldo da conta ${c.id}: R$ ${Number(c.saldo).toFixed(2)}`,
    )
    if (c) setConta(c)
  }

  async function aoSacar(id, valor) {
    const c = await executar(
      () => contasApi.sacar(id, valor),
      (c) => `Saque ok. Novo saldo da conta ${c.id}: R$ ${Number(c.saldo).toFixed(2)}`,
    )
    if (c) setConta(c)
  }

  function aoTransferir(origem, destino, valor) {
    return executar(
      () => contasApi.transferir(origem, destino, valor),
      (r) =>
        `${r.mensagem}` +
        (r.saldoOrigem != null
          ? ` Saldo da origem: R$ ${Number(r.saldoOrigem).toFixed(2)}.`
          : ''),
    )
  }

  return (
    <div className="app">
      <header>
        <h1>ICEIBank</h1>
        <div className="ferramentas">
          <label>
            Agência de entrada:{' '}
            <select
              value={agencia}
              onChange={(e) => trocarAgencia(Number(e.target.value))}
            >
              {AGENCIAS.map((a) => (
                <option key={a.id} value={a.id}>
                  Agência {a.id} ({a.url})
                </option>
              ))}
            </select>
          </label>
          {autenticado && <button onClick={sair}>Sair</button>}
        </div>
      </header>

      <Mensagem msg={msg} />

      {!autenticado ? (
        <Login aoEntrar={aoEntrar} ocupado={ocupado} />
      ) : (
        <main className="grade">
          <FormCriarConta aoCriar={aoCriar} agenciaAtual={agencia} />
          <ConsultaSaldo aoConsultar={aoConsultar} conta={conta} agenciaAtual={agencia} />
          <FormValor titulo="Depósito" rotuloBotao="Depositar" aoEnviar={aoDepositar} />
          <FormValor titulo="Saque" rotuloBotao="Sacar" aoEnviar={aoSacar} />
          <FormTransferencia aoTransferir={aoTransferir} agenciaAtual={agencia} />
        </main>
      )}

      <footer>ICEIBank · Sprint 1 — REST/MVC + Relógio de Lamport + JWT</footer>
    </div>
  )
}
