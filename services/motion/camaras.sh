#!/bin/bash

set -e
set -o pipefail

FILE="$1"
ROOT="/media/hdd2/Camara/Recordings"
LOG="/media/hdd2/camaras.log"
LOCK="/tmp/camaras.lock"

[ -f "$FILE" ] || exit 1

# Si el HDD no esta montado, /media/hdd2 es un directorio vacio de la tarjeta SD.
# Escribir ahi llena la SD en silencio y ademas deja las grabaciones fuera del
# arbol real. Paso el 2026-09-16: un reinicio no limpio dejo el NTFS marcado dirty,
# ntfs3 se nego a montarlo y una grabacion termino en la SD.
# Abortamos dejando el video en el ramdisk, que se procesa cuando el mount vuelva.
# El aviso va a journald, no a $LOG, porque $LOG vive en el disco ausente.
if ! mountpoint -q /media/hdd2; then
  logger -t camaras "ABORTA: /media/hdd2 no esta montado; dejo $FILE en el ramdisk"
  exit 1
fi

# Cola en vez de descarte: esperamos hasta 300s a que se libere el lock.
# Con -n (no bloqueante) cualquier evento que cerraba durante un re-encode
# se perdia en silencio, y el descarte ni siquiera quedaba logueado porque
# el exit ocurria antes del echo START.
exec 200>$LOCK
LOCK_T0=$(date +%s)
if ! flock -w 300 200; then
  echo "$(date) LOCK_TIMEOUT $FILE (espero 300s, sigue ocupado)" >> "$LOG"
  exit 1
fi
LOCK_WAIT=$(( $(date +%s) - LOCK_T0 ))
[ "$LOCK_WAIT" -gt 0 ] && echo "$(date) LOCK_WAIT ${LOCK_WAIT}s $FILE" >> "$LOG"

echo "$(date) START $FILE" >> "$LOG"

mkdir -p "$ROOT"

BASENAME=$(basename "$FILE")
TARGET="$ROOT/$BASENAME"

# Copia segura desde el ramdisk hacia el HDD
rsync --partial "$FILE" "$TARGET" >> "$LOG" 2>&1
sync
rm -f "$FILE"

DATE=$(echo "$BASENAME" | grep -oE "[0-9]{8}" | head -n1)
[ -z "$DATE" ] && exit 1

DIR="${DATE:0:4}-${DATE:4:2}-${DATE:6:2}"
FINAL_DIR="$ROOT/$DIR"

mkdir -p "$FINAL_DIR"
FINAL_PATH="$FINAL_DIR/$BASENAME"

mv "$TARGET" "$FINAL_PATH" || exit 1

# --- NORMALIZACIÓN SEGURA DE VIDEO (25 FPS CFR) ---
# --- NORMALIZACIÓN SEGURA DE VIDEO CON METADATOS DE FECHA ---
CONVERTED="${FINAL_PATH%.mp4}_fix.mp4"

# Capturar fecha y hora actual en formato UTC ISO 8601 (ej. 2026-08-20T20:18:00Z)
CREATION_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# El re-encode es necesario: motion entrega HEVC y los navegadores no lo
# reproducen de forma confiable. Lo que cambio es COMO se re-encodea:
#   -r 25      ELIMINADO. La fuente es 12 fps; forzar 25 duplicaba cada frame
#              (doble de trabajo y doble de tamano, cero informacion extra).
#   ultrafast -> veryfast. ultrafast es el peor preset en compresion y era el
#              responsable de inflar el bitrate de 1.3 Mbps a 16.3 Mbps (12x).
#              Ademas desactiva CABAC/B-frames, por lo que el -profile:v main
#              de abajo nunca se aplicaba (la salida quedaba Constrained Baseline).
#   crf 23 -> 26. Suficiente para CCTV y recorta bastante el tamano.
if /usr/bin/ffmpeg -y -i "$FINAL_PATH" \
  -metadata creation_time="$CREATION_TIME" \
  -c:v libx264 -preset veryfast -crf 26 \
  -profile:v main -level:v 4.0 \
  -pix_fmt yuv420p \
  -movflags +faststart \
  "$CONVERTED" >> "$LOG" 2>&1; then
  
  # Verificar que el video convertido no esté vacío
  if [ -s "$CONVERTED" ]; then
    mv "$CONVERTED" "$FINAL_PATH"
    # Asegurar que la fecha de modificación del archivo físico coincida con el momento actual
    touch "$FINAL_PATH"
  else
    echo "$(date) WARNING: Video convertido vacío. Conservando original." >> "$LOG"
    rm -f "$CONVERTED"
  fi
else
  echo "$(date) WARNING: Falló conversión de ffmpeg. Conservando original." >> "$LOG"
  rm -f "$CONVERTED"
fi

# --- GENERACIÓN DE MINIATURA (THUMBNAIL) ---
# minidlna consume esta miniatura como caratula del video, por la convencion de
# sidecar <nombre>.jpg junto a <nombre>.mp4 (no la indexa como item propio: el
# media_dir usa el prefijo "V," que restringe a video). Para servirla la
# reescala a 160x90, asi que generarla a 2560x1440 eran ~40x mas pixeles de los
# necesarios: ~497 KB por archivo en vez de ~25 KB.
JPG="${FINAL_PATH%.*}.jpg"
if [ ! -f "$JPG" ] && [ -s "$FINAL_PATH" ]; then
    timeout 10s /usr/bin/ffmpeg -y -i "$FINAL_PATH" -frames:v 1 -update 1 \
      -vf scale=640:-2 -q:v 5 "$JPG" >> "$LOG" 2>&1 || true
fi

# Desactivar fallo estricto para asegurar ejecución de Docker
set +e

# --- DETECCIÓN DE IA CON DOCKER ---
if [ -s "$FINAL_PATH" ]; then
  :  # no-op: bloque docker deshabilitado (evita if vacio)
#  docker run --rm -d \
#    -v "$FINAL_PATH":"$FINAL_PATH":ro \
#    -v /media/hdd2/Detection:/media/hdd2/Detection \
#    -v /home/daniel/detection/detect_targets.py:/app/detect.py \
#    -v /home/daniel/detection/haarcascade_frontalface_default.xml:/app/haarcascade_frontalface_default.xml:ro \
#    ultralytics/ultralytics:latest-arm64 python3 /app/detect.py "$FINAL_PATH" >> "$LOG" 2>&1
fi

echo "$(date) DONE $FINAL_PATH" >> "$LOG"
