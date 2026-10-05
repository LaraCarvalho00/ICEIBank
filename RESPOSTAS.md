# RESPOSTAS - ICEIBank

- [Sprint 2 - Mensageria (Pub/Sub) + Relógio vetorial](#sprint-2---mensageria-pubsub--relógio-vetorial)
- [Sprint 1 - REST/MVC + Relógio de Lamport](#sprint-1---restmvc--relógio-de-lamport)

---

# Sprint 2 - Mensageria (Pub/Sub) + Relógio vetorial

**Aluna:** Lara Carvalho
**Linguagem:** Python (FastAPI), mesma do Sprint 1. Cliente RabbitMQ: `pika`.
**Broker:** RabbitMQ 4.3 gerenciado no CloudAMQP (plano Little Lemur, região
AWS SA-East-1 / São Paulo).

## Nota de transparência - uso de IA (Sprint 2)

Usei o **Claude (Anthropic)** como apoio para adaptar a arquitetura de
mensageria do roteiro (Node/amqplib) para Python/pika, revisar o código e
estruturar esta documentação. Testei tudo contra a minha instância real do
RabbitMQ, e cada trecho entregue é passível de explicação e defesa por mim.

## O que mudou em relação ao Sprint 1

| Peça | Sprint 1 | Sprint 2 |
|---|---|---|
| Crédito entre agências | `POST /contas/{id}/creditar-remoto` (REST síncrono, token `interno`) | mensagem `agencia.<id>.creditar` na exchange `iceibank.eventos` |
| Relógio lógico | Lamport (`int`) | vetorial (`list[int]`, 3 posições) |
| Resposta 200 de `/transferencias` entre agências | "crédito já aplicado no destino" | "mensagem aceita pelo broker" (crédito assíncrono) |
| Destino fora do ar | HTTP 502, débito "pendurado" | 200; mensagem retida na fila durável até a agência voltar |

Arquivos principais: `agencia/src/services/relogio_vetorial.py`,
`agencia/src/services/mensageria.py`,
`agencia/src/controllers/transferencias_controller.py` (publicação e
`processar_credito_remoto`), `agencia/src/main.py` (consumidor iniciado no
`lifespan`, em thread própria) e `agencia/mesclar_logs.py`.

**Topologia no RabbitMQ:** exchange `iceibank.eventos` (`topic`, durável);
filas duráveis `fila-agencia-0/1/2`, cada uma ligada por
`agencia.<id>.creditar`; mensagens publicadas com `delivery_mode=2`
(persistentes). Decisões além do exemplo do roteiro:

- **Toda agência declara as 3 filas** ao conectar, não só a própria. Sem isso,
  uma transferência para uma agência que *nunca* subiu seria descartada pela
  exchange (nenhuma fila ligada àquela routing key).
- **Publisher confirms + `mandatory=True`:** `publicar()` só retorna depois que o
  broker confirma que gravou a mensagem numa fila. Se falhar, o débito é
  desfeito (`TRANSFERENCIA_DESFEITA`) e a API responde 503. Aqui *dá* para
  desfazer, porque sabemos com certeza que nenhum crédito vai acontecer.
- **Ack só depois de processar** e `prefetch_count=1`: se a agência cair no meio
  do processamento, o RabbitMQ entrega a mensagem de novo.
- **`pika` não é thread-safe:** o publicador usa uma conexão protegida por lock
  (rotas síncronas do FastAPI rodam num threadpool), e o consumidor tem conexão
  própria numa thread daemon que se reconecta sozinha.
- O envio virou um evento explícito no log, `TRANSFERENCIA_PUBLICADA` (vetor de
  `ao_enviar()`), separado do `TRANSFERENCIA_DEBITO` (vetor de
  `evento_local()`).

---

## Funcionalidade adicional (seção 2.1) - Dead-letter queue com reprocessamento

**O que faz:** um crédito remoto que não pode ser aplicado (conta de destino
inexistente, mensagem malformada) não é mais confirmado e esquecido. O
consumidor o rejeita (`basic_nack(requeue=False)`) e o RabbitMQ o move para a
dead-letter queue da agência:

- exchange `iceibank.dlx` (`direct`, durável) e filas `fila-agencia-<id>.dlq`;
- cada `fila-agencia-<id>` é declarada com o argumento
  `x-dead-letter-exchange = iceibank.dlx`, e a routing key original é mantida;
- o broker anexa o cabeçalho `x-death` (motivo `rejected`, fila de origem,
  quantas vezes, quando).

Dois endpoints novos, protegidos por JWT:

- `GET /mensagens-mortas?limite=N` lista a DLQ da agência **sem consumir**
  (`basic_get` sem ack; ao fechar o canal as mensagens voltam para a fila),
  mostrando o conteúdo e o resumo do `x-death`;
- `POST /mensagens-mortas/reprocessar` republica cada mensagem da DLQ na fila
  principal (com confirmação do broker) e só então a remove da DLQ. O
  consumidor tenta aplicá-la de novo. Registra `DLQ_REPROCESSADA` no log.

Código: `agencia/src/services/mensageria.py` (topologia, `listar_mortas`,
`reprocessar_mortas`), `agencia/src/controllers/mensagens_mortas_controller.py`
e as rotas em `agencia/src/rotas.py`.

**Por que escolhi:** ela ataca diretamente o problema que a Parte C expõe. No
teste de resiliência, o crédito chegava à Agência 1 depois do reinício, não
encontrava a conta e simplesmente sumia (era confirmado com ack e virava só uma
linha `CREDITO_REMOTO_FALHOU` no log). Com a DLQ, o dinheiro deixa de "evaporar":
fica visível e recuperável. Observado no teste: depois de recriar a conta 1,
`POST /mensagens-mortas/reprocessar` respondeu `"reprocessadas": 1`, a conta
passou a ter saldo 20 e a DLQ esvaziou. A DLQ não substitui uma compensação
(Saga, Sprint 4): ela só garante que a falha não seja silenciosa.

**Evidência:** `evidencias/sprint2/funcionalidade-adicional.png`.

---

## Parte B - Relógio vetorial (seção 6.4)

**1. Com 3 agências o vetor tem 3 posições. Se o sistema crescesse para 10
agências, o que aconteceria com o tamanho de cada vetor anexado a cada
mensagem? Isso é um problema?**

O vetor cresce **linearmente com o número de processos**: com 10 agências, cada
mensagem carrega 10 inteiros em vez de 3, e cada evento no log também guarda 10.
Para 10 agências isso **não é um problema**: são dezenas de bytes num JSON que
já tem `idMensagem`, valores etc. O custo de comparar dois vetores também é
O(N), desprezível nessa escala.

Vira problema quando N é grande ou muda o tempo todo: com milhares de processos
(ex.: cada cliente ou cada réplica sendo um "processo"), o vetor passa a
dominar o tamanho da mensagem e do log. Além disso, o vetor de tamanho fixo
supõe que o conjunto de agências é conhecido de antemão. No código,
`NUMERO_AGENCIAS = 3` está fixo, e `ao_receber` rejeita vetores de outro
tamanho. Adicionar uma agência exigiria migrar todos os vetores. Alternativas
na literatura: vetores esparsos/dicionário `{id: contador}` (só os processos
com quem houve interação), *version vectors* por réplica de dado em vez de por
processo, *dotted version vectors* e *interval tree clocks* (para membros
dinâmicos).

**2. Dado V1 = [3, 1, 0] e V2 = [3, 2, 0]: qual aconteceu primeiro, ou são
concorrentes?**

**V1 aconteceu antes de V2** (V1 → V2). Posição a posição:

- posição 0: 3 ≤ 3
- posição 1: 1 ≤ 2 (estritamente menor)
- posição 2: 0 ≤ 0

Todas as posições de V1 são ≤ às de V2 e os vetores são diferentes, então V1 <
V2. Interpretação: quem gerou V2 já "conhecia" tudo o que V1 conhecia, mais um
evento a mais da agência 1. (Conferido em `verificar_vetorial.py`:
`comparar([3,1,0], [3,2,0]) == "ANTES"`.)

**3. Dado V1 = [3, 1, 0] e V2 = [1, 3, 0]: qual aconteceu primeiro, ou são
concorrentes?**

**São concorrentes.** Posição a posição:

- posição 0: 3 > 1, então V1 **não** é ≤ V2
- posição 1: 1 < 3, então V2 **não** é ≤ V1
- posição 2: 0 = 0

Nenhum vetor domina o outro: V1 viu mais eventos da agência 0 do que V2 conhecia,
e V2 viu mais eventos da agência 1 do que V1 conhecia. Nenhum dos dois pode ter
influenciado o outro. (Também em `verificar_vetorial.py`:
`comparar([3,1,0], [1,3,0]) == "CONCORRENTES"`.)

---

## Parte C - Publish/Subscribe entre agências (seção 7.5)

**1. No passo 4 da tarefa, o que aconteceu exatamente quando a Agência 1 voltou?
Se a mensagem "sumiu", isso foi porque a mensageria falhou, ou por outro
motivo?**

Sequência observada (`evidencias/sprint2/resiliencia-fila.png`):

1. Com a Agência 1 no ar, criei a conta 1 e recebi um primeiro crédito de 30
   (`TRANSFERENCIA_CREDITO_REMOTO`, vetor `[3, 2, 0]`).
2. Derrubei a Agência 1. Transferi 20 da conta 0 para a conta 1: a Agência 0
   respondeu **HTTP 200** ("Transferencia publicada... entrega assincrona"),
   debitou a conta 0 (saldo 70 → 50) e publicou com vetor `[5, 0, 0]`. No
   RabbitMQ Manager, `fila-agencia-1` ficou com **1 mensagem** retida.
3. Subi a Agência 1 de novo. Assim que o consumidor conectou
   (`[mensageria] consumindo fila-agencia-1`), a mensagem foi entregue
   **na hora**, e o log registrou:
   `[Vetor [5, 1, 0]] CREDITO_REMOTO_FALHOU {... 'idConta': 1, 'valor': 20.0, 'motivo': 'conta nao encontrada'}`.

Portanto **a mensageria não falhou**: a mensagem sobreviveu à queda da agência e
foi entregue exatamente uma vez quando ela voltou. O crédito não foi aplicado
por **outro motivo**: as contas vivem só em memória (`estado.contas`), e o
reinício apagou a conta 1. A mensagem chegou, mas não havia onde aplicar o
valor. O vetor `[5, 1, 0]` mostra a regra 3 funcionando: máximo com `[5, 0, 0]`
recebido e a própria posição incrementada a partir de 0, porque o relógio
também foi zerado no reinício.

Sem a funcionalidade adicional, o comportamento do roteiro é exatamente esse: a
mensagem é confirmada (ack) e o valor desaparece. Com a DLQ, ela foi para
`fila-agencia-1.dlq` e, depois de recriar a conta, o reprocessamento creditou os
20.

**2. Compare com o Sprint 1 (REST direto): o que melhorou e o que continua sendo
um problema em aberto?**

**Melhorou:**

- **Desacoplamento temporal:** a origem não precisa que o destino esteja no ar.
  No Sprint 1 a mesma situação dava HTTP 502 imediatamente
  (`TRANSFERENCIA_FALHOU`), com o débito já aplicado. Agora a mensagem fica
  retida e é entregue quando o destino volta.
- **A mensagem não se perde no caminho:** fila e exchange duráveis, mensagem
  persistente, publisher confirms e ack só depois de processar.
- **Desacoplamento de endereço:** a origem não conhece mais a URL da outra
  agência, só a routing key.

**Continua em aberto** ("a mensagem não se perde" ≠ "o sistema está correto"):

- **O estado não é durável.** A fila guardou a mensagem, mas a agência perdeu a
  conta. Durabilidade só no broker não basta: o destinatário também precisa
  persistir o estado (banco/disco).
- **Não há atomicidade entre débito e crédito.** O débito na Agência 0 é
  definitivo e ninguém o compensa quando o crédito falha. Entre a publicação e o
  consumo, o dinheiro "não está em lugar nenhum". O sistema fica
  inconsistente, agora de forma silenciosa. A DLQ deixa a falha visível, mas o
  estorno automático precisa de uma Saga (Sprint 4).
- **A resposta 200 perdeu força.** Ela diz "publicado", não "creditado". O
  cliente não tem confirmação de que a transferência terminou (seria a opção
  "confirmação de entrega" da seção 2.1).
- **Entrega *at-least-once*.** Se a agência cair depois de aplicar o crédito e
  antes do ack, a mensagem volta e seria creditada duas vezes. Falta
  idempotência (ex.: guardar os `idMensagem` já aplicados, de forma persistente).
- **O próprio relógio vetorial reinicia.** Observado no teste: depois do
  reinício, a Agência 1 voltou com o vetor zerado. O crédito `[3, 2, 0]` (antes
  da queda) e a falha `[5, 1, 0]` (depois) ficam **concorrentes** na comparação,
  porque 2 > 1 na posição 1, embora tenham acontecido em sequência no mesmo
  processo. Para o relógio continuar válido entre reinícios, o vetor também
  precisaria ser persistido (ou a agência voltar como um "novo processo").

**3. O consumidor processa créditos sem verificar JWT. Isso é um problema de
segurança?**

No meu ambiente de desenvolvimento, **sim, é um ponto fraco**, mas o JWT não
seria a ferramenta certa para resolvê-lo. A fronteira de confiança mudou: no
Sprint 1, quem quisesse creditar precisava passar pela API HTTP (por isso o
token `interno`). Agora, quem consegue **publicar na exchange** consegue
creditar qualquer conta de qualquer agência, sem passar pelo FastAPI.

Hoje, quem consegue publicar é **qualquer pessoa que tenha a AMQP URL** da minha
instância CloudAMQP. Ela contém usuário e senha, e as 3 agências usam o mesmo
usuário, com permissão total no vhost (configurar, escrever e ler em tudo).
Essa URL fica em `agencia/.env.local`, que não vai para o Git, mas qualquer
vazamento dela (print, terminal compartilhado, chat) permitiria forjar uma
mensagem `{"idConta": 1, "valor": 1000000, ...}`. O consumidor valida o
**formato** (Pydantic, `MensagemCredito`), mas não a **origem**: o campo
`origemAgencia` é só um número que o publicador escolhe.

Mitigações, da mais simples à mais forte:

1. Tratar a URL como segredo e rotacioná-la se vazar (o painel do CloudAMQP
   permite).
2. **Um usuário do RabbitMQ por agência**, com permissões mínimas: a agência N
   só lê `fila-agencia-N` e só escreve na exchange `iceibank.eventos`.
3. Usar a propriedade `user_id` da mensagem: o RabbitMQ **valida** que ela é
   igual ao usuário da conexão. O consumidor passaria a saber, com garantia do
   broker, qual agência publicou, e poderia conferir com `origemAgencia`.
4. **Assinar o conteúdo** (HMAC ou um JWT dentro da mensagem, com segredo por
   agência), para que nem quem tem acesso ao broker consiga forjar créditos.

TLS já existe (`amqps://`), então ninguém lê nem altera mensagens no caminho
até o CloudAMQP.

---

## Parte D - Linha do tempo causal (seção 8.3)

**1. O que exatamente, no relógio vetorial, torna possível a comparação
confiável que o Lamport não permitia?**

O vetor guarda **um contador por processo**. A posição `i` do vetor de um evento
diz *quantos eventos da agência `i` aquele evento "conhece"* (direta ou
indiretamente, via mensagens). Com isso vale a **condição forte de relógio**:

> a → b  **se e somente se**  V(a) < V(b)  (≤ em todas as posições e diferente)

No Lamport só vale a ida (a → b ⇒ L(a) < L(b)). Como tudo fica achatado num
único número, L(a) < L(b) pode ser causalidade ou coincidência, e não há como
saber. No vetor, se nenhum domina o outro, isso **prova** que nenhum dos dois
eventos "ouviu falar" do outro: são concorrentes. A informação perdida pelo
Lamport (de *qual* processo veio cada parte da história) é exatamente o que o
vetor preserva. O preço é o tamanho: N inteiros em vez de 1.

**2. Encontre, no seu teste, um par classificado como concorrente. Faz sentido?**

Da saída do `mesclar_logs.py` (`evidencias/sprint2/linha-do-tempo-causal.png`):

```
[agencia-1] CRIAR_CONTA [0, 1, 0]  ||  [agencia-2] CRIAR_CONTA [0, 0, 1]
```

Faz sentido. As duas contas foram criadas **em paralelo** (três requisições
disparadas ao mesmo tempo, uma por agência), cada uma por uma requisição HTTP
independente. A Agência 1 e a Agência 2 nunca trocaram mensagem nenhuma (todas
as transferências do teste foram da Agência 0 para a 1). O vetor da Agência 1
tem 0 na posição 2, e o da Agência 2 tem 0 na posição 1: nenhum sabe da
existência do outro evento. Não há como a criação da conta 1 ter causado a da
conta 2, nem o contrário. A ordem de hora de parede entre eles (`.962` × `.982`)
é só um acaso de agendamento.

Outro par que também aparece e mostra a diferença para a hora de parede:
`[agencia-0] TRANSFERENCIA_DEBITO [2, 0, 0]  ||  [agencia-2] CRIAR_CONTA [0, 0, 1]`.
O débito aconteceu depois na hora de parede, mas é concorrente com a criação da
conta 2, que não participou da transferência.

O contraponto causal está na última seção da mesma saída:
`TRANSFERENCIA_PUBLICADA [3, 0, 0] -> TRANSFERENCIA_CREDITO_REMOTO [3, 2, 0]
relacao=ANTES`. O débito `[2, 0, 0]` e o crédito `[3, 2, 0]` **não** aparecem
na lista de concorrentes, porque `[2,0,0] ≤ [3,2,0]`.

**3. O algoritmo é O(n²). Seria um problema com milhões de eventos? Como tornar
mais escalável?**

Sim. Com n = 10⁶ eventos são ~5 × 10¹¹ comparações de vetor, inviável. E a
saída também é quadrática: a maioria dos pares entre agências independentes é
concorrente. No meu teste, com só 12 eventos, já foram 18 pares. Ideias:

- **Perguntar algo mais útil do que "todos os pares".** Na prática interessa a
  concorrência entre eventos que **conflitam**, por exemplo operações sobre a
  *mesma conta*. Agrupar por conta e comparar só dentro do grupo reduz
  drasticamente o n de cada comparação.
- **Explorar a monotonicidade dentro de cada agência.** Os eventos de uma
  agência têm vetores crescentes (a própria posição sempre aumenta). Para um
  evento `e` da agência A e a sequência da agência B, os eventos de B que vêm
  *antes* de `e` formam um prefixo, e os que vêm *depois*, um sufixo. Busca
  binária acha as duas fronteiras, e o que fica no meio é concorrente com `e`.
  Isso dá O(n log n) para *contar* os pares (listá-los continua proporcional à
  saída).
- **Janelas de tempo / processamento em fluxo.** Comparar só eventos próximos,
  já que pares muito distantes quase sempre estão ligados por alguma cadeia de
  mensagens, e processar incrementalmente conforme os eventos chegam, em vez de
  em lote.
- **Paralelizar/distribuir** (as comparações são independentes; map-reduce por
  partição) e **ordenar pela soma do vetor**: se a → b então soma(V(a)) <
  soma(V(b)), o que permite podar candidatos.

---

# Sprint 1 - REST/MVC + Relógio de Lamport

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

**Funcionalidade escolhida:** Histórico de transações por conta.

**O que faz:** novo endpoint `GET /contas/{id}/historico?limite=N` (protegido por
JWT). Lê o log de eventos da agência (`data/eventos-agencia-<id>.jsonl`), filtra
os eventos que envolvem aquela conta - olhando os campos `id`, `idConta`,
`idOrigem` e `idDestino` dentro de `detalhes` -, ordena por timestamp de Lamport
e devolve os `N` mais recentes (padrão 20, teto 500). A resposta traz
`total` (quantos eventos a conta tem no total) e a lista `eventos`. Cobre
criação, depósitos, saques e as duas pontas de transferência (débito, crédito,
crédito remoto e falha). Conta inexistente na agência → 404; `limite` fora de
1..500 → 422.

Código: `agencia/src/controllers/historico_controller.py` +
rota em `agencia/src/rotas.py`.

**Por que escolhemos:** é comportamento novo e observável (um endpoint que não
existia, com regra própria e parâmetro de consulta), encaixa direto no que o
sprint já produz (o log de eventos com Lamport) e é a base natural de um extrato
bancário - algo que os próximos sprints vão reaproveitar. Também exercita a
leitura do mesmo log que o `mesclar_logs.py` usa, reforçando a Parte E.

**Evidência:** `evidencias/sprint1/funcionalidade-adicional.png`
(gerar com `evidencias/sprint1/demos/08-historico.sh`).

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

A linha do tempo mesclada trouxe vários timestamps de Lamport repetidos, vindos
de agências diferentes (os valores de `horaParede` abaixo variam a cada
execução - estes são de uma execução real):

| Lamport | Eventos (agências diferentes) | Relação |
|---|---|---|
| 1 | `CRIAR_CONTA` em agencia-0, agencia-1 e agencia-2 | concorrentes |
| 2 | `DEPOSITO` em agencia-0, agencia-1 e agencia-2 | concorrentes |
| 3 | `TRANSFERENCIA_DEBITO` (agencia-0) e `SAQUE` (agencia-2) | concorrentes |

Nenhum desses pares é causalmente relacionado: criar a conta 1 na agencia-1 não
depende de criar a conta 0 na agencia-0, o saque na agencia-2 não depende do
débito na agencia-0. São operações independentes que por acaso caíram no mesmo
ponto do contador de cada agência.

**A ordem por `horaParede` NÃO coincide com a ordem da linha do tempo:**

- No `[Lamport 3]`, o `TRANSFERENCIA_DEBITO` da agencia-0 tem `horaParede`
  `...930780` e o `SAQUE` da agencia-2 tem `...950166`: os dois compartilham o
  timestamp de Lamport 3, mesmo tendo acontecido em instantes físicos
  diferentes - são concorrentes.
- O evento `[Lamport 5]` (`TRANSFERENCIA_CREDITO_REMOTO` na agencia-1,
  `horaParede ...943366`) aparece na lista **depois** do `[Lamport 3]` `SAQUE` da
  agencia-2 (`horaParede ...950166`), mas pelo relógio **físico** o evento de
  Lamport 5 aconteceu **antes**. Isso **não é um erro**: os dois são
  concorrentes, então nenhuma das duas ordens é "a certa". O relógio de Lamport
  só se compromete a respeitar a ordem de eventos **causalmente ligados** - por
  exemplo, o `TRANSFERENCIA_DEBITO` de Lamport 3 (agencia-0) vem antes do
  `TRANSFERENCIA_CREDITO_REMOTO` de Lamport 5 (agencia-1), que é o seu efeito
  direto.

---

## Parte F - Autenticação JWT (seção 11.3)

### Justificativas de design

**Formato das credenciais escolhido e por quê:**

**Usuário + senha** (os integrantes: `lara` e `allan`). É o modelo mais familiar
e suficiente para o escopo. Como não há cadastro nem banco de dados neste sprint,
o store de usuários é fixo em memória (`agencia/src/seguranca.py`), mas as senhas
**não** ficam em texto puro: cada uma é guardada como hash
**PBKDF2-HMAC-SHA256** com 200 000 iterações e um **salt aleatório por usuário**,
e a verificação usa comparação em tempo constante (`hmac.compare_digest`).
Usuário inexistente ainda gasta o tempo de um hash, para não virar um oráculo de
timing. Em produção, esse store viria de um banco e o algoritmo seria bcrypt ou
argon2.

Não escolhemos "id de conta + senha" porque um mesmo aluno pode ter várias
contas (inclusive em agências diferentes): quem se autentica é a **pessoa**, não
a conta.

**A chamada interna agência-a-agência (`creditar-remoto`) carrega token ou é
tratada de forma diferente? Justificativa:**

É tratada **de forma diferente**. O endpoint `creditar-remoto` exige um JWT de
**escopo `"interno"`**, emitido pela própria agência de origem
(`sub = "agencia-<id>"`), com validade curta (30 s) e assinado com o mesmo
segredo. A dependency `requer_token_interno` rejeita (403) um token de usuário
comum nesse endpoint.

Não repassamos o token do usuário final por três motivos:

1. A chamada é **máquina-a-máquina**; não há um "usuário" a ser representado ali
   - quem age é a agência.
2. Repassar o token do usuário **espalharia a credencial** dele para além do
   necessário (mais superfície de vazamento) e **acoplaria** o sucesso de uma
   operação interna ao tempo de vida da sessão do usuário (o token poderia
   expirar no meio de uma transferência multi-salto).
3. Um escopo dedicado deixa a **fronteira de confiança explícita**: o
   `creditar-remoto` sabe que só aceita chamadas de outra agência.

Alternativa também aceitável: deixar `creditar-remoto` sem autenticação,
assumindo que as agências ficam numa rede isolada. Preferimos a autenticação
explícita para não depender dessa suposição de topologia.

### Questões

**1. Qual a diferença entre autenticação e autorização? Sua implementação
verifica só uma das duas, ou as duas? Um usuário autenticado consegue sacar de
uma conta que não é dele?**

**Autenticação** é provar *quem você é* (aqui: apresentar usuário + senha no
`/auth/login` e receber um token; depois, cada requisição prova a identidade pela
assinatura do token). **Autorização** é decidir se essa identidade *pode* fazer
aquela ação sobre aquele recurso.

Nossa implementação faz **essencialmente só autenticação**: qualquer token
válido pode operar qualquer conta da agência. Não há vínculo entre o `sub` do
token e o dono da conta. Então **sim** - um usuário autenticado (ex.: `allan`)
consegue sacar da conta da `lara`, porque não existe checagem de autorização por
recurso. A única exceção de "autorização" na implementação é o `creditar-remoto`,
que exige escopo `interno`. Corrigir o resto exigiria guardar o dono de cada
conta e comparar com o `sub` do token antes de cada operação (fica como melhoria
futura).

**2. Por que o servidor não precisa consultar um banco de dados para validar a
assinatura de um JWT a cada requisição? O que isso implica sobre escalabilidade
comparado a guardar sessões em memória?**

O JWT é **autocontido e assinado**. A assinatura HS256 é
`HMAC-SHA256(header + "." + payload, segredo)`. Para validar, o servidor
**recomputa** o HMAC com o segredo que só ele conhece e compara; se bater, o
conteúdo não foi adulterado e veio de quem tem o segredo. Os dados de identidade
(`sub`, `exp`) já estão dentro do token. Nada disso precisa de I/O - é só CPU.

Implicação: **estado zero de sessão no servidor**. Qualquer instância de qualquer
agência valida qualquer token sem coordenação e sem consultar um store
compartilhado. Escala horizontalmente "de graça" e não tem o gargalo nem o ponto
único de falha de um store de sessões. O preço: não dá para **revogar** um token
antes de ele expirar (com sessão em memória, bastaria apagar a entrada). Por isso
a expiração curta importa.

**3. O que aconteceria com a segurança do sistema se a chave secreta usada para
assinar o JWT vazasse?**

Quem tiver o segredo pode **forjar tokens válidos arbitrários**: escolher
qualquer `sub`, qualquer `escopo` (inclusive `interno`) e qualquer `exp` no
futuro. O servidor aceitaria todos como legítimos, porque a única verificação é
"a assinatura bate com o segredo". Na prática, o atacante se autentica como
qualquer usuário e chama qualquer rota protegida - inclusive o `creditar-remoto`
entre agências - e não há como distinguir o token forjado de um real.

Mitigação: rotacionar o segredo imediatamente (isso invalida **todos** os tokens
em circulação, inclusive os legítimos), manter segredos diferentes por ambiente,
guardá-los fora do código (variável de ambiente / cofre de segredos, nunca
commitados) e, idealmente, suportar rotação de chaves com `kid` no cabeçalho do
token.

---

## Parte G - Frontend (seção 12.3)

### Justificativas de design

**Framework escolhido e forma de guardar o token:**

**React + Vite** (JavaScript puro, sem TypeScript). Motivos: é o stack de
frontend mais usado como referência, o Vite dá servidor de desenvolvimento
rápido e build sem configuração, e ficar em JS puro reduz o número de peças para
um sprint. O app é montado em `src/main.jsx`; a árvore fica em `src/App.jsx`.

**Token guardado no `localStorage`** (chave `iceibank.token`). Vantagens: simples
e sobrevive a recarregar a página (o app já inicia autenticado se houver token).
Como enviamos o token no cabeçalho `Authorization` (e não em cookie), não há
exposição automática a CSRF. O risco conhecido do `localStorage` é um XSS
conseguir ler o token; mitigamos mantendo a expiração curta (30 min) e não
injetando HTML de terceiros. `sessionStorage` seria a alternativa se quiséssemos
que a sessão sumisse ao fechar a aba. A agência selecionada também é persistida
(`iceibank.agencia`).

### Questões

**1. Como o frontend "lembra" de reenviar o token em cada requisição depois do
login? Descreva o mecanismo implementado.**

No login bem-sucedido, o `access_token` devolvido por `/auth/login` é salvo no
`localStorage` (`setToken()` em `src/api/cliente.js`). **Toda** requisição à API
passa por uma única função, `requisitar()`, no mesmo arquivo - nenhum componente
chama `fetch` diretamente. Antes de cada `fetch`, `requisitar()` lê o token do
`localStorage` e adiciona o cabeçalho `Authorization: Bearer <token>`. Assim o
reenvio é automático e centralizado num só ponto, e o token sobrevive a um
reload da página.

**2. Se o token expirar enquanto alguém está usando o frontend no meio de uma
operação, o que acontece na sua implementação? A interface avisa a pessoa?**

A `requisitar()` inspeciona o status da resposta. Ao receber **401**, ela: (1)
apaga o token do `localStorage`; (2) lança um erro do tipo `SessaoExpirada` com
a mensagem vinda da API ("Token expirado."). No `App.jsx`, o wrapper
`executar()` reconhece esse tipo específico, volta o estado para
não-autenticado (a tela de login reaparece) e mostra a mensagem no **banner
vermelho** no topo. Ou seja, **a interface avisa explicitamente** - a pessoa vê
"Token expirado." / "Sua sessão expirou. Entre novamente." e volta ao login, em
vez de só um erro no console.

**3. Esta unidade trata de arquitetura MVC. No seu frontend, onde fica o "M"
(Model), o "V" (View) e o "C" (Controller)?**

- **Model - `src/api/`.** `cliente.js` (infra HTTP: injeta o token, trata 401,
  converte resposta != 2xx em `ErroApi`/`SessaoExpirada`, guarda token e agência
  no `localStorage`), `auth.js` (login) e `contas.js` (`consultarSaldo`,
  `depositar`, `sacar`, `transferir`, `criarConta`, `agenciaDaConta`). É onde
  mora "o que o sistema faz" e o acesso ao estado persistido.
- **View - `src/componentes/`.** `Login`, `FormCriarConta`, `ConsultaSaldo`,
  `FormValor` (reusado em Depósito e Saque), `FormTransferencia`, `Mensagem`.
  Componentes de apresentação: renderizam, capturam entrada, recebem tudo por
  props e avisam o pai por callbacks; não sabem como a API funciona.
- **Controller - `src/App.jsx`.** Guarda o estado da tela (autenticado, agência,
  conta consultada, mensagem, "ocupado"), liga os eventos da View às funções do
  Model (`aoEntrar`, `aoConsultar`, `aoDepositar`, `aoSacar`, `aoTransferir`) e
  decide o que exibir (login ou painel). O wrapper `executar()` concentra o
  fluxo comum: marca "ocupado", chama o Model e transforma sucesso/erro em
  mensagem visível.

A separação é razoavelmente clara. Onde ela "mistura" mais é o próprio
`App.jsx`, que acumula o papel de Controller e de container da View - comum em
apps React pequenos. Dava para extrair um hook `useSessao()` para isolar melhor
a lógica de autenticação.
