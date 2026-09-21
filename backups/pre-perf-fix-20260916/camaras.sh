#!/bin/bash

set -e
set -o pipefail

FILE="$1"
ROOT="/media/hdd2/Camara/Recordings"
LOG="/media/hdd2/camaras.log"
LOCK="/tmp/camaras.lock"

exec 200>$LOCK
flock -n 200 || exit 1

[ -f "$FILE" ] || exit 1

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

if /usr/bin/ffmpeg -y -i "$FINAL_PATH" \
  -metadata creation_time="$CREATION_TIME" \
  -c:v libx264 -preset ultrafast -crf 23 \
  -profile:v main -level:v 4.0 \
  -r 25 -pix_fmt yuv420p \
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
JPG="${FINAL_PATH%.*}.jpg"
if [ ! -f "$JPG" ] && [ -s "$FINAL_PATH" ]; then
    timeout 10s /usr/bin/ffmpeg -y -i "$FINAL_PATH" -frames:v 1 -update 1 "$JPG" >> "$LOG" 2>&1 || true
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
