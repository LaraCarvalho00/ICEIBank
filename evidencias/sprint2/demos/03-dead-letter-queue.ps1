# Evidencia da funcionalidade adicional: dead-letter queue + reprocessamento.
# Rodar DEPOIS da demo 2. Print -> evidencias/sprint2/funcionalidade-adicional.png
. "$PSScriptRoot\lib.ps1"
$host.UI.RawUI.WindowTitle = 'Demo 3 - dead-letter queue'
Get-Date
Entrar

Titulo 'O credito que falhou esta na DLQ da Agencia 1 (nao foi descartado)'
req GET 4001/mensagens-mortas

Titulo 'Recriando a conta 1 que se perdeu no reinicio'
req POST 4001/contas '{"id":1,"nomeAluno":"Bia","saldoInicial":0}'

Titulo 'Reprocessando a DLQ: as mensagens voltam para a fila principal'
req POST 4001/mensagens-mortas/reprocessar
Start-Sleep 2

Titulo 'Resultado'
req GET 4001/contas/1
Filas
Nota 'Conta 1 com saldo 20 e DLQ vazia: o credito foi aplicado na segunda tentativa.'

Write-Host ""
Write-Host "Fim da demo - $(Get-Date)" -ForegroundColor Green
