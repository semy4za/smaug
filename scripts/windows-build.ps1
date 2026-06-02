# scripts\windows-build.ps1
#
# Setup + build + testes do Smaug no Windows (sem make, sem Valgrind).
#
# O que faz:
#   1. (opcional, com -Setup) instala MSYS2 + gcc + luajit.
#   2. Compila o backend C em build\smaug.dll (nome que o ffi_loader
#      procura no Windows).
#   3. Compila e roda os testes em C (test_alloc, test_ops, test_bool).
#   4. Roda os testes Lua (test_series.lua, test_dataset.lua) com luajit.
#
# Uso (a partir da raiz do projeto):
#   powershell -ExecutionPolicy Bypass -File .\scripts\windows-build.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\windows-build.ps1 -Setup
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
    [switch]$SkipLua
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

$sources = @(
    "src\smaug_core.c",
    "src\smaug_ops_f64.c",
    "src\smaug_ops_i64.c",
    "src\smaug_ops_bool.c"
)

Write-Host ""
Write-Host "== Compilando build\smaug.dll ==" -ForegroundColor Cyan
& $gcc -std=c11 -Wall -Wextra -O2 -I".\include" -shared -static-libgcc -o "build\smaug.dll" @sources
if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar a DLL." }
Write-Host "OK -> build\smaug.dll" -ForegroundColor Green

$cTests = @("test_alloc", "test_ops", "test_bool")
$allPass = $true

Write-Host ""
Write-Host "== Testes em C ==" -ForegroundColor Cyan
foreach ($t in $cTests) {
    $exe = "build\$t.exe"
    & $gcc -std=c11 -g -O0 -Wall -Wextra -I".\include" "tests\$t.c" @sources -lm -o $exe
    if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar $t." }

    $out = (& ".\$exe") | Out-String
    $out = $out.Trim()
    Write-Host ("{0,-12} -> {1}" -f $t, $out)
    if ($out -ne "PASS") { $allPass = $false }
}

if ($luajit -and -not $SkipLua) {
    Write-Host ""
    Write-Host "== Testes em Lua ==" -ForegroundColor Cyan
    foreach ($lt in @("tests\test_series.lua", "tests\test_dataset.lua")) {
        $out = (& $luajit $lt) | Out-String
        $out = $out.Trim()
        Write-Host $out
        if ($out -notlike "OK*") { $allPass = $false }
    }
} elseif (-not $luajit) {
    Write-Host ""
    Write-Host "(Lua pulado: luajit nao encontrado. Rode com -Setup.)" -ForegroundColor Yellow
}

Write-Host ""
if ($allPass) {
    Write-Host "TUDO PASSOU." -ForegroundColor Green
    exit 0
} else {
    Write-Host "ALGUM TESTE FALHOU." -ForegroundColor Red
    exit 1
}
