# scripts\build.ps1
#
# Setup + build + testes do Smaug no Windows (sem make, sem Valgrind).
#
# O que faz:
#   1. (opcional, com -Setup) instala MSYS2 + gcc + luajit.
#   2. Compila o backend C em build\smaug.dll (nome que o ffi_loader
#      procura no Windows).
#   3. Compila e roda os testes em C de tests\c\ (test_alloc, test_ops,
#      test_ops_edge, test_bool, test_bool_lifecycle, test_string, test_cow,
#      test_io_c, test_datetime_c, test_ops_window; test_allocfail com
#      -Wl,--wrap; e test_stress com N grande).
#   4. Roda as 18 suites Lua com luajit (series/, dataset/, io/, props/).
#   5. Regenera o MANIFEST.txt (make manifest equivalente).
#
# Uso (a partir da raiz do projeto):
#   powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1 -Setup
#
# Observacoes:
#   * Valgrind nao existe no Windows; a checagem de leaks fica so no Linux.
#     Os testes de correcao rodam igual.
#   * Requer gcc e luajit no PATH (ou MSYS2 em C:\msys64). O -Setup resolve isso.
#
# NOTA: este arquivo e' deliberadamente ASCII puro (sem acentos) para evitar
# problemas de codificacao no Windows PowerShell 5.1.

[CmdletBinding()]
param(
    [switch]$Setup,
    [switch]$SkipLua,
    [switch]$SkipManifest
)

$ErrorActionPreference = "Stop"

# Raiz do projeto = pasta-pai do diretorio deste script.
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
Write-Host "Projeto: $Root" -ForegroundColor Cyan

$Msys2Bin = "C:\msys64\ucrt64\bin"

function Add-Msys2ToPath {
    if (Test-Path $Msys2Bin) {
        if ($env:Path -notlike "*$Msys2Bin*") {
            $env:Path = "$Msys2Bin;$env:Path"
        }
    }
}

function Find-Tool([string]$name) {
    Add-Msys2ToPath
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-Setup {
    Write-Host "== Setup da toolchain (MSYS2) ==" -ForegroundColor Yellow

    if (-not (Test-Path "C:\msys64\usr\bin\bash.exe")) {
        Write-Host "MSYS2 nao encontrado; instalando via winget..." -ForegroundColor Yellow
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $wg) {
            throw "winget indisponivel. Instale o MSYS2 de https://www.msys2.org e rode de novo."
        }
        winget install -e --id MSYS2.MSYS2 --accept-source-agreements --accept-package-agreements
    }

    $bash = "C:\msys64\usr\bin\bash.exe"
    if (-not (Test-Path $bash)) {
        throw "MSYS2 nao localizado em C:\msys64 apos a instalacao."
    }

    Write-Host "Instalando gcc + luajit + make (pacman)..." -ForegroundColor Yellow
    & $bash -lc "pacman -Sy --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-luajit mingw-w64-ucrt-x86_64-make"
    if ($LASTEXITCODE -ne 0) {
        throw "pacman falhou. Abra o 'MSYS2 UCRT64' e rode 'pacman -Syu' primeiro."
    }
    Add-Msys2ToPath
    Write-Host "Setup concluido." -ForegroundColor Green
}

if ($Setup) { Invoke-Setup }

$gcc = Find-Tool "gcc"
if (-not $gcc) {
    Write-Host "ERRO: gcc nao encontrado." -ForegroundColor Red
    Write-Host "Rode com -Setup para instalar a toolchain, ou instale o MSYS2 e:" -ForegroundColor Red
    Write-Host "  pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-luajit" -ForegroundColor Red
    exit 1
}
Write-Host "gcc:    $gcc" -ForegroundColor Green

