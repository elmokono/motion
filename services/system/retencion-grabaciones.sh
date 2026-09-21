#!/bin/bash
# Borra las carpetas de grabaciones mas viejas que DIAS_RETENCION.
#
# Decide por el NOMBRE de la carpeta (YYYY-MM-DD), no por mtime: camaras.sh hace
# touch sobre los archivos y la fecha de modificacion no refleja cuando se grabo.
#
# Uso:
#   retencion-grabaciones.sh            -> simulacro, no borra nada
#   retencion-grabaciones.sh --aplicar  -> borra de verdad

set -u
ROOT="${ROOT:-/media/hdd2/Camara/Recordings}"
DIAS_RETENCION="${DIAS_RETENCION:-90}"
APLICAR=0
[ "${1:-}" = "--aplicar" ] && APLICAR=1

# Sin el disco montado, ROOT seria un directorio vacio de la SD: no borrar nada.
if ! mountpoint -q /media/hdd2; then
    logger -t retencion "ABORTA: /media/hdd2 no esta montado"
    echo "ABORTA: /media/hdd2 no esta montado" >&2
    exit 1
fi

corte=$(date -d "-${DIAS_RETENCION} days" +%Y-%m-%d)
total_kb=0; total_dirs=0

for d in "$ROOT"/*/; do
    nombre=$(basename "$d")
    # Solo carpetas con formato de fecha valido
    date -d "$nombre" +%Y-%m-%d >/dev/null 2>&1 || continue
    [[ "$nombre" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
    [[ "$nombre" < "$corte" ]] || continue

    kb=$(du -sk "$d" | cut -f1)
    total_kb=$((total_kb + kb)); total_dirs=$((total_dirs + 1))
    if [ "$APLICAR" -eq 1 ]; then
        rm -rf "$d" && logger -t retencion "borrada $nombre ($((kb/1024)) MB)"
    else
        echo "  [simulacro] borraria $nombre ($((kb/1024)) MB)"
    fi
done

msg="retencion ${DIAS_RETENCION}d (corte $corte): $total_dirs carpetas, $((total_kb/1024)) MB"
if [ "$APLICAR" -eq 1 ]; then
    logger -t retencion "$msg"
    echo "$msg"
else
    echo "  TOTAL simulacro: $msg"
    echo "  (ejecutar con --aplicar para borrar)"
fi
