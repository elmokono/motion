#!/bin/bash

set -e

echo "🔧 Updating system..."
sudo apt update

echo "📦 Installing packages..."
sudo apt install -y motion ffmpeg minidlna ntfs-3g

# =========================
# 📁 DIRECTORIES
# =========================
sudo mkdir -p /media/ramdisk
sudo mkdir -p /media/hdd2/Camara/Recordings
sudo mkdir -p /media/hdd2/.minidlna

# =========================
# 💾 RAMDISK
# =========================
if ! grep -q "/media/ramdisk" /etc/fstab; then
    echo "tmpfs /media/ramdisk tmpfs size=200M,noatime 0 0" | sudo tee -a /etc/fstab
fi

mountpoint -q /media/ramdisk || sudo mount /media/ramdisk

# =========================
# 💽 HDD
# =========================
mountpoint -q /media/hdd2 || echo "⚠️ HDD no montado (verificar fstab)"

# =========================
# 🔐 PERMISSIONS
# =========================
sudo chown -R motion:motion /media/ramdisk || true
sudo chown -R motion:motion /media/hdd2 || true
sudo chown -R minidlna:minidlna /media/hdd2/.minidlna || true

sudo chmod -R 775 /media/hdd2 || true

# =========================
# 🎬 CAMARAS.SH (FIX LOCK)
# =========================
TMP_SCRIPT=$(mktemp)

cat <<'EOF' > $TMP_SCRIPT
#!/bin/bash

FILE="$1"
ROOT="/media/hdd2/Camara/Recordings"

LOG="/var/log/camaras.log"
LOCK="/tmp/camaras.lock"

# limpiar lock zombie si existe
rm -f "$LOCK"

exec 200>$LOCK
flock -n 200 || exit 1

[ -f "$FILE" ] || exit 1

echo "$(date) START $FILE" >> $LOG

BASENAME=$(basename "$FILE")
TARGET="$ROOT/$BASENAME"

mv "$FILE" "$TARGET" || exit 1

DATE=$(echo "$BASENAME" | grep -oE "[0-9]{8}" | head -n1)
[ -z "$DATE" ] && exit 1

DIR="${DATE:0:4}-${DATE:4:2}-${DATE:6:2}"
FINAL_DIR="$ROOT/$DIR"

mkdir -p "$FINAL_DIR"

FINAL_PATH="$FINAL_DIR/$BASENAME"

mv "$TARGET" "$FINAL_PATH" || exit 1

sleep 1

JPG="${FINAL_PATH%.*}.jpg"

if [ ! -f "$JPG" ]; then
    timeout 10s /usr/bin/ffmpeg -y -i "$FINAL_PATH" -frames:v 1 "$JPG" >> $LOG 2>&1
fi

echo "$(date) DONE $FINAL_PATH" >> $LOG
EOF

if [ ! -f /etc/motion/camaras.sh ] || ! cmp -s $TMP_SCRIPT /etc/motion/camaras.sh; then
    sudo mv $TMP_SCRIPT /etc/motion/camaras.sh
    sudo chmod +x /etc/motion/camaras.sh
    sudo chown motion:motion /etc/motion/camaras.sh
else
    rm $TMP_SCRIPT
fi

# =========================
# ⚙️ MOTION CONFIG
# =========================
TMP_CONF=$(mktemp)

cat <<EOF > $TMP_CONF
daemon off

log_file /var/log/motion/motion.log
log_level 6

target_dir /media/ramdisk

netcam_url rtsp://192.168.0.222/live/0/sub

width 800
height 448
framerate 0

threshold 1500
minimum_motion_frames 2
event_gap 10
pre_capture 5
post_capture 60

movie_output on
movie_max_time 60
movie_codec mp4
movie_quality 0
movie_passthrough on

netcam_keepalive on
netcam_tolerant_check on

on_movie_end /etc/motion/camaras.sh %f

stream_port 8081
stream_localhost off

webcontrol_port 8080
webcontrol_localhost off
EOF

if [ ! -f /etc/motion/motion.conf ] || ! cmp -s $TMP_CONF /etc/motion/motion.conf; then
    sudo mv $TMP_CONF /etc/motion/motion.conf
    sudo chown root:motion /etc/motion/motion.conf
    sudo chmod 644 /etc/motion/motion.conf
else
    rm $TMP_CONF
fi

# =========================
# ⚙️ SYSTEMD FIX
# =========================
SERVICE_FILE="/etc/systemd/system/motion.service"

sudo bash -c "cat > $SERVICE_FILE <<EOF
[Unit]
Description=Motion detection video capture daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/motion -c /etc/motion/motion.conf
Restart=always
RestartSec=5
User=motion
Group=motion

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reexec
sudo systemctl daemon-reload

# =========================
# 📺 MINIDLNA
# =========================
CONF="/etc/minidlna.conf"

grep -q "media_dir=V,/media/hdd2/Camara/Recordings" $CONF || \
    echo "media_dir=V,/media/hdd2/Camara/Recordings" | sudo tee -a $CONF

grep -q "friendly_name=CamServer" $CONF || \
    echo "friendly_name=CamServer" | sudo tee -a $CONF

grep -q "db_dir=/media/hdd2/.minidlna" $CONF || \
    echo "db_dir=/media/hdd2/.minidlna" | sudo tee -a $CONF

grep -q "log_dir=/media/hdd2/.minidlna" $CONF || \
    echo "log_dir=/media/hdd2/.minidlna" | sudo tee -a $CONF

grep -q "inotify=yes" $CONF || \
    echo "inotify=yes" | sudo tee -a $CONF

# =========================
# 🧹 LOGS
# =========================
sudo sed -i 's/^#Storage=.*/Storage=volatile/' /etc/systemd/journald.conf || true
sudo systemctl restart systemd-journald

# =========================
# 🚀 SERVICES
# =========================
sudo systemctl enable motion
sudo systemctl enable minidlna

sudo systemctl restart motion
sudo systemctl restart minidlna

echo "✅ DONE - Stable NVR with lock fix"
