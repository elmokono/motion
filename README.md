<<<<<<< HEAD
# motion — videovigilancia en Raspberry Pi

Código de los servicios de grabación, etiquetado por IA y visualización que corren en
`raspberrypi`. Este repo es el **espejo del código que vive en el server**; el server es
la fuente de verdad operativa.

> **Todo comando de este repo se ejecuta vía `ssh daniel@raspberrypi`.** Ver
> `.clinerules/general-rules.md`.

## ⚠️ Credenciales ofuscadas: NO desplegar estos dos archivos tal cual

Las credenciales están reemplazadas por `XXXXXXXXXXXXXXX` **solo en el repo**. El server
conserva los valores reales.

| Archivo | Valor ofuscado |
|---|---|
| `services/video_tagger/tagger.py` | `API_KEY` (línea 12, y una copia comentada en la 1) |
| `services/motion/motion.conf` | password RTSP en `netcam_url` y `netcam_high_url` |

**Estos dos archivos ya no son copia byte a byte del server.** Copiarlos sin editar deja
al tagger con una key inválida y a motion sin poder conectar con la cámara. Antes de
desplegar cualquiera de los dos hay que reponer el valor real (ver más abajo).

El resto de los archivos (`app.py`, `index.html`, `camaras.sh`, units de systemd) **sí**
son copia exacta y se despliegan directo.

Para comprobar que no se coló ninguna credencial:

```bash
./scripts/check-secrets.sh
```

Queda pendiente lo de fondo: **rotar** ambas credenciales (estuvieron en claro) y moverlas
a un `EnvironmentFile=` de systemd. Ofuscar el repo evita filtraciones nuevas, no las ya
ocurridas. Los `.tar.gz` de `backups/` siguen conteniendo los valores reales y por eso
están en `.gitignore`.

## Arquitectura

```
Cámara IP RTSP (192.168.0.158)
   │   substream 800x448 → detección       mainstream 1080p → grabación
   ▼
[1] motion.service            graba en /media/ramdisk
   │   hook on_movie_end
   ▼
[2] camaras.sh                rsync al HDD → carpeta YYYY-MM-DD → H.264 25fps CFR → thumbnail .jpg
   ▼
[3] video_tagger.service      polling 5 min → Gemini → .json junto al video
   ▼
[4] motion-ui.service         Flask :5000 → /api/events → timeline web
```

Grabaciones en `/media/hdd2/Camara/Recordings/YYYY-MM-DD/`, con un `.json` y un `.jpg`
por video.

## Mapa del repo → server

| Ruta en el repo | Ruta en `raspberrypi` |
|---|---|
| `services/motion/motion.conf` | `/etc/motion/motion.conf` |
| `services/motion/camaras.sh` | `/etc/motion/camaras.sh` |
| `services/motion-ui/app.py` | `/opt/motion-ui/app.py` |
| `services/motion-ui/templates/index.html` | `/opt/motion-ui/templates/index.html` |
| `services/video_tagger/tagger.py` | `/opt/video_tagger/tagger.py` |
| `services/video_tagger/requirements.txt` | `pip freeze` de `/opt/video_tagger/venv` |
| `services/systemd/*.service`, `*.timer` | `/etc/systemd/system/` |
| `services/system/net-watchdog.sh` | `/usr/local/sbin/net-watchdog.sh` |
| `services/system/retencion-grabaciones.sh` | `/usr/local/sbin/retencion-grabaciones.sh` |
| `services/system/journald-99-persistent-storage.conf` | `/etc/systemd/journald.conf.d/99-persistent-storage.conf` |
| `services/system/fstab` | `/etc/fstab` |
| `scripts/check-secrets.sh` | — (solo repo) |

El venv (210 MB) y las grabaciones (63 GB) no se versionan.

## Servicios

### `motion` — captura
motion 4.7.0. Dual stream: substream 800x448 @12fps para el motor de detección,
mainstream HD con `movie_passthrough on` para la grabación. `threshold 600`,
`minimum_motion_frames 2`, `event_gap 60`. Escribe al ramdisk para no desgastar la SD y
dispara `camaras.sh` en `on_movie_end`.

Dos cosas que confunden al leer la config:

