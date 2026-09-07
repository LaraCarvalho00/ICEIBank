// ---------------------------------------------------------------------------
// MODEL (infraestrutura de acesso à API)
// ---------------------------------------------------------------------------
// Ponto único por onde TODA requisição à API passa. Responsável por:
//  - escolher a agência "porta de entrada" (as 3 rodam em portas diferentes);
//  - injetar o cabeçalho Authorization: Bearer <token> em toda requisição;
//  - guardar/ler o token e a agência escolhida no localStorage;
//  - transformar respostas != 2xx em erros de domínio (ErroApi / SessaoExpirada).
// Nenhum componente chama fetch direto: todos passam por requisitar().

const CHAVE_TOKEN = 'iceibank.token'
const CHAVE_AGENCIA = 'iceibank.agencia'

export const AGENCIAS = [
  { id: 0, url: 'http://localhost:4000' },
  { id: 1, url: 'http://localhost:4001' },
  { id: 2, url: 'http://localhost:4002' },
]

export function getToken() {
  try {
    return localStorage.getItem(CHAVE_TOKEN)
  } catch {
    return null
  }
}

export function setToken(token) {
  try {
    if (token) localStorage.setItem(CHAVE_TOKEN, token)
    else localStorage.removeItem(CHAVE_TOKEN)
  } catch {
    /* localStorage indisponível (aba privada etc.) - segue sem persistir */
  }
}

export function getAgenciaId() {
  try {
    return Number(localStorage.getItem(CHAVE_AGENCIA)) || 0
  } catch {
    return 0
  }
}

export function setAgenciaId(id) {
  try {
    localStorage.setItem(CHAVE_AGENCIA, String(id))
  } catch {
    /* ignora */
  }
}

export function urlBase() {
  const a = AGENCIAS.find((x) => x.id === getAgenciaId()) || AGENCIAS[0]
  return a.url
}

// A API respondeu com status != 2xx e (normalmente) um campo "detail".
export class ErroApi extends Error {
  constructor(mensagem, status) {
    super(mensagem)
    this.name = 'ErroApi'
    this.status = status
  }
}

// Token ausente, inválido ou expirado (HTTP 401).
export class SessaoExpirada extends ErroApi {
  constructor(mensagem, status) {
    super(mensagem, status)
    this.name = 'SessaoExpirada'
  }
}

export async function requisitar(caminho, { metodo = 'GET', corpo, base } = {}) {
  const headers = { 'Content-Type': 'application/json' }
  const token = getToken()
  if (token) headers.Authorization = `Bearer ${token}`

  let resposta
  try {
    resposta = await fetch((base || urlBase()) + caminho, {
      method: metodo,
      headers,
      body: corpo ? JSON.stringify(corpo) : undefined,
    })
  } catch {
    throw new ErroApi('Não foi possível falar com a agência. Ela está no ar?', 0)
  }

  let dados = null
  try {
    dados = await resposta.json()
  } catch {
    /* resposta sem corpo JSON */
  }

  if (resposta.status === 401) {
    setToken(null) // limpa o token morto
    throw new SessaoExpirada(
      (dados && dados.detail) || 'Sua sessão expirou. Entre novamente.',
      401,
    )
  }

  if (!resposta.ok) {
    throw new ErroApi(
      formatarDetalhe(dados && dados.detail, resposta.status),
      resposta.status,
    )
  }

  return dados
}

// Mensagens de validação do FastAPI/Pydantic mais comuns, em português.
const TRAD_VALIDACAO = {
  'Input should be a valid number': 'informe um número válido',
  'Input should be a valid integer': 'informe um número inteiro',
  'Input should be greater than 0': 'deve ser maior que zero',
  'Input should be greater than or equal to 0': 'não pode ser negativo',
  'Field required': 'campo obrigatório',
  'String should have at least 1 character': 'campo obrigatório',
}

// Transforma o "detail" da resposta em uma frase legível. O 422 do Pydantic vem
// como um array de objetos {loc, msg, ...}; sem isto o usuário veria o JSON cru.
function formatarDetalhe(detalhe, status) {
  if (typeof detalhe === 'string') return detalhe
  if (Array.isArray(detalhe)) {
    return detalhe
      .map((e) => {
        const campo = Array.isArray(e.loc) ? e.loc[e.loc.length - 1] : e.loc
        const bruta = String(e.msg || '').replace(/^Value error,\s*/i, '')
        const msg = TRAD_VALIDACAO[bruta] || bruta
        return campo && campo !== 'body' ? `${campo}: ${msg}` : msg
      })
      .join(' · ')
  }
  return `Erro ${status}`
}
