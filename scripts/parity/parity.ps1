# scripts/parity/parity.ps1
# Roda todos os scripts de paridade e gera docs/PARITY_REPORT.md.
# Equivalente PowerShell do parity.sh.
#
# Princípio: cada script é independente. Falha em um não impede os outros.
# Nunca falha o build (indicador, não veredito).

$ErrorActionPreference = "Continue"

# Vai para a raiz do projeto (scripts/parity → ../..)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root      = Resolve-Path (Join-Path $scriptDir "..\..")
Set-Location $root

$out = "docs\PARITY_REPORT.md"

# Detecta luajit
$luajit = Get-Command luajit -ErrorAction SilentlyContinue
if (-not $luajit) {
    Write-Host "  parity: luajit nao encontrado, pulando" -ForegroundColor Yellow
    exit 0
}

# Header do relatório
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC")
@"
# Smaug — Relatório de Paridade

> Arquivo gerado por ``bash scripts/parity/parity.sh`` ou ``powershell scripts/parity/parity.ps1``.
> **Não editar à mão.** Decisões conscientes de não-paridade ficam em
> ``scripts/parity/exceptions.txt``.

Convenção de status:

- ✅ paridade presente
- ⚪ não aplicável (exceção registrada em ``exceptions.txt``)
- ⚠️ ausência sem registro — suspeita, requer revisão humana
- ❌ inconsistência clara — gap real

Gerado em: $now
"@ | Set-Content -Path $out -Encoding utf8

# Lista dos eixos
$eixos = @(
    "01_dtypes", "02_series_dataset", "03_c_lua_mirror", "04_anel2",
    "05_io_dtypes", "06_return_types", "07_null_handling", "08_naming",
    "09_sentinels", "10_lifecycle", "11_test_coverage", "12_docs_sync"
)

$failed = @()
foreach ($eixo in $eixos) {
    $script = "scripts\parity\$eixo.lua"
    if (-not (Test-Path $script)) {
        Write-Host "  AVISO  ${eixo}: script nao encontrado" -ForegroundColor Yellow
        $failed += $eixo
        continue
    }
    # Roda o script e anexa ao relatório
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = "luajit"
    $proc.StartInfo.Arguments = $script
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.RedirectStandardError = $true
    $proc.StartInfo.WorkingDirectory = $root
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -eq 0) {
        Add-Content -Path $out -Value $stdout -Encoding utf8 -NoNewline
        Write-Host "  OK     $eixo"
    } else {
        Write-Host "  FALHOU $eixo" -ForegroundColor Red
        if ($stderr) { Write-Host ("         " + ($stderr -replace "`n", "`n         ")) }
        $failed += $eixo
    }
}

# Resumo executivo no final
$reportText = Get-Content -Path $out -Raw

# Contagens — uso regex porque os marcadores são emojis multi-byte
$okCount   = ([regex]::Matches($reportText, "✅")).Count
$excCount  = ([regex]::Matches($reportText, "⚪")).Count
$warnCount = ([regex]::Matches($reportText, "⚠️")).Count
$errCount  = ([regex]::Matches($reportText, "❌")).Count

@"

---

## Resumo executivo


**Contagem global de status no relatório:**

- ✅ paridade: $okCount
- ⚪ exceção registrada: $excCount
- ⚠️ suspeita (revisar): $warnCount
- ❌ inconsistência clara: $errCount


## Como usar este relatório

1. Procure por ⚠️ — cada um é um candidato a gap real ou exceção a registrar.
2. Se for decisão consciente, adicione em ``scripts/parity/exceptions.txt``.
3. Se for gap real, registre em ``Roadmap.md`` ou corrija e rode novamente.
4. Procure por ❌ — sempre gap real, exige ação.
"@ | Add-Content -Path $out -Encoding utf8

Write-Host ""
Write-Host "Relatorio: $out"
# Indicador, não veredito: NUNCA quebra build, mesmo se eixo falhar
exit 0