- **`pre_capture` y `post_capture` se cuentan en FRAMES, no en segundos**, y `framerate`
  es 12. Los 30 frames originales daban 2,5 s, no los "1 a 2 segundos a 25fps" que decía
  el comentario del archivo.
- **`movie_max_time 60` no tiene efecto** porque `movie_passthrough on` lo ignora; hay
  grabaciones de 226 s. No hay tope real de duración.

### `camaras.sh` — post-proceso
Lock con `flock`, `rsync` del ramdisk al HDD, organización en carpetas por fecha,
normalización a H.264 25fps CFR con `+faststart`, y thumbnail JPG. El bloque de
detección con Docker/YOLO está comentado.

### `video_tagger` — etiquetado con Gemini
Recorre las carpetas desde `MIN_DATE`, sube cada video sin `.json` a Gemini
(`gemini-3.5-flash-lite`) y guarda la metadata:

```json
{
  "evento_principal": "Persona",
  "descripcion": "...",
  "hay_personas": true,
  "hay_animales": false,
  "movimiento_vegetacion": false,
  "vision_nocturna": true
}
```

`vision_nocturna` lo determina el modelo por la imagen (escala de grises del modo IR o
escena claramente nocturna), no por la hora del archivo. Validado el 2026-09-17 contra un
video de las 23:20 (`true`) y uno de las 11:37 (`false`).

**Sospechoso** = `vision_nocturna && hay_personas`. La regla se evalúa en el frontend y
**no se persiste** en el JSON, para poder ajustarla sin re-etiquetar. Los videos
etiquetados antes del 2026-09-17 no traen `vision_nocturna`, así que nunca dan sospechoso.

Respeta los límites del nivel gratuito: pausa de 30 s entre videos (RPM) y, ante un 429
por cuota diaria, duerme hasta las 04:05 AM (reset de medianoche del Pacífico).

### `motion-ui` — visualización
Flask sirviendo una timeline (`vis-timeline`) con los eventos, reproductor de video y
filtros por 👤 personas, 🐾 animales, 🌿 vegetación y otros.

Cada tarjeta del historial antepone ☀️ o 🌙 al título según la hora del evento (día
08:00–19:59). Es la hora del archivo, señal distinta de `vision_nocturna`, que es lo que
ve la cámara por IR: pueden discrepar al atardecer, y esa discrepancia es informativa.

Filtro y badge **🚨 Sospechoso** para personas detectadas en modo nocturno. Un evento
sospechoso deja de contar como "Personas" a efectos del filtro, para que destildando
Personas queden solo las alertas.

Se **autorefresca cada 60 s** sin recargar la página: conserva filtros, el video en
reproducción con su posición, y el zoom de la timeline. El indicador `⟳` en la barra de
filtros muestra la hora del último refresco y resalta en turquesa cuando entraron eventos
nuevos.

> Al reidentificar el evento en curso se usa `video_url`, **nunca `id`**: el backend
> numera los eventos por orden de `os.walk`, así que al aparecer un solo video nuevo
> cambian de id ~1.400 eventos (medido). Usar el id haría saltar el reproductor.

**En móvil vertical** (`max-width: 900px` + `orientation: portrait`) el panel de
historial se apila debajo del reproductor, que pasa a ocupar el ancho completo en una
caja 16:9. El layout de escritorio/TV no se toca. Requiere la etiqueta `viewport`, que
faltaba: sin ella el teléfono renderiza a ~980px y ninguna media query llega a aplicar.

### `minidlna` — DLNA para la TV
Indexa `/media/hdd2/Camara/Recordings` con `media_dir=V,...` (solo video). No lista los
`.jpg` como items, pero **sí los usa como carátula** de cada video por la convención de
sidecar `<nombre>.jpg`; guarda su propia copia reescalada a 160×90 en
`/media/hdd2/.minidlna/art_cache`. Por eso `camaras.sh` debe seguir generando la
miniatura, aunque la UI web no la use.

## Acceso: libre en la LAN, Basic Auth desde afuera

`app.py` decide por la IP de origen en un `before_request`, así que cubre todas las rutas
(incluida `/video/`) y las que se agreguen después.

```
/etc/motion-ui.env        0600 root:root      (no versionado)
  WEB_USER=...
  WEB_PASSWORD=...
  LAN_NETWORKS=192.168.0.0/24,127.0.0.0/8,::1/128
```

