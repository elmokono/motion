# MOTION MINIPC

## Steps
- Create and mount HDD (for storing movies)
- (optional) Create and mount Ramdisk. Movies are written on ramdisk and when movie_end event is trigger a thumbnail is created and this file and the thumbnail are moved to HDD
- Install and configure motion (see conf.d)
- Install and configure ffmpeg (for thumbnails)
- (optional) Install miniDlna for accessing your videos

## Useful commands
- sudo systemctl start motion
- sudo systemctl stop motion
- sudo nano /etc/motion/motion.conf
- cat /var/log/motion/motion.log

## Paths
- /etc/motion/motion.conf
- /etc/motion/camaras.sh
- /media/ramdisk/
- /media/hdd2/Camara/Recordings/
- /var/log/motion/motion.log

## Trigger Events
- http://192.168.0.195:8080/0/action/eventstart
- http://192.168.0.195:8080/0/action/eventend

## References / Docs
- https://motion-project.github.io/motion_config.html
- https://www.linuxbabe.com/command-line/create-ramdisk-linux
- https://goughlui.com/2020/10/03/review-escam-pvr008-full-hd-h-265-pan-tilt-wireless-ip-camera/
