# scripts/make_manifest.ps1
# Gera docs/MANIFEST.txt DELEGANDO a scripts/make_manifest.sh.
#
# Por que delegar em vez de reimplementar (2026-07-27):
# havia duas implementacoes independentes, e elas divergiam em SEIS eixos --
# separador de caminho (./docs/x.md vs .\docs\x.md), BOM, fim de linha
# (LF vs CRLF), texto do cabecalho, criterio de ordenacao (LC_ALL=C sobre o
# caminho relativo vs Sort-Object sobre o caminho absoluto) e contagem de
# linhas (wc -l conta quebras; (Get-Content).Count conta linhas, e as duas
# discordam em arquivo sem quebra final).
#
# Consequencia pratica: o MANIFEST e versionado, entao trocar de plataforma
# reescrevia as 126 linhas e enchia o historico de diff-fantasma -- e comparar
# a integridade ENTRE maquinas, que e a razao de existir do arquivo, era
# impossivel porque nenhuma linha batia.
#
# Fazer as duas implementacoes concordarem exigiria mante-las em sincronia
# para sempre. Fonte unica resolve por construcao: uma implementacao so.

$ErrorActionPreference = "Stop"

# Raiz do projeto = pasta-pai do diretorio deste script (mesmo criterio do
# build.ps1). O .sh usa caminhos relativos, entao precisa rodar da raiz.
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

# ATENCAO (aprendido na primeira execucao real, 2026-07-27): nao basta achar o
# bash. As coreutils que o .sh usa (sha256sum, cut, wc, sort, find) ficam em
# C:\msys64\usr\bin, enquanto o build.ps1 poe no PATH apenas
# C:\msys64\ucrt64\bin (onde moram gcc e luajit). E bash NAO-interativo nao le
# /etc/profile, entao herda o PATH do Windows tal como esta -- sem as
# ferramentas. Resultado da primeira tentativa: "sha256sum: command not found".
# Por isso garantimos aqui o diretorio das coreutils no PATH.
$MsysUsrBin = "C:\msys64\usr\bin"

$Bash = $null
if (Test-Path (Join-Path $MsysUsrBin "bash.exe")) {
    # Local canonico do MSYS2: o bash convive com as coreutils.
    $Bash = Join-Path $MsysUsrBin "bash.exe"
} else {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { $Bash = $cmd.Source }
}

if (-not $Bash) {
    throw "bash nao encontrado (PATH nem $MsysUsrBin\bash.exe). " +
          "O MANIFEST e gerado por scripts/make_manifest.sh; instale o MSYS2 " +
          "(o build.ps1 -Setup faz isso) e rode de novo."
}

# Poe no PATH o diretorio do proprio bash (onde ficam suas coreutils irmas) e,
# se existir e for diferente, o usr\bin canonico.
$BashDir = Split-Path -Parent $Bash
foreach ($dir in @($BashDir, $MsysUsrBin)) {
    if ((Test-Path $dir) -and ($env:Path -notlike "*$dir*")) {
        $env:Path = "$dir;$env:Path"
    }
}

& $Bash "scripts/make_manifest.sh"
if ($LASTEXITCODE -ne 0) {
    throw "make_manifest.sh falhou (codigo $LASTEXITCODE). Verifique se as " +
          "coreutils do MSYS2 (sha256sum, cut, wc, sort, find) estao em " +
          "$MsysUsrBin."
}
