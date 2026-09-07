// Helpers de conversão de texto digitado -> número.

// Aceita vírgula decimal (pt-BR) e ponto de milhar:
//   "100,00"    -> 100
//   "1.234,56"  -> 1234.56
//   "50.5"      -> 50.5
//   ""          -> NaN
export function paraNumero(texto) {
  if (typeof texto === 'number') return texto
  let s = String(texto).trim()
  if (s === '') return NaN
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.')
  return Number(s)
}

// Número de conta: inteiro >= 0. Retorna NaN se não for.
export function paraInteiroConta(texto) {
  const s = String(texto).trim()
  if (!/^\d+$/.test(s)) return NaN
  return Number(s)
}
