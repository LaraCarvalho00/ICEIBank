# Evidencia: Agencia 1 fora do ar -> mensagem retida na fila -> Agencia 1 volta.
# Rodar DEPOIS da demo 1. Print -> evidencias/sprint2/resiliencia-fila.png
. "$PSScriptRoot\lib.ps1"
$host.UI.RawUI.WindowTitle = 'Demo 2 - resiliencia da fila'
Get-Date
Entrar

Titulo 'Derrubando a Agencia 1 (fecha a janela dela)'
Agencias stop 1
Agencias status

Titulo 'Transferencia de 20 da conta 0 para a conta 1, com a Agencia 1 FORA DO AR'
req POST 4000/transferencias '{"idOrigem":0,"idDestino":1,"valor":20}'
Nota 'Resposta 200 mesmo sem ninguem para consumir: a mensagem ficou na fila duravel.'
Filas
Nota 'fila-agencia-1 com 1 mensagem e 0 consumidores (confira tambem no RabbitMQ Manager).'

Write-Host ''
Read-Host 'PRINT 1: tire o print agora. Depois pressione Enter para religar a Agencia 1'

Titulo 'Religando a Agencia 1 (memoria zerada: a conta 1 nao existe mais)'
Agencias start 1
Start-Sleep 3
Filas
Logs 1
Nota 'A mensagem FOI entregue quando a Agencia 1 voltou, mas a conta 1 sumiu no reinicio:'
Nota 'CREDITO_REMOTO_FALHOU (conta nao encontrada). A mensagem foi para fila-agencia-1.dlq.'
Write-Host ''
Write-Host 'PRINT 2: tire o print desta janela + a janela nova da Agencia 1.' -ForegroundColor Green

Write-Host ""
Write-Host "Fim da demo - $(Get-Date)" -ForegroundColor Green
