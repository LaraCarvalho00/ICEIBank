# ICEIBank - app Flutter (Sprint 3)

App mobile do ICEIBank. Fala com as 3 agências (FastAPI) usando a mesma API
REST dos Sprints 1-2, mais as rotas novas do Sprint 3 (`/bully/lider` e
`/sync/operacoes`).

## Funcionalidades

- **Fluxo bancário:** login (JWT), abrir/criar conta, saldo, depósito, saque e
  transferência. A agência de cada conta é `id % 3`, como no frontend web.
- **Painel de liderança** (aba *Liderança*): consulta `GET /bully/lider` das 3
  agências a cada 2 s e mostra a líder atual, o estado de cada agência e o
  histórico de transições. A líder aparece também na barra superior de todas as
  abas, então o failover fica visível em qualquer tela.
- **Offline-first** (aba *Sincronização*):
  - contas, fila e histórico ficam salvos no aparelho (`shared_preferences`);
  - depósito/saque sem conexão entram na fila com o `vetorBase` (versão da
    conta em cache);
  - o saldo exibido já inclui as pendentes (UI otimista). Se uma operação
    entrar em conflito ou for rejeitada, o efeito dela sai do saldo;
  - ao reconectar, a fila é enviada sozinha, em ordem (`connectivity_plus` e
    uma tentativa a cada 4 s);
  - um **HTTP 409** aparece como cartão vermelho com a versão que o app
    conhecia, a versão e o saldo do servidor e as escritas concorrentes. O
    usuário decide entre *Reaplicar sobre o saldo atual* e *Descartar*;
  - depósitos mesclados pelo servidor (funcionalidade adicional) aparecem no
    histórico como `MESCLADA`.
- **Simular offline** (menu ⋮): faz o app se comportar como se não houvesse
  rede, sem mexer na rede do emulador. Útil para a demonstração.
- Transferência e criação de conta **exigem conexão**. A transferência tira
  dinheiro para outra agência via RabbitMQ, e o app não tem como desfazer isso
  de forma otimista.

## Estrutura (MVC)

```
lib/
├── main.dart                     # inicia estado, monitor e sincronização automática
├── config.dart                   # portas, host padrão, id % 3, intervalos
├── modelos.dart                  # MODEL: ContaLocal, OperacaoPendente, EstadoAgencia...
├── servicos/
│   ├── api.dart                  # MODEL (infra): cliente HTTP, JWT, timeout, erros (409 -> ConflitoSincronizacao)
│   ├── armazenamento.dart        # MODEL (infra): persistência local
│   ├── estado_app.dart           # CONTROLLER: sessão, contas, fila offline, sincronização
│   └── monitor_lideranca.dart    # CONTROLLER: painel de liderança (polling + transições)
├── telas/                        # VIEW
│   ├── login_tela.dart
│   ├── inicio_tela.dart          # abas, faixa offline/conflito, líder na barra
│   ├── contas_tela.dart
│   ├── conta_tela.dart           # saldo otimista + pendências da conta
│   ├── lideranca_tela.dart
│   └── sincronizacao_tela.dart   # fila, conflitos 409, histórico
└── widgets/                      # tema e componentes comuns
```

## Como rodar

Pré-requisitos: Flutter 3.50+ e as 3 agências no ar (`agencia/dev-agencias.sh start`).

```bash
cd app
flutter pub get
flutter run -d chrome        # ou -d macos, ou um emulador Android/iOS
```

O endereço das agências é configurável na tela de login (⚙) ou no menu
*Configurações*:

| Onde o app roda           | Host          |
|---------------------------|---------------|
| Web, macOS, simulador iOS | `localhost`   |
| Emulador Android          | `10.0.2.2` (padrão no Android) |
| Celular físico            | IP da máquina na rede (subir as agências com `--host 0.0.0.0`) |

Login: `lara` / `iceibank`.

## Testes

`test/integracao_test.dart` exercita o `EstadoApp` e o `MonitorLideranca`
contra as agências **reais**. Se elas estiverem fora do ar, os testes são
pulados. Os cenários são: fluxo bancário completo, failover real (o teste
derruba a líder com `dev-agencias.sh` e confere a transição no painel), fila
offline com sincronização em ordem, conflito 409 com reaplicação, e depósito
mesclado.

```bash
cd app && flutter test
```

> Nota (macOS): com Command Line Tools cujo SDK é mais novo que o linker, o
> `flutter test` pode falhar ao compilar o asset nativo do
> `shared_preferences_foundation` ("tapi error: unknown architecture"). Isso é
> do toolchain, não do app. Para contornar só nos testes, adicione
> temporariamente ao `pubspec.yaml`:
> `dependency_overrides: {shared_preferences_foundation: 2.5.4}`.
