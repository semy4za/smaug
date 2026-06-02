#!/usr/bin/env bash
# Gera docs/MANIFEST.txt: sha256 + linhas de cada arquivo versionável.
# Uso: bash scripts/make_manifest.sh   (rode da raiz do projeto)
# Serve para detectar perda/divergência de arquivos ao transferir o projeto.
set -euo pipefail

# Força o find do Unix. No Windows (MSYS2/Git Bash chamado do PowerShell), o
# PATH pode resolver "find" para o FIND.EXE do Windows, que tem sintaxe
# incompatível. Usamos o caminho absoluto quando ele existe.
FIND=find
[ -x /usr/bin/find ] && FIND=/usr/bin/find

out="docs/MANIFEST.txt"
{
  echo "# Smaug -- MANIFEST de integridade"
  echo "# Gerado por scripts/make_manifest.sh"
  echo "# Formato: <sha256>  <linhas>  <caminho>"
  echo "#"
  total=0
  while IFS= read -r f; do
    h=$(sha256sum "$f" | cut -d' ' -f1)
    n=$(wc -l < "$f")
    printf "%s  %6s  %s\n" "$h" "$n" "$f"
    total=$((total+1))
  done < <("$FIND" . -type f \
            \( -name '*.c' -o -name '*.h' -o -name '*.lua' -o -name '*.md' \
               -o -name 'Makefile' -o -name '*.ps1' -o -name '*.sh' \
               -o -name '.gitattributes' -o -name '.gitignore' \
               -o -name '.env.example' \) \
            -not -path './build/*' -not -path './.git/*' | sort)
  echo "#"
  echo "# total de arquivos: $total"
} > "$out"
echo "MANIFEST gerado: $out ($total arquivos)"
