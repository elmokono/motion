#!/bin/bash
# Falla si aparece una credencial real en los archivos de texto del repo.
# Los placeholders XXXXXXXXXXXXXXX se consideran validos.
#
# Uso:  ./scripts/check-secrets.sh
# Como pre-commit:  ln -s ../../scripts/check-secrets.sh .git/hooks/pre-commit

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLACEHOLDER="XXXXXXXXXXXXXXX"
fallos=0

buscar() { # $1=descripcion  $2=regex
  local hits
  hits=$(grep -rInE "$2" "$ROOT" \
    --include="*.py" --include="*.conf" --include="*.sh" --include="*.html" \
    --include="*.md" --include="*.service" --include="*.txt" --include="*.env" \
    2>/dev/null | grep -v "$PLACEHOLDER" | grep -v "check-secrets.sh")
  if [ -n "$hits" ]; then
    echo "FALLA: $1"
    echo "$hits" | sed 's/^/  /'
    fallos=$((fallos + 1))
  fi
}

# API key de Gemini: empieza con AQ. seguido de una cadena larga
buscar "API key de Gemini en claro" 'AQ\.[A-Za-z0-9_-]{20,}'
# Credenciales RTSP embebidas en la URL de la camara
buscar "password RTSP en claro" 'password=[A-Za-z0-9!@#$%^&*()_+-]{4,}'
# Formas genericas
buscar "asignacion de secreto en claro" '(api[_-]?key|secret|token|passwd)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_-]{12,}["'"'"']'

if [ "$fallos" -eq 0 ]; then
  echo "OK: no hay credenciales en claro en los archivos de texto del repo."
  echo "    (los .tar.gz de backups/ no se inspeccionan: estan en .gitignore)"
  exit 0
fi
echo
echo "$fallos patron(es) con credenciales en claro. Reemplazalos por $PLACEHOLDER."
exit 1