La unidad lo carga con `EnvironmentFile=-/etc/motion-ui.env`. El `-` hace que el servicio
arranque aunque falte el archivo, pero entonces **todo acceso externo recibe 503**: falla
cerrado, nunca abierto.

> **No usar `X-Forwarded-For` en esta lógica.** Con port forwarding no hay proxy reverso,
> así que cualquiera desde internet podría mandar `X-Forwarded-For: 192.168.0.5` y saltarse
> la autenticación. Se usa solo `request.remote_addr`. Si algún día se pone un proxy
> adelante, esta lógica hay que rehacerla.

Comportamiento verificado (2026-09-18):

| Origen | Credenciales | Resultado |
|---|---|---|
| LAN (`192.168.0.x`, `127.0.0.1`) | — | 200 |
| WAN | ninguna | 401 + `WWW-Authenticate` |
| WAN | correctas | 200 |
| WAN | password incorrecto | 401 |
| WAN | `X-Forwarded-For`/`X-Real-IP`/`Forwarded` falsificados | 401 |
| WAN | server sin `WEB_PASSWORD` | 503 |

### ⚠️ Antes de abrir el puerto en el router

- **Reenviar únicamente el 5000.** Los puertos **8080** (webcontrol de motion) y **8081**
  (stream en vivo) escuchan en `0.0.0.0` **sin autenticación**: el 8080 permite
  reconfigurar motion entero. Exponerlos sería entregar el sistema.
