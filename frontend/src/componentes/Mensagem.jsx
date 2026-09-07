// VIEW - banner de mensagem (erro ou sucesso), visível para quem usa a tela.
export default function Mensagem({ msg }) {
  if (!msg) return null
  return (
    <div className={`mensagem ${msg.tipo}`} role="status">
      {msg.texto}
    </div>
  )
}
