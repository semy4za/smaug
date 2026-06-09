# scripts/make_manifest.ps1
# Gera docs/MANIFEST.txt
# Formato: <sha256> <linhas> <caminho>

$OutFile = "docs/MANIFEST.txt"

$Extensions = @(
    "*.c",
    "*.h",
    "*.lua",
    "*.md",
    "*.ps1",
    "*.sh"
)

$SpecialFiles = @(
    "Makefile",
    ".gitattributes",
    ".gitignore",
    ".env.example"
)

$Files = Get-ChildItem -Path . -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/]build[\\/]'
    } |
    Where-Object {
        ($Extensions | ForEach-Object { $_ }) -contains "*$($_.Extension)" -or
        $SpecialFiles -contains $_.Name
    } |
    Sort-Object FullName

$Lines = @(
    "# Smaug -- MANIFEST de integridade"
    "# Gerado por scripts/make_manifest.ps1"
    "# Formato: <sha256>  <linhas>  <caminho>"
    "#"
)

$Total = 0

foreach ($File in $Files) {
    $Hash = (Get-FileHash $File.FullName -Algorithm SHA256).Hash.ToLower()

    $LineCount = if ((Get-Item $File.FullName).Length -eq 0) {
        0
    }
    else {
        (Get-Content $File.FullName).Count
    }

    $RelativePath = Resolve-Path -Relative $File.FullName

    $Lines += "{0}  {1,6}  {2}" -f $Hash, $LineCount, $RelativePath

    $Total++
}

$Lines += "#"
$Lines += "# total de arquivos: $Total"

$Lines | Set-Content -Encoding UTF8 $OutFile

Write-Host "MANIFEST gerado: $OutFile ($Total arquivos)"