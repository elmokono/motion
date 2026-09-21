import gzip
import hmac
import ipaddress
import os
import re
import json
import threading
from datetime import datetime, timedelta
from flask import Flask, jsonify, render_template, request, send_from_directory, Response

app = Flask(__name__)
MOTION_DIR = os.getenv("MOTION_DIR", "/media/hdd2/Camara/Recordings")

# --- ACCESO: libre desde la LAN, Basic Auth desde afuera -----------------------
# El router hace port forwarding (DNAT), que preserva la IP de origen, asi que
# request.remote_addr alcanza para distinguir LAN de WAN.
#
# NUNCA usar X-Forwarded-For aca: al no haber proxy reverso, cualquiera desde
# internet puede mandar "X-Forwarded-For: 192.168.0.5" y saltarse la auth.
# Si algun dia se pone un proxy adelante, ESTA logica hay que rehacerla.
LAN_NETWORKS = [
    ipaddress.ip_network(n.strip())
    for n in os.getenv("LAN_NETWORKS", "192.168.0.0/24,127.0.0.0/8,::1/128").split(",")
    if n.strip()
]
WEB_USER = os.getenv("WEB_USER", "")
WEB_PASSWORD = os.getenv("WEB_PASSWORD", "")

# El router de arriba (Movistar) hace SNAT sobre el trafico que reenvia: TODO
# visitante de internet llega con SU IP como origen, no con la propia. Verificado
# el 2026-09-18: accesos desde datos moviles aparecen como 192.168.1.1.
# Por eso estas IPs nunca pueden contar como LAN, pase lo que pase con
# LAN_NETWORKS. Sin esta lista, ampliar LAN_NETWORKS a 192.168.0.0/16 por error
# abriria el sitio a internet entero sin credenciales.
NUNCA_LAN = [
    ipaddress.ip_network(n.strip())
    for n in os.getenv("UPSTREAM_NAT_IPS", "192.168.1.1/32").split(",")
    if n.strip()
]


def _es_lan(ip_str):
    if not ip_str:
        return False
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        return False
    if any(ip in red for red in NUNCA_LAN):
        return False
    return any(ip in red for red in LAN_NETWORKS)


def _credencial_valida(auth):
    if not auth or auth.username is None or auth.password is None:
        return False
    # compare_digest evita filtrar la credencial por diferencias de tiempo.
    return (hmac.compare_digest(auth.username, WEB_USER)
            and hmac.compare_digest(auth.password, WEB_PASSWORD))


def _pedir_auth(mensaje="Acceso restringido"):
    return Response(mensaje, 401,
                    {"WWW-Authenticate": 'Basic realm="Motion UI", charset="UTF-8"'})


@app.before_request
def control_de_acceso():
    """Se aplica a TODAS las rutas, incluidas las que se agreguen despues."""
    if _es_lan(request.remote_addr):
        return None
    # Falla cerrado: sin credenciales configuradas, desde afuera no entra nadie.
    if not WEB_USER or not WEB_PASSWORD:
        app.logger.warning("Acceso externo de %s rechazado: WEB_USER/WEB_PASSWORD sin configurar",
                           request.remote_addr)
        return Response("Acceso externo no habilitado.", 503)
    if _credencial_valida(request.authorization):
        return None
    app.logger.warning("Auth fallida desde %s para %s", request.remote_addr, request.path)
    return _pedir_auth()

PATTERN = re.compile(r'(\d+)-(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\.(mp4|avi|mkv)$')

# --- CACHE -------------------------------------------------------------------
# El costo de /api/events no esta en el os.walk (0.08s sobre 8700 archivos) sino
# en abrir y parsear un .json por video: 0.35 ms cada uno sobre NTFS-FUSE. Con
# 620 etiquetados eran 0.72s; con los 4047 proyectaba 4.7s, y ~58s a un ano.
#
# Dos niveles:
#   _meta_cache     {json_path: (mtime, metadata)} - evita releer JSON que no
#                   cambiaron. Un escaneo incremental solo lee los nuevos.
#   _events_cache   lista de eventos ya armada, invalidada por la firma del
#                   arbol de directorios (mtime+size de BASE_DIR y subdirs).
_lock = threading.Lock()
_meta_cache = {}
_events_cache = None
_events_sig = None


def _tree_signature():
    """Firma barata del arbol: ~90 stat() en vez de releer 4000 archivos."""
    try:
        sig = [os.stat(MOTION_DIR).st_mtime_ns]
    except OSError:
        return None
    with os.scandir(MOTION_DIR) as it:
        for entry in it:
            if entry.is_dir():
                try:
                    sig.append((entry.name, entry.stat().st_mtime_ns))
                except OSError:
                    pass
    return tuple(sig)


def _load_metadata(json_path):
    """Lee el .json del tagger, reusando la cache si el mtime no cambio."""
    try:
        mtime = os.stat(json_path).st_mtime_ns
    except OSError:
        return {}
    cached = _meta_cache.get(json_path)
    if cached is not None and cached[0] == mtime:
        return cached[1]
    try:
        with open(json_path, 'r', encoding='utf-8') as jf:
            metadata = json.load(jf)
    except Exception:
        metadata = {}
    _meta_cache[json_path] = (mtime, metadata)
    return metadata


def _scan_events():
    events = []
    id_counter = 1
    if os.path.exists(MOTION_DIR):
        for root, dirs, files in os.walk(MOTION_DIR):
            for file in files:
                match = PATTERN.match(file)
                if not match:
                    continue
                cam_id, y, m, d, H, M, S, ext = match.groups()
                start_dt = datetime(int(y), int(m), int(d), int(H), int(M), int(S))
                end_dt = start_dt + timedelta(minutes=2)
                rel_path = os.path.relpath(os.path.join(root, file), MOTION_DIR)
                json_path = os.path.join(root, file.rsplit('.', 1)[0] + '.json')
                events.append({
                    "id": id_counter,
                    "cam_id": cam_id,
                    "year": int(y),
                    "month": int(m),
                    "day": int(d),
                    "hour": int(H),
                    "minute": int(M),
                    "second": int(S),
                    "start": start_dt.isoformat(),
                    "end": end_dt.isoformat(),
                    "video_url": f"/video/{rel_path}",
                    "metadata": _load_metadata(json_path),
                })
                id_counter += 1
    # Purga de la cache de metadata: saca entradas de videos que ya no existen.
    vivos = {e["video_url"] for e in events}
    if len(_meta_cache) > len(vivos) * 2:
        for k in [k for k in _meta_cache if not os.path.exists(k)]:
            del _meta_cache[k]
    return events


def _get_events():
    """Devuelve la lista cacheada, reconstruyendola solo si el arbol cambio."""
    global _events_cache, _events_sig
    sig = _tree_signature()
    with _lock:
        if _events_cache is not None and sig == _events_sig and sig is not None:
            return _events_cache
        events = _scan_events()
        _events_cache = events
        _events_sig = sig
        return events


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/api/events')
def get_events():
    events = _get_events()

    # Filtros opcionales. Sin parametros devuelve todo, igual que antes, para
    # no romper el frontend actual.
    desde = request.args.get('desde')   # YYYY-MM-DD inclusive
    hasta = request.args.get('hasta')   # YYYY-MM-DD inclusive
    if desde:
        events = [e for e in events if e["start"][:10] >= desde]
    if hasta:
        events = [e for e in events if e["start"][:10] <= hasta]

    limit = request.args.get('limit', type=int)
    if limit and limit > 0:
        events = sorted(events, key=lambda e: e["start"], reverse=True)[:limit]

    # El payload son ~1 MB para 4000 eventos; comprimido baja a una fraccion.
    if 'gzip' in request.headers.get('Accept-Encoding', ''):
        body = gzip.compress(json.dumps(events).encode('utf-8'), compresslevel=6)
        resp = Response(body, mimetype='application/json')
        resp.headers['Content-Encoding'] = 'gzip'
        resp.headers['Vary'] = 'Accept-Encoding'
        return resp
    return jsonify(events)


@app.route('/video/<path:filename>')
def serve_video(filename):
    return send_from_directory(MOTION_DIR, filename)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, threaded=True)
