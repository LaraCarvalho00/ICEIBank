# Evidencia: transferencia entre agencias via RabbitMQ (ambas no ar).
# Print -> evidencias/sprint2/transferencia-assincrona.png
. "$PSScriptRoot\lib.ps1"
$host.UI.RawUI.WindowTitle = 'Demo 1 - transferencia assincrona'
Get-Date
Entrar

Titulo 'Contas criadas em agencias diferentes (sem relacao entre si)'
req POST 4000/contas '{"id":0,"nomeAluno":"Ana","saldoInicial":100}'
req POST 4001/contas '{"id":1,"nomeAluno":"Bia","saldoInicial":0}'
req POST 4002/contas '{"id":2,"nomeAluno":"Caio","saldoInicial":50}'

Titulo 'Transferencia: 30 da conta 0 (Agencia 0) para a conta 1 (Agencia 1)'
req POST 4000/transferencias '{"idOrigem":0,"idDestino":1,"valor":30}'
Nota 'A resposta 200 so diz que a mensagem foi publicada; o credito e assincrono.'
Start-Sleep 2

Titulo 'Saldos depois'
req GET 4000/contas/0
req GET 4001/contas/1

Logs 0
Logs 1
Nota 'Ag0: ao_enviar -> TRANSFERENCIA_PUBLICADA [3,0,0]'
Nota 'Ag1: ao_receber([3,0,0]) com vetor local [0,1,0] -> max = [3,1,0], +1 na propria posicao -> [3,2,0]'

Write-Host ""
Write-Host "Fim da demo - $(Get-Date)" -ForegroundColor Green
