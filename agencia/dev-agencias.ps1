# Sobe/derruba as 3 agências do ICEIBank no Windows (conveniência de
# desenvolvimento - o roteiro sugere 3 terminais separados; este script abre
# um terminal por agência, já com Get-Date no topo para os prints).
#
#   .\dev-agencias.ps1 start          # abre uma janela por agência (0, 1 e 2)
#   .\dev-agencias.ps1 start 1        # sobe só a agência 1
#   .\dev-agencias.ps1 stop           # derruba as 3
#   .\dev-agencias.ps1 stop 1         # derruba só a agência 1 (teste de resiliência)
#   .\dev-agencias.ps1 status
#   .\dev-agencias.ps1 start -Oculto  # sem janela; log em data\dev-agencia-N.out
#
# A URL do RabbitMQ vem de $env:RABBITMQ_URL ou de agencia\.env.local.
# Se o PowerShell bloquear o script: powershell -ExecutionPolicy Bypass -File .\dev-agencias.ps1 start
param(
    [Parameter(Position = 0)][ValidateSet('start', 'stop', 'restart', 'status')][string]$Acao = 'status',
    [Parameter(Position = 1)][string]$Ids = '0,1,2',
    [switch]$Oculto
)

$ErrorActionPreference = 'Stop'
# Aceita "1", "1,2" ou "0 2" (com -File o PowerShell não converte "1,2" em array).
$ListaIds = @($Ids -split '[,\s]+' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })
$Pasta = $PSScriptRoot
$Offset = if ($env:OFFSET) { [int]$env:OFFSET } else { 0 }

function Porta($id) { 4000 + $Offset + $id }

function NoAr($id) {
    # 127.0.0.1 e não localhost: no Windows "localhost" tenta IPv6 (::1) primeiro
    # e o uvicorn escuta só em IPv4 - cada checagem demoraria o timeout inteiro.
    & curl.exe -s -o NUL -m 1 "http://127.0.0.1:$(Porta $id)/"
    $LASTEXITCODE -eq 0
}

function Uv {
    # Caminho completo: a janela nova roda com -NoProfile e pode não ter o uv no PATH.
    $exe = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { "& '$($exe.Source)'" } else { 'python -m uv' }
}

function Subir($id) {
    if (NoAr $id) { Write-Host "agencia ${id}: ja no ar na porta $(Porta $id)"; return }
    $porta = Porta $id
    $comando = "`$env:AGENCIA_ID='$id'; $(Uv) run uvicorn src.main:app --port $porta"
    if ($Oculto) {
        $log = Join-Path $Pasta "data\dev-agencia-$id.out"
        Start-Process powershell -WorkingDirectory $Pasta -WindowStyle Hidden `
            -RedirectStandardOutput $log -RedirectStandardError "$log.err" `
            -ArgumentList '-NoProfile', '-Command', $comando | Out-Null
    } else {
        $janela = "`$host.UI.RawUI.WindowTitle='ICEIBank - Agencia $id (porta $porta)'; Get-Date; $comando"
        Start-Process powershell -WorkingDirectory $Pasta -ArgumentList '-NoExit', '-NoProfile', '-Command', $janela | Out-Null
    }
    for ($i = 0; $i -lt 60; $i++) {
        if (NoAr $id) { Write-Host "agencia ${id}: no ar na porta $porta"; return }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "agencia ${id}: NAO subiu na porta $porta (veja a janela dela ou data\dev-agencia-$id.out.err)"
}

function Derrubar($id) {
    $conexoes = Get-NetTCPConnection -LocalPort (Porta $id) -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conexoes) {
        # O uvicorn roda dentro de um powershell (a janela da agência): derruba os dois.
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($c.OwningProcess)"
        Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
        if ($proc) {
            $pai = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.ParentProcessId)"
            while ($pai -and $pai.Name -notmatch 'powershell') {
                $pai = Get-CimInstance Win32_Process -Filter "ProcessId=$($pai.ParentProcessId)"
            }
            if ($pai) { Stop-Process -Id $pai.ProcessId -Force -ErrorAction SilentlyContinue }
        }
    }
    Write-Host "agencia $id (porta $(Porta $id)) derrubada"
}

switch ($Acao) {
    'start'   { foreach ($id in $ListaIds) { Subir $id } }
    'stop'    { foreach ($id in $ListaIds) { Derrubar $id } }
    'restart' { foreach ($id in $ListaIds) { Derrubar $id }; Start-Sleep 1; foreach ($id in $ListaIds) { Subir $id } }
    'status'  { foreach ($id in $ListaIds) { "agencia $id (porta $(Porta $id)): $(if (NoAr $id) {'NO AR'} else {'parada'})" } }
}
