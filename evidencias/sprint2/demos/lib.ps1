# Funções compartilhadas pelos scripts de demonstração do Sprint 2.
# Cada demo faz: . "$PSScriptRoot\lib.ps1"
$ErrorActionPreference = 'Stop'
$Agencia = Resolve-Path "$PSScriptRoot\..\..\..\agencia"
Set-Location $Agencia

function Titulo($texto) { Write-Host "`n=== $texto ===" -ForegroundColor Cyan }
function Nota($texto)   { Write-Host "# $texto" -ForegroundColor Yellow }

function Py { & python -m uv run python @args }

function Entrar {
    $login = Invoke-RestMethod -Method Post -Uri http://127.0.0.1:4000/auth/login `
        -ContentType 'application/json' -Body '{"usuario":"lara","senha":"iceibank"}'
    $script:H = @{ Authorization = "Bearer $($login.access_token)" }
}

# req METODO PORTA/CAMINHO [JSON] -> imprime a chamada, o corpo e o status HTTP
function req($metodo, $caminho, $corpo) {
    Write-Host "$metodo http://127.0.0.1:$caminho $corpo" -ForegroundColor DarkGray
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Method $metodo -Uri "http://127.0.0.1:$caminho" `
            -Headers $script:H -ContentType 'application/json' -Body $corpo
        Write-Host "  $($r.Content)  [HTTP $($r.StatusCode)]"
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $leitor = New-Object System.IO.StreamReader($resp.GetResponseStream())
            Write-Host "  $($leitor.ReadToEnd())  [HTTP $([int]$resp.StatusCode)]" -ForegroundColor Red
        } else { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red }
    }
}

function Agencias($acao, $ids = '0,1,2') {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$Agencia\dev-agencias.ps1" $acao $ids
}

function Filas { Titulo 'Filas no RabbitMQ'; Py ver_filas.py }

function Logs($id) {
    Titulo "Log da Agencia $id (data\eventos-agencia-$id.jsonl)"
    $arquivo = "$Agencia\data\eventos-agencia-$id.jsonl"
    if (Test-Path $arquivo) {
        Get-Content $arquivo | ForEach-Object {
            $e = $_ | ConvertFrom-Json
            "  vetor=[$($e.timestampVetorial -join ', ')]  $($e.tipo)  $($e.detalhes | ConvertTo-Json -Compress)"
        }
    } else { '  (vazio)' }
}
