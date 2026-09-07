# RESPOSTAS - Sprint 1: ICEIBank

**Alunos:** Lara Carvalho · Allan Mateus
**Linguagem escolhida:** Python (FastAPI) - mantida do Sprint 1 ao 4.

---

## Nota de transparência - uso de IA

Este projeto utilizou o **Claude (Anthropic)** como apoio para: estruturação do
repositório, adaptação do código de referência (que o roteiro fornece em
Node.js) para Python/FastAPI, redação desta documentação e revisão de código.
Todo trecho entregue foi lido, compreendido e é passível de explicação e defesa
pelos autores.

---

## Funcionalidade adicional (seção 2.1)

**Funcionalidade escolhida:** _(a definir - ver seção correspondente)_

**O que faz:**

**Por que escolhemos:**

**Evidência:** `evidencias/sprint1/funcionalidade-adicional.png`

---

## Parte B - Relógio de Lamport (seção 6.4)

**1. Por que o relógio de Lamport usa `max(contador_local, timestampRecebido) + 1`
ao receber uma mensagem, em vez de adotar o timestamp recebido diretamente?**

Porque o relógio precisa satisfazer duas propriedades ao mesmo tempo, e adotar o
timestamp recebido "cru" quebra pelo menos uma delas:

- **Monotonicidade (nunca retroceder).** Se o timestamp recebido for *menor* que
  o contador local (a outra agência estava atrasada), adotá-lo faria o relógio
  andar para trás. Eventos futuros ganhariam timestamps menores que eventos
  passados, e poderiam surgir timestamps repetidos. O `max` garante que o
  contador fica **pelo menos igual** ao que já era.
- **Causalidade estrita entre envio e recebimento.** O evento "receber" acontece
  *depois* do evento "enviar" da outra agência. Se adotássemos o timestamp
  recebido diretamente (caso ele fosse maior), "receber" ficaria com o **mesmo**
  valor de "enviar", sugerindo simultaneidade. O `+ 1` força
  `ts(enviar) < ts(receber)` e também `ts(último evento local) < ts(receber)`,
  preservando a relação "aconteceu antes".

Em resumo: `max(...)` impede retrocesso; `+ 1` garante que o recebimento é
estritamente posterior tanto ao último evento local quanto ao envio remoto.

**2. Se a Agência 0 está no evento de contador 10 e recebe uma mensagem com
timestamp 3 (de uma agência mais "atrasada"), qual o novo valor do contador da
Agência 0? O que isso implica sobre agências que processam muitos eventos
rapidamente versus agências mais lentas?**

`max(10, 3) + 1 = **11**`. A mensagem "atrasada" não puxa o relógio da Agência 0
para trás; ela apenas continua avançando (10 → 11). Isso está verificado em
`agencia/verificar_lamport.py` (`cenario_pergunta_6_4_2`).

Implicações:

- O relógio de cada agência avança no ritmo dos **próprios** eventos. Uma agência
  que processa muita coisa terá contador alto; uma agência ociosa terá contador
  baixo.
- Quando a agência lenta manda mensagem para a rápida, quase nada muda (a rápida
  já está à frente, faz só `+1`). Quando a rápida manda para a lenta, a lenta
  **salta** para perto do valor da rápida.
- Logo, o valor de Lamport **não** mede "quantidade de trabalho" nem "tempo", e a
  diferença numérica entre dois timestamps não significa nada além de ordem. Só a
  ordem relativa importa - e, mesmo assim, apenas para eventos causalmente
  ligados.

---

## Parte D - Transferências (seção 8.3)

**1. No trecho `agenciaDestino === idAgencia`, por que a transferência local não
precisa da lógica de `aoEnviar()`/`aoReceber()` do relógio de Lamport, enquanto a
transferência entre agências precisa?**

As regras 2 e 3 de Lamport (`ao_enviar` / `ao_receber`) só existem para ordenar
um evento de **um processo** em relação a um evento de **outro processo** - ou
seja, quando há troca de mensagem entre processos que têm contadores
independentes.

- **Transferência local:** débito e crédito acontecem no **mesmo processo** (a
  mesma agência, o mesmo contador). São dois eventos locais consecutivos -
  `evento_local()` para o débito, `evento_local()` para o crédito. O próprio
  incremento sequencial já garante `ts(débito) < ts(crédito)`. Nenhuma mensagem
  cruza a fronteira de processo, então não há timestamp externo para reconciliar.
- **Transferência entre agências:** o crédito acontece em **outro processo**, com
  outro contador que evoluiu de forma independente. A origem chama `ao_enviar()`
  (regra 2) para carimbar a mensagem com seu contador; o destino chama
  `ao_receber(ts)` (regra 3): `max(contador_local, ts) + 1`. Sem isso, o crédito
  remoto poderia ganhar um timestamp **menor** que o do débito que o causou,
  quebrando a relação causal "o débito aconteceu antes do crédito".

