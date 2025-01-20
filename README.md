# MOTION MINIPC

## Steps
- Create and mount HDD
- (optional) Create and mount Ramdisk. Movies are written on ramdisk and when movie_end event is trigger a thumbnail is created and this file and the thumbnail are moved to HDD
- Install and configure motion (see conf.d)
- Install and configure ffmpeg
- (optional) Install miniDlna for accessing your videos

## Permissions
- -rwxrwxr-x   1 motion motion  1050 Jan 20 15:19 camaras.sh*
- drwxr-xr-x   3 root root 4096 Jan 18 15:25 hdd2/
- drwxrwxrwt   2 root root   40 Jan 20 19:43 ramdisk/

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
