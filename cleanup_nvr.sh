#!/bin/bash

set -e

echo "🛑 Stopping services..."
sudo systemctl stop motion || true
sudo systemctl stop minidlna || true

echo "❌ Disabling services..."
sudo systemctl disable motion || true
sudo systemctl disable minidlna || true

echo "🧹 Removing custom motion service (if exists)..."
sudo rm -f /etc/systemd/system/motion.service

echo "🔄 Reloading systemd..."
sudo systemctl daemon-reload

echo "📦 Removing packages..."
sudo apt purge -y motion minidlna
sudo apt autoremove -y

echo "🧽 Removing configs..."
sudo rm -rf /etc/motion
sudo rm -f /etc/minidlna.conf

echo "🧹 Cleaning logs..."
sudo rm -f /var/log/motion.log
sudo rm -f /var/log/camaras.log

echo "🧹 Cleaning cache..."
sudo rm -rf /var/cache/minidlna

echo "🧹 Cleaning RAM disk..."
sudo rm -rf /media/ramdisk/* || true

echo "🧹 Cleaning HDD structure (optional recordings NOT deleted)..."
sudo rm -rf /media/hdd2/.minidlna

echo "🔐 Fixing /tmp permissions..."
sudo chmod 1777 /tmp

echo "💾 Removing RAMDISK from fstab..."
sudo sed -i '\|/media/ramdisk|d' /etc/fstab

echo "🔄 Reload mounts..."
sudo systemctl daemon-reexec
sudo mount -a || true

echo "🧼 Final cleanup..."
sudo apt clean

echo "✅ NVR CLEAN RESET DONE"
