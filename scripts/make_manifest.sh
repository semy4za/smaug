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

# Verificacao previa das ferramentas (2026-07-27). Antes daqui o script escrevia
# direto no arquivo final: se uma ferramenta faltasse no meio do caminho, o
# redirecionamento ja tinha truncado o MANIFEST e sobrava so o cabecalho --
# destruindo o arquivo valido anterior e deixando um que PARECE bom (cabecalho
# certo, algumas entradas) mas omite arquivos. Como a verificacao so confere o
# que esta listado, arquivo omitido nao seria detectado: falha silenciosa a
# partir de uma falha barulhenta. Aconteceu de verdade no Windows, quando o
# wrapper .ps1 chamou o bash sem as coreutils do MSYS2 no PATH.
for tool in sha256sum cut wc sort; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERRO: '$tool' nao encontrado no PATH." >&2
    echo "  O MANIFEST precisa de sha256sum, cut, wc e sort." >&2
    echo "  No Windows/MSYS2 elas ficam em C:\\msys64\\usr\\bin." >&2
    exit 127
  fi
done

# Procedência: sobre qual commit esta árvore foi gerada, e se havia alteração
# não commitada. Sem isto, um MANIFEST antigo valida limpo contra a própria
# árvore antiga e NÃO denuncia que a cópia está atrás — foi o que aconteceu em
# 2026-07-27, quando um zip da máquina Windows (desatualizada) passou na
# verificação de integridade sem levantar suspeita. Hash de arquivo prova
# consistência interna; só a procedência prova QUAL árvore é.
# Degrada com elegância: fora de um repositório git, imprime "sem git".
commit="sem git"
if git rev-parse --git-dir >/dev/null 2>&1; then
  commit=$(git rev-parse --short HEAD 2>/dev/null || echo "sem commit")
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    commit="$commit + alteracoes nao commitadas"
  fi
fi

# Escrita atomica: monta num temporario e so troca pelo definitivo no fim. Se
# algo falhar no meio, o MANIFEST anterior permanece intacto.
tmp=$(mktemp "${out}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

{
  echo "# Smaug -- MANIFEST de integridade"
  echo "# Gerado por scripts/make_manifest.sh (o .ps1 delega a este)"
  echo "# Arvore: $commit"
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
               -o -name '.env.example' -o -name 'LICENSE' \) \
            -not -path './build/*' -not -path './.git/*' | LC_ALL=C sort)
  echo "#"
  echo "# total de arquivos: $total"
} > "$tmp"

mv "$tmp" "$out"
trap - EXIT
echo "MANIFEST gerado: $out ($total arquivos)"
