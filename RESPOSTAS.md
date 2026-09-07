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

Significa que a ordem numérica dos timestamps **não é prova de causalidade**.
Vendo `ts(A) < ts(B)`, há duas situações que o relógio de Lamport **não
distingue**:

- A de fato aconteceu antes de B e pode tê-lo influenciado (relação causal); ou
- A e B são **concorrentes** (nenhum influenciou o outro), e o `<` é só efeito de
  como os contadores avançaram - se as mensagens tivessem trafegado noutra ordem,
  esse `<` poderia até se inverter.

Ou seja, `ts(A) < ts(B)` autoriza dizer "B não aconteceu-antes de A", mas **não**
autoriza dizer "A causou B". Para eventos sem ligação causal, quem ficou com o
número menor é arbitrário.

**2. O relógio de Lamport, sozinho, seria suficiente para um sistema que precisa
distinguir com certeza "A e B são concorrentes" de "A aconteceu antes de B"? Por
que isso motiva o relógio vetorial do Sprint 2?**

Não seria suficiente. Com **um único inteiro por processo**, dado `ts(A) < ts(B)`
não há como saber se existe um caminho causal de A até B ou se são concorrentes;
e um empate `ts(A) == ts(B)` entre processos diferentes indica concorrência, mas
a **ausência** de empate não indica causalidade. O relógio de Lamport comprime
todo o histórico causal num número e **perde informação**.

O **relógio vetorial** guarda um contador por processo (um vetor). Comparando os
vetores de A e B decide-se com exatidão: se `V(A) < V(B)` em todas as
componentes, então A → B (causal); se nem `V(A) ≤ V(B)` nem `V(B) ≤ V(A)`, então
A e B são concorrentes. É essa capacidade de **detectar concorrência com
certeza** que o Sprint 2 acrescenta.

**Observação do passo 3 da tarefa (execução de `demos/04-linha-do-tempo.sh`):**

A linha do tempo mesclada trouxe vários timestamps repetidos:

| Lamport | Eventos (agências diferentes) | Relação |
|---|---|---|
| 1 | `CRIAR_CONTA` em agencia-0, agencia-1 e agencia-2 | concorrentes |
| 2 | `DEPOSITO` em agencia-0, agencia-1 e agencia-2 | concorrentes |
| 3 | `TRANSFERENCIA_DEBITO` (agencia-0) e `SAQUE` (agencia-2) | concorrentes |

Nenhum desses pares é causalmente relacionado: criar a conta 1 na agencia-1 não
depende de criar a conta 0 na agencia-0, o saque na agencia-2 não depende do
débito na agencia-0, etc. São operações independentes que por acaso caíram no
mesmo ponto do contador de cada agência.

**A ordem por `horaParede` NÃO coincide com a ordem da lista:**

- No `[Lamport 2]`, os três depósitos têm `horaParede` `...053805` (ag0),
  `...053810` (ag2) e `...053870` (ag1) - fisicamente a ordem foi ag0, ag2, ag1,
  mas a lista (ordenada por Lamport e depois por nome) mostra ag0, ag1, ag2.
- O evento `[Lamport 5]` (`TRANSFERENCIA_CREDITO_REMOTO` na agencia-1) tem
  `horaParede` `...080073`, **anterior** ao `[Lamport 3]` `SAQUE` da agencia-2
  (`...087043`). Pelo relógio físico o evento de Lamport 5 aconteceu antes do de
  Lamport 3 - e isso **não é um erro**: os dois são concorrentes, então nenhuma
  das duas ordens é "a certa". O relógio de Lamport só se compromete a respeitar
  a ordem de eventos **causalmente ligados** (ex.: o `TRANSFERENCIA_DEBITO` de
  Lamport 3 na agencia-0 vem antes do `TRANSFERENCIA_CREDITO_REMOTO` de Lamport 5
  na agencia-1, que é o seu efeito).

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