$luajit = Find-Tool "luajit"
if ($luajit) {
    Write-Host "luajit: $luajit" -ForegroundColor Green
} else {
    Write-Host "luajit: nao encontrado - testes Lua serao pulados" -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force -Path "build" | Out-Null

# Fontes do backend: descobre TODOS os src\*.c automaticamente, para nunca
# dessincronizar quando um novo .c entra.
$sources = @(Get-ChildItem -Path "src" -Filter "*.c" | ForEach-Object { "src\$($_.Name)" })
if ($sources.Count -eq 0) { throw "Nenhum fonte encontrado em src\*.c" }
Write-Host ("Fontes ({0}): {1}" -f $sources.Count, ($sources -join ", ")) -ForegroundColor DarkGray

# Exporta a lista de fontes para o eixo 14 auditar o que foi compilado (12.29/A3).
# Normaliza para forward slash → build/SOURCES tem formato único nos dois OS.
($sources | ForEach-Object { $_ -replace '\\', '/' }) | Set-Content -Path "build/SOURCES" -Encoding ASCII

Write-Host ""
Write-Host "== Compilando build\smaug.dll ==" -ForegroundColor Cyan
& $gcc -std=c11 -Wall -Wextra -O2 -I".\include" -shared -static-libgcc -o "build\smaug.dll" @sources
if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar a DLL." }
Write-Host "OK -> build\smaug.dll" -ForegroundColor Green

$cTests      = @("test_alloc", "test_ops", "test_ops_edge", "test_bool", "test_bool_lifecycle", "test_string", "test_cow", "test_io_c", "test_datetime_c", "test_ops_window")
$cTestsWrap  = @("test_allocfail")
$cTestsStress = @("test_stress")
$allPass = $true

Write-Host ""
Write-Host "== Testes em C ==" -ForegroundColor Cyan
foreach ($t in $cTests) {
    $exe = "build\$t.exe"
    & $gcc -std=c11 -g -O0 -Wall -Wextra -I".\include" "tests\c\$t.c" @sources -lm -o $exe
    if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar $t." }

    $out = (& ".\$exe") | Out-String
    $out = $out.Trim()
    Write-Host ("{0,-14} -> {1}" -f $t, $out)
    if ($out -notlike "PASS*") { $allPass = $false }
}

foreach ($t in $cTestsWrap) {
    $exe = "build\$t.exe"
    $cargs = @(
        "-std=c11", "-g", "-O0", "-Wall", "-Wextra", "-I.\include",
        "-Wl,--wrap=malloc", "-Wl,--wrap=realloc", "-Wl,--wrap=calloc", "-Wl,--wrap=strdup",
        "tests\c\$t.c"
    ) + $sources + @("-lm", "-o", $exe)
    & $gcc @cargs
    if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar $t." }

    $out = (& ".\$exe") | Out-String
    $out = $out.Trim()
    Write-Host ("{0,-14} -> {1}" -f $t, $out)
    if ($out -notlike "PASS*") { $allPass = $false }
}

Write-Host ""
Write-Host "== Testes de Stress ==" -ForegroundColor Cyan
foreach ($t in $cTestsStress) {
    $exe = "build\$t.exe"
    & $gcc -std=c11 -g -O0 -Wall -Wextra -I".\include" "tests\c\$t.c" @sources -lm -o $exe
    if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar $t." }

    $out = (& ".\$exe") | Out-String
    $out = $out.Trim()
    $lastLine = ($out -split "`n")[-1].Trim()
    Write-Host ("{0,-14} -> {1}" -f $t, $lastLine)
    if ($lastLine -notlike "PASS*") { $allPass = $false }
}

if ($luajit -and -not $SkipLua) {
    Write-Host ""
    Write-Host "== Testes em Lua ==" -ForegroundColor Cyan
    $luaTests = @("core/test_keys", "core/test_collation",
                  "series/test_constructors", "series/test_access", "series/test_reduce",
                  "series/test_stat", "series/test_window", "series/test_predicates",
                  "series/test_selection", "series/test_str", "series/test_dt", "series/test_categorical",
                  "dataset/test_core", "dataset/test_relational", "dataset/test_stat", "dataset/test_io_support",
                  "io/test_csv", "io/test_json",
                  "props/test_props", "props/test_integration")
    foreach ($lt in $luaTests) {
        # Captura stdout e stderr separados para distinguir output normal de erros
        $ltPath = $lt -replace "/", "\"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $luajit
        $psi.Arguments = "tests\$ltPath.lua"
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute = $false
        $psi.WorkingDirectory = $Root

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $proc.Start() | Out-Null
        $stdout = $proc.StandardOutput.ReadToEnd().Trim()
        $stderr = $proc.StandardError.ReadToEnd().Trim()
        $proc.WaitForExit()
        $rc = $proc.ExitCode

        if ($rc -ne 0 -or $stdout -notlike "OK*") {
            # Falha real: mostra tudo, incluindo stack trace
            Write-Host "FALHOU: $lt" -ForegroundColor Red
            if ($stdout) { Write-Host $stdout }
            if ($stderr) { Write-Host $stderr -ForegroundColor Red }
            $allPass = $false
        } else {
            Write-Host $stdout
        }
    }
} elseif (-not $luajit) {
    Write-Host ""
    Write-Host "(Lua pulado: luajit nao encontrado. Rode com -Setup.)" -ForegroundColor Yellow
}

# Paridade da API (indicador permanente, nunca quebra build)
if ($luajit -and (Test-Path "scripts\parity\parity.ps1")) {
    Write-Host ""
    Write-Host "== Paridade da API ==" -ForegroundColor Cyan
    & powershell -ExecutionPolicy Bypass -File "scripts\parity\parity.ps1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Aviso: parity.ps1 reportou problemas (nao bloqueia o build)." -ForegroundColor Yellow
    }
}

# Regenera o MANIFEST.txt para refletir o estado atual do repo.
if (-not $SkipManifest) {
    Write-Host ""
    $manifestScript = "scripts\make_manifest.ps1"
    if (Test-Path $manifestScript) {
        Write-Host "== Manifest ==" -ForegroundColor Cyan
        & powershell -ExecutionPolicy Bypass -File $manifestScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Aviso: make_manifest.ps1 retornou erro (nao bloqueia o build)." -ForegroundColor Yellow
        }
    }
}

Write-Host ""
if ($allPass) {
    Write-Host "TUDO PASSOU." -ForegroundColor Green
    exit 0
} else {
    Write-Host "ALGUM TESTE FALHOU." -ForegroundColor Red
    exit 1
}