- **Basic Auth sobre HTTP manda la credencial en base64 en cada request**, legible por
  cualquiera en el camino, igual que el video. Para exposición real conviene TLS (un
  proxy reverso tipo Caddy con Let's Encrypt) o, mejor, evitar el port forwarding y usar
  una VPN (WireGuard/Tailscale), que deja todo fuera de internet.
- Flask corre con el servidor de desarrollo de Werkzeug y como `root`; ninguna de las dos
  cosas es apropiada de cara a internet.

## Recuperación tras corte de luz

Cuando vuelve la luz el router tarda más en arrancar que el Pi, el WiFi no se reasocia y
el sistema queda sin red indefinidamente. Motion no falla: reintenta cada 10 s para
siempre, pero contra una red que no existe. Pasó dos veces, y las dos se resolvieron solo
con un reinicio manual:

```
Sep 06 11:23 → Sep 08 10:36    ~47 h sin grabar   16.985 reintentos
Sep 19 11:43 → Sep 20 13:17    ~25 h sin grabar    9.217 reintentos
```

La firma en `/var/log/motion/motion.log` es `Network is unreachable` — sin ruta, no es que
la cámara no responda.

Tres medidas (2026-09-21):

| Medida | Detalle |
|---|---|
| **Power save del WiFi apagado** | `802-11-wireless.powersave=2` en el perfil `CASA-ALT`. Causa conocida de caídas con `brcmfmac` en Pi. |
| **Journal persistente** | `/etc/systemd/journald.conf.d/99-persistent-storage.conf`, con tope de 100 MB. Antes los logs de arranque se perdían y no se podía diagnosticar. |
| **`net-watchdog.timer`** | Cada minuto pinga el gateway. A los 3 fallos reasocia `wlan0`; a los 10 reinicia el equipo. |

> RPi OS trae `/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf` con
> `Storage=volatile` para no desgastar la SD. Un drop-in en `/etc/` con número más alto lo
> pisa; editar `journald.conf` directamente **no** alcanza. Además hay que crear
> `/var/log/journal/<machine-id>` a mano.

El watchdog no reinicia durante los primeros 15 minutos de uptime, para no entrar en bucle
si el router sigue apagado. Para ver su actividad:

```bash
ssh daniel@raspberrypi 'journalctl -t net-watchdog --since today'
```

## Retención de grabaciones

`retencion-grabaciones.timer` corre todos los días a las 04:30 y borra las carpetas
anteriores a **180 días** (`DIAS_RETENCION` en la unidad, no en el script).

```bash
# Simulacro, no borra nada:
ssh daniel@raspberrypi 'sudo /usr/local/sbin/retencion-grabaciones.sh'
# Con otra retención, solo para ver el efecto:
ssh daniel@raspberrypi 'sudo DIAS_RETENCION=90 /usr/local/sbin/retencion-grabaciones.sh'
```

Dos salvaguardas: decide por el **nombre** de la carpeta (`YYYY-MM-DD`) y no por `mtime`,
porque `camaras.sh` hace `touch` y la fecha de modificación no refleja cuándo se grabó; y
**aborta si `/media/hdd2` no está montado**, para no borrar del directorio vacío de la SD.

Se eligió 180 y no 90 días porque a 90 se llevaba las grabaciones de febrero y marzo
recuperadas de la tarjeta SD, de las que no hay otra copia. A 180 igual caen las tres
carpetas más viejas de ese lote (2026-02-25, 03-23 y 03-24: 89 videos, 75 MB).

> **La retención libera poco espacio.** Las grabaciones viejas son livianas (previas al
> cambio a HD): junio entero son 1,6 GB contra los 58,6 GB de septiembre. A 90 días
> liberaba 3,5 GB. Lo que de verdad ocupa es el bitrate inflado de agosto y la primera
> mitad de septiembre.

### Bitrate inflado: 48 GB recuperables, sin aplicar

Los 2.381 videos anteriores al 2026-09-16 se encodearon con `ultrafast crf23 -r 25` y
ocupan 62,2 GB. Re-encodearlos con los ajustes actuales los dejaría en ~14,1 GB
(**medido: factor 4,4×**, 19 MB → 4 MB en una muestra), pero cuesta ~21 h de CPU y agrega
una segunda generación de pérdida sobre video que ya venía re-encodeado. **Decisión del
2026-09-21: no hacerlo**, se dejan como están.

| Fecha | Videos | MB/video | GB/día |
|---|---|---|---|
| 1-15 sep (encoder viejo) | 2.097 | 27,3 | 4,30 |
| 17-21 sep (encoder nuevo) | 201 | **10,3** | **0,41** |

## Operación

```bash
ssh daniel@raspberrypi 'systemctl status motion motion-ui video_tagger'
ssh daniel@raspberrypi 'sudo journalctl -u video_tagger -f'
ssh daniel@raspberrypi 'sudo systemctl restart motion-ui'
```

UI en `http://raspberrypi:5000`. Stream en vivo de motion en `:8081`, webcontrol en `:8080`.

## Desplegar cambios de este repo al server

> ⚠️ `tagger.py` y `motion.conf` llevan la credencial ofuscada. Para desplegarlos hay que
> reponer el valor real **en el archivo que se copia**, nunca en el del repo. Por ejemplo,
> tomando el valor que ya está en el server:
>
> ```bash
> KEY=$(ssh daniel@raspberrypi "sudo grep -oP '(?<=^API_KEY = \")[^\"]+' /opt/video_tagger/tagger.py")
> sed "s/XXXXXXXXXXXXXXX/$KEY/" services/video_tagger/tagger.py > /tmp/tagger.py
> scp /tmp/tagger.py daniel@raspberrypi:/tmp/ && rm /tmp/tagger.py
> ssh daniel@raspberrypi 'sudo cp /tmp/tagger.py /opt/video_tagger/ && sudo systemctl restart video_tagger'
> ```

```bash
# Los de abajo son copia exacta del server y se despliegan directo.

scp services/motion-ui/app.py             daniel@raspberrypi:/tmp/ && \
  ssh daniel@raspberrypi 'sudo cp /tmp/app.py /opt/motion-ui/ && sudo systemctl restart motion-ui'

scp services/motion-ui/templates/index.html daniel@raspberrypi:/tmp/ && \
  ssh daniel@raspberrypi 'sudo cp /tmp/index.html /opt/motion-ui/templates/ && sudo systemctl restart motion-ui'
```

> **El `restart` tras tocar `index.html` no es opcional.** Flask cachea las plantillas
> Jinja compiladas y `app.run()` no corre en modo debug, así que sin reiniciar se sigue
> sirviendo la versión anterior aunque el archivo en disco ya esté actualizado.

## Cambios de performance — 2026-09-16

Backup previo de todo lo tocado en `backups/pre-perf-fix-20260916/`.

| Cambio | Resultado medido |
|---|---|
| `camaras.sh`: re-encode sin `-r 25`, `veryfast`, `crf 26` | archivos **4,5× más chicos** (44,3 → 9,8 MB); perfil H.264 Main correcto |
| `camaras.sh`: `flock -w 300` en vez de `-n`, con log de espera | dejó de descartar grabaciones; 13 huérfanos recuperados |
| `app.py`: caché por firma del árbol + metadata por mtime | `/api/events` **1,07 s → 0,05 s** en caliente |
| `app.py`: gzip y filtros `?desde`/`?hasta`/`?limit` | payload **1 MB → 134 KB** |
| ramdisk 200 MB → 500 MB (`/etc/fstab`) | margen ante ráfagas de eventos |
| HDD: driver `ntfs-3g` (FUSE) → `ntfs3` (kernel) | lectura de metadata **5,2× más rápida** (0,35 → 0,067 ms/archivo), a la par de ext4 |
| `camaras.sh`: thumbnail con `scale=640:-2 -q:v 5` | 497 KB → 70 KB por miniatura (7×) |
| Borrados los 2.089 thumbnails full-res ya existentes | **655 MB liberados** (731 → 76 MB) |
| `motion.conf`: `event_gap` 5 → 60 s, `post_capture` 30 → 60 | corta el 42% de grabaciones que eran fragmentos de una acción |

Sobre `event_gap 60`: motion mantiene el evento abierto 60 s, pero **no graba mientras no
hay movimiento**, así que no agrega metraje muerto (medido: evento de 68 s de reloj → video
de 13,2 s, 171 frames). La contrapartida es que la duración del video ya no equivale al
tiempo transcurrido: las pausas quedan recortadas y se ve un salto.

El re-encode **no** quedó más rápido (≈15 s en ambos casos): `ultrafast` procesaba el
doble de frames con un algoritmo más barato y se compensaba. La ganancia es de tamaño.

Validado con un reboot completo el 2026-09-16: `/media/hdd2` monta solo como `ntfs3`,
el ramdisk levanta en 500 MB y los 4 servicios arrancan habilitados. Pipeline de punta a
punta confirmado (evento 11:31:47 → `camaras.sh` 9 s → H.264 Main 13 fps 3,5 Mbps).

> Al desmontar `/media/hdd2` hay que parar también **`minidlna`**, que lo mantiene
> abierto. Si `ssh raspberrypi` falla por resolución de nombre, existe `raspberrypi.local`
> (mDNS), pero su host key se guarda aparte.

## Pendientes conocidos

- **NTFS + `ntfs3` es frágil ante apagados no limpios.** El driver del kernel se niega a
  montar un volumen marcado dirty (a diferencia de `ntfs-3g`, que lo montaba igual), así
  que un corte de luz deja el disco sin montar en el arranque. Mitigado con
  `ntfsfix-hdd2.service` y la guarda de `mountpoint` en `camaras.sh`, pero la solución de
  fondo es **formatear a ext4**, idealmente al cambiar de disco.
- Rotar API key de Gemini y credenciales RTSP; moverlas a `EnvironmentFile=`.
- `webcontrol_localhost off` y `stream_localhost off` exponen control y video a toda la
  LAN sin autenticación.
- `motion-ui` y `video_tagger` corren como `root` sin necesitarlo; Flask usa el servidor
  de desarrollo.
- `camaras.log` (41 MB) sin logrotate.
- Los 2.089 videos anteriores al 2026-09-16 ya no tienen sidecar `.jpg`. minidlna los
  sigue mostrando desde su `art_cache`, pero perderían la carátula si alguna vez
  reconstruye la base desde cero (`minidlnad -R`). Listado de lo borrado en
  `backups/pre-perf-fix-20260916/thumbnails-borrados-20260916.tsv`.
- `app.py` asume 2 minutos de duración por evento, pero `movie_max_time` es 60 s.
- `camaras.sh` escribe `creation_time` con la hora de procesamiento, no la del evento, y
  el `touch` final pisa la mtime.
=======
# MOTION MINIPC

## Steps
- Create and mount HDD (for storing movies)
- (optional) Create and mount Ramdisk. Movies are written on ramdisk and when movie_end event is trigger a thumbnail is created and this file and the thumbnail are moved to HDD
- Install and configure motion (see conf.d)
- Install and configure ffmpeg (for thumbnails)
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
>>>>>>> origin/main