Isto aparece no `demos/02-transferencia-entre-agencias.sh`: a Ag0 debita em
`ts=2` e envia com `ts=3`; a Ag1, que estava em `ts=1`, recebe e registra o
crédito remoto em `ts = max(1, 3) + 1 = 4`.

**2. Reproduza a falha conhecida e observe o saldo da conta de origem depois do
erro. Ele foi revertido? O que isso significa em termos de consistência do
sistema bancário?**

**Não foi revertido.** No teste (`demos/03-falha-conhecida.sh`), a conta 0 foi de
**100 para 75** e ficou em 75, mesmo com a transferência retornando **HTTP 502** e
a conta 1 nunca tendo sido creditada. Os R$ 25 "desapareceram": não estão mais na
origem e nunca chegaram ao destino.

Em termos de consistência, o sistema violou:

- a **atomicidade** da operação (uma transferência deveria ser tudo-ou-nada);
- a **conservação do dinheiro total** - invariante do domínio bancário: numa
  transferência, a soma dos saldos deveria permanecer constante.

O sistema não corrompeu **silenciosamente** - ele gravou o evento
`TRANSFERENCIA_FALHOU` no log -, mas **registrar não é reparar**. Esse é
exatamente o problema que o Sprint 4 resolve.

**3. Pensando à frente para o Sprint 4: cite, em alto nível, duas formas
possíveis de corrigir esse problema.**

1. **Commit em duas fases (2PC).** Um coordenador (a agência de origem ou um
   serviço à parte) primeiro pergunta a todas as partes se conseguem executar
   (fase *prepare*): a origem **reserva** os R$ 25 sem efetivar, o destino
   confirma que a conta existe e pode receber. Só se **todas** responderem "sim"
   o coordenador manda *commit* e cada parte efetiva; se qualquer uma falhar ou
   não responder, manda *abort* e todas desfazem. O débito só se torna definitivo
   quando o crédito já está garantido.
2. **Saga com compensação.** A transferência vira uma sequência de passos locais,
   cada um com uma ação compensatória. Passo 1: debitar a origem (compensação:
   creditar de volta). Passo 2: creditar o destino. Se o passo 2 falhar, a saga
   dispara a compensação do passo 1 (estorna o débito), devolvendo o sistema a um
   estado consistente. Não dá isolamento como o 2PC, mas não trava recursos
   esperando e tolera melhor agências lentas ou instáveis.

*(Variante mais simples: tornar `creditar-remoto` idempotente e a origem
re-tentar em background até receber o ACK do destino, mantendo o débito como
"pendente" e só o consolidando depois - na prática, uma Saga com retry.)*

---

## Parte E - Linha do tempo unificada (seção 10.3)

**1. O relógio de Lamport garante que, se A aconteceu antes de B causalmente,
`timestamp(A) < timestamp(B)`. Ele não garante a volta. O que isso significa na
prática quando você vê dois eventos com timestamps diferentes na linha do tempo,
mas sem saber se um realmente influenciou o outro?**

_(responder)_

**2. O relógio de Lamport, sozinho, seria suficiente para um sistema que precisa
distinguir com certeza "A e B são concorrentes" de "A aconteceu antes de B"? Por
que isso motiva o relógio vetorial do Sprint 2?**

_(responder)_

**Observação do passo 3 da tarefa (par de eventos empatados encontrado):**

_(descrever o que foi observado: timestamps, horaParede, se são causais ou
concorrentes)_

---

## Parte F - Autenticação JWT (seção 11.3)

### Justificativas de design

**Formato das credenciais escolhido e por quê:**

_(responder)_

**A chamada interna agência-a-agência (`creditar-remoto`) carrega token ou é
tratada de forma diferente? Justificativa:**

_(responder)_

### Questões

**1. Qual a diferença entre autenticação e autorização? Sua implementação
verifica só uma das duas, ou as duas? Um usuário autenticado consegue sacar de
uma conta que não é dele?**

_(responder)_

**2. Por que o servidor não precisa consultar um banco de dados para validar a
assinatura de um JWT a cada requisição? O que isso implica sobre escalabilidade
comparado a guardar sessões em memória?**

_(responder)_

**3. O que aconteceria com a segurança do sistema se a chave secreta usada para
assinar o JWT vazasse?**

_(responder)_

---

## Parte G - Frontend (seção 12.3)

### Justificativas de design

**Framework escolhido e forma de guardar o token:**

_(responder)_

### Questões

**1. Como o frontend "lembra" de reenviar o token em cada requisição depois do
login? Descreva o mecanismo implementado.**

_(responder)_

**2. Se o token expirar enquanto alguém está usando o frontend no meio de uma
operação, o que acontece na sua implementação? A interface avisa a pessoa?**

_(responder)_

**3. Esta unidade trata de arquitetura MVC. No seu frontend, onde fica o "M"
(Model), o "V" (View) e o "C" (Controller)?**

_(responder)_
