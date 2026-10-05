# Evidencia: linha do tempo causal com pares concorrentes (relogio vetorial).
# Rodar DEPOIS das demos 1-3. Print -> evidencias/sprint2/linha-do-tempo-causal.png
. "$PSScriptRoot\lib.ps1"
$host.UI.RawUI.WindowTitle = 'Demo 4 - linha do tempo causal'
Get-Date
Py mesclar_logs.py --limite 10
Write-Host ''
Nota 'Concorrentes: ex. CRIAR_CONTA [0,1,0] (Ag1) || CRIAR_CONTA [0,0,1] (Ag2) - nenhuma mensagem entre elas.'
Nota 'Causal: TRANSFERENCIA_PUBLICADA [3,0,0] -> TRANSFERENCIA_CREDITO_REMOTO [3,2,0] = ANTES (nao aparece nos concorrentes).'

Write-Host ""
Write-Host "Fim da demo - $(Get-Date)" -ForegroundColor Green
