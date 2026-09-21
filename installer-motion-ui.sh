#!/bin/bash

echo "=== Configurando Motion UI para Raspberry Pi ==="

# 1. Crear directorios necesarios
sudo mkdir -p /opt/motion-ui/templates
sudo mkdir -p /var/lib/motion

# 2. Escribir /opt/motion-ui/app.py
echo "Creando backend app.py..."
sudo tee /opt/motion-ui/app.py > /dev/null << 'EOF'
import os
import re
import json
from datetime import datetime, timedelta
from flask import Flask, jsonify, render_template, send_from_directory

app = Flask(__name__)
MOTION_DIR = os.getenv("MOTION_DIR", "/var/lib/motion")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/events')
def get_events():
    events = []
    id_counter = 1
    pattern = re.compile(r'(\d+)-(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\.(mp4|avi|mkv)$')

    if os.path.exists(MOTION_DIR):
        for root, dirs, files in os.walk(MOTION_DIR):
            for file in files:
                match = pattern.match(file)
                if match:
                    cam_id, y, m, d, H, M, S, ext = match.groups()
                    start_dt = datetime(int(y), int(m), int(d), int(H), int(M), int(S))
                    end_dt = start_dt + timedelta(minutes=2)
                    
                    rel_path = os.path.relpath(os.path.join(root, file), MOTION_DIR)
                    
                    json_filename = file.rsplit('.', 1)[0] + '.json'
                    json_path = os.path.join(root, json_filename)
                    metadata = {}
                    if os.path.exists(json_path):
                        try:
                            with open(json_path, 'r', encoding='utf-8') as jf:
                                metadata = json.load(jf)
                        except Exception:
                            pass
                    
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
                        "metadata": metadata
                    })
                    id_counter += 1
    return jsonify(events)

@app.route('/video/<path:filename>')
def serve_video(filename):
    return send_from_directory(MOTION_DIR, filename)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# 3. Escribir /opt/motion-ui/templates/index.html
echo "Creando frontend index.html..."
sudo tee /opt/motion-ui/templates/index.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Motion TV Dashboard</title>
    <script src="https://unpkg.com/vis-timeline@latest/standalone/umd/vis-timeline-graph2d.min.js"></script>
    <link href="https://unpkg.com/vis-timeline@latest/styles/vis-timeline-graph2d.min.css" rel="stylesheet" type="text/css" />
    <style>
        body { background-color: #121212; color: #ffffff; font-family: sans-serif; margin: 0; padding: 15px; display: flex; flex-direction: column; height: 100vh; box-sizing: border-box; overflow: hidden; }
        h2 { margin-top: 0; font-weight: 400; color: #bb86fc; text-align: center; font-size: 22px; margin-bottom: 5px; }
        
        #filters-container { display: flex; justify-content: center; gap: 20px; margin-bottom: 10px; background: #1e1e1e; padding: 10px; border-radius: 8px; align-items: center; }
        .filter-label { font-size: 18px; display: flex; align-items: center; gap: 8px; cursor: pointer; user-select: none; }
        .filter-checkbox { transform: scale(1.4); cursor: pointer; accent-color: #03dac6; }

        #toggle-panel-btn { background: #2c2c2c; color: #03dac6; border: 2px solid #03dac6; border-radius: 6px; padding: 6px 12px; font-size: 16px; cursor: pointer; font-weight: bold; margin-left: auto; }
        #toggle-panel-btn:focus, #toggle-panel-btn:hover { background: #3d3d3d; }

        #main-layout { display: flex; flex: 1; gap: 15px; overflow: hidden; }
        #left-column { flex: 1; display: flex; flex-direction: column; overflow: hidden; }

        #video-container { position: relative; flex: 1; display: flex; justify-content: center; align-items: center; background: #000; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 10px rgba(0,0,0,0.5); min-height: 200px; }
        video { max-width: 100%; max-height: 100%; outline: none; }
        
        #loading-spinner {
            position: absolute;
            display: none;
            flex-direction: column;
            align-items: center;
            gap: 10px;
            color: #03dac6;
            font-size: 18px;
            font-weight: bold;
            background: rgba(0, 0, 0, 0.7);
            padding: 20px;
            border-radius: 12px;
            z-index: 10;
        }
        .spinner-ring {
            width: 50px;
            height: 50px;
            border: 5px solid rgba(3, 218, 198, 0.2);
            border-top: 5px solid #03dac6;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }

        #metadata-panel { background: #1e1e1e; padding: 12px; border-radius: 8px; margin: 10px 0; display: flex; flex-direction: column; gap: 8px; min-height: 60px;}
        #desc-text { font-size: 18px; margin: 0; color: #e0e0e0; }
        #badges-container { display: flex; gap: 15px; flex-wrap: wrap; }
        .badge { padding: 6px 14px; border-radius: 20px; font-weight: bold; font-size: 16px; display: flex; align-items: center; gap: 8px; }
        .badge-persona { background-color: #cf6679; color: #000; }
        .badge-animal { background-color: #ffb300; color: #000; }
        .badge-vacio { background-color: #333; color: #aaa; }

        #tv-controls { display: flex; justify-content: center; gap: 15px; margin-bottom: 10px; }
        .tv-btn { background-color: #2c2c2c; color: #ffffff; border: 4px solid transparent; border-radius: 10px; padding: 12px 25px; font-size: 20px; font-weight: bold; cursor: pointer; transition: all 0.2s ease; }
        .tv-btn:focus, .tv-btn:hover { border-color: #03dac6; background-color: #3d3d3d; outline: none; transform: scale(1.05); color: #03dac6; }
        
        #timeline { width: 100%; height: 160px; background: #1e1e1e; border: 1px solid #333; border-radius: 8px; cursor: pointer; flex-shrink: 0; }
        
        .vis-item { 
            background-color: #2d2b55; border: 2px solid #bb86fc; color: #ffffff; font-weight: bold; 
            border-radius: 6px; font-size: 15px; padding: 4px 10px; cursor: pointer; 
            display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 5px rgba(0,0,0,0.4);
        }
        .vis-item.vis-selected { background-color: #03dac6; border-color: #ffffff; color: #000000; }
        .vis-time-axis .vis-text { color: #aaa; font-size: 13px; }
        .vis-timeline { border: none; }

        #right-panel { width: 380px; background: #1e1e1e; border-radius: 8px; border: 1px solid #333; display: flex; flex-direction: column; overflow: hidden; transition: width 0.3s ease, opacity 0.3s ease; }
        #right-panel.collapsed { width: 0; opacity: 0; border: none; }
        
        #right-panel-header { background: #252525; padding: 12px; font-weight: bold; font-size: 18px; color: #bb86fc; border-bottom: 1px solid #333; text-align: center; }
        #events-list { flex: 1; overflow-y: auto; padding: 10px; display: flex; flex-direction: column; gap: 8px; }
        
        .event-card { background: #282828; padding: 10px 12px; border-radius: 6px; cursor: pointer; border-left: 4px solid #bb86fc; transition: background 0.2s; }
        .event-card:hover, .event-card:focus { background: #383838; border-left-color: #03dac6; outline: none; }
        .event-card.active { background: #32314a; border-left-color: #03dac6; }
        
        .event-card-header { font-size: 13px; color: #888; margin-bottom: 4px; display: flex; justify-content: space-between; }
        .event-card-title { font-weight: bold; font-size: 15px; color: #fff; margin-bottom: 4px; }
        .event-card-desc { font-size: 13px; color: #ccc; line-height: 1.3; }
    </style>
</head>
<body>
    <h2>Motion TV Dashboard</h2>

    <div id="filters-container">
        <label class="filter-label"><input type="checkbox" id="chk-personas" class="filter-checkbox" checked> 🚶‍♂️ Personas</label>
        <label class="filter-label"><input type="checkbox" id="chk-animales" class="filter-checkbox" checked> 🐕 Animales</label>
        <label class="filter-label"><input type="checkbox" id="chk-otros" class="filter-checkbox"> ✨ Otros / Vacío</label>
        <button id="toggle-panel-btn" tabindex="4">📋 Lista ⇄</button>
    </div>
    
    <div id="main-layout">
        <div id="left-column">
            <div id="video-container">
                <div id="loading-spinner">
                    <div class="spinner-ring"></div>
                    <span>Cargando video...</span>
                </div>
                <video id="player" controls>
                    <source src="" type="video/mp4">
                </video>
            </div>

            <div id="metadata-panel">
                <p id="desc-text">Cargando...</p>
                <div id="badges-container"></div>
            </div>

            <div id="tv-controls">
                <button id="btn-prev" class="tv-btn" tabindex="1">⏮ Anterior</button>
                <button id="btn-play" class="tv-btn" tabindex="2">⏯ Pausa / Play</button>
                <button id="btn-next" class="tv-btn" tabindex="3">Siguiente ⏭</button>
            </div>

            <div id="timeline"></div>
        </div>

        <div id="right-panel">
            <div id="right-panel-header">Historial (Top 100 Recientes)</div>
            <div id="events-list"></div>
        </div>
    </div>

    <script>
        let allEvents = [];
        let currentFilteredEvents = [];
        let currentIndex = -1;
        let timeline;
        const player = document.getElementById('player');
        const descText = document.getElementById('desc-text');
        const badgesContainer = document.getElementById('badges-container');
        const eventsListContainer = document.getElementById('events-list');
        const rightPanel = document.getElementById('right-panel');
        const loadingSpinner = document.getElementById('loading-spinner');

        player.addEventListener('waiting', () => { loadingSpinner.style.display = 'flex'; });
        player.addEventListener('playing', () => { loadingSpinner.style.display = 'none'; });
        player.addEventListener('canplay', () => { loadingSpinner.style.display = 'none'; });

        document.getElementById('toggle-panel-btn').addEventListener('click', () => {
            rightPanel.classList.toggle('collapsed');
        });

        function loadVideo(index) {
            if (index < 0 || index >= currentFilteredEvents.length) return;
            currentIndex = index;
            const event = currentFilteredEvents[currentIndex];
            
            loadingSpinner.style.display = 'flex';
            player.src = event.video_url;
            player.play().catch(() => { loadingSpinner.style.display = 'none'; });
            
            timeline.setSelection(event.id);
            
            const eventTime = new Date(event.start).getTime();
            const fifteenMinutes = 15 * 60 * 1000;
            timeline.setWindow(new Date(eventTime - fifteenMinutes), new Date(eventTime + fifteenMinutes), { animation: true });

            document.querySelectorAll('.event-card').forEach((card) => {
                if (card.dataset.eventId == event.id) {
                    card.classList.add('active');
                    card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
                } else {
                    card.classList.remove('active');
                }
            });

            if (event.metadata && Object.keys(event.metadata).length > 0) {
                descText.innerText = event.metadata.descripcion || "Sin descripción detallada.";
                
                let badgesHtml = '';
                if (event.metadata.hay_personas) {
                    badgesHtml += '<div class="badge badge-persona">🚶‍♂️ Personas Detectadas</div>';
                }
                if (event.metadata.hay_animales) {
                    badgesHtml += '<div class="badge badge-animal">🐕 Animal Detectado</div>';
                }
                if (!event.metadata.hay_personas && !event.metadata.hay_animales) {
                    badgesHtml += '<div class="badge badge-vacio">✨ ' + (event.metadata.evento_principal || 'Sin novedades') + '</div>';
                }
                badgesContainer.innerHTML = badgesHtml;
            } else {
                descText.innerText = "No hay metadata JSON para este video.";
                badgesContainer.innerHTML = '';
            }
        }

        function renderEventsList() {
            eventsListContainer.innerHTML = '';
            const top100Events = [...currentFilteredEvents]
                .sort((a, b) => new Date(b.start) - new Date(a.start))
                .slice(0, 100);

            top100Events.forEach((event, index) => {
                const card = document.createElement('div');
                card.className = 'event-card';
                card.dataset.eventId = event.id;
                card.tabIndex = 5 + index;

                const yyyy = event.year;
                const mm = String(event.month).padStart(2, '0');
                const dd = String(event.day).padStart(2, '0');
                const hh = String(event.hour).padStart(2, '0');
                const min = String(event.minute).padStart(2, '0');
                const ss = String(event.second).padStart(2, '0');
                const dateStr = `${yyyy}-${mm}-${dd} ${hh}:${min}:${ss}`;

                let summaryType = event.metadata?.evento_principal || "Evento de Cámara";
                if (event.metadata?.hay_personas) summaryType = "Personas Detectadas";
                else if (event.metadata?.hay_animales) summaryType = "Animal Detectado";

                const descSnippet = event.metadata?.descripcion || "Sin descripción.";

                card.innerHTML = `
                    <div class="event-card-header">
                        <span>${dateStr}</span>
                        <span>Cam ${event.cam_id || ''}</span>
                    </div>
                    <div class="event-card-title">${summaryType}</div>
                    <div class="event-card-desc">${descSnippet}</div>
                `;

                const handleSelect = () => {
                    const realIndex = currentFilteredEvents.findIndex(e => e.id === event.id);
                    if (realIndex !== -1) loadVideo(realIndex);
                };

                card.addEventListener('click', handleSelect);
                card.addEventListener('keydown', (e) => {
                    if (e.key === 'Enter') handleSelect();
                });

                eventsListContainer.appendChild(card);
            });
        }

        function applyFilters() {
            const showPersonas = document.getElementById('chk-personas').checked;
            const showAnimales = document.getElementById('chk-animales').checked;
            const showOtros = document.getElementById('chk-otros').checked;

            currentFilteredEvents = allEvents.filter(e => {
                const hasP = e.metadata && e.metadata.hay_personas;
                const hasA = e.metadata && e.metadata.hay_animales;
                const isOther = !hasP && !hasA;

                if (hasP && showPersonas) return true;
                if (hasA && showAnimales) return true;
                if (isOther && showOtros) return true;
                return false;
            });

            itemsDataSet.clear();
            itemsDataSet.add(currentFilteredEvents);
            renderEventsList();

            if (currentFilteredEvents.length > 0) {
                loadVideo(0);
            } else {
                player.pause();
                player.src = "";
                loadingSpinner.style.display = 'none';
                descText.innerText = "No hay eventos que coincidan con los filtros seleccionados.";
                badgesContainer.innerHTML = "";
            }
        }

        document.getElementById('chk-personas').addEventListener('change', applyFilters);
        document.getElementById('chk-animales').addEventListener('change', applyFilters);
        document.getElementById('chk-otros').addEventListener('change', applyFilters);

        document.getElementById('btn-prev').addEventListener('click', () => loadVideo(currentIndex + 1));
        document.getElementById('btn-next').addEventListener('click', () => loadVideo(currentIndex - 1));
        
        document.getElementById('btn-play').addEventListener('click', () => {
            if (player.paused) player.play();
            else player.pause();
        });

        let itemsDataSet;

        fetch('/api/events')
            .then(response => response.json())
            .then(data => {
                data.forEach(e => {
                    let icons = "";
                    if (e.metadata) {
                        if (e.metadata.hay_personas) icons += " 🚶‍♂️";
                        if (e.metadata.hay_animales) icons += " 🐕";
                    }
                    e.content = `Cam ${e.cam_id || ''}` + icons;
                });

                allEvents = data.sort((a, b) => new Date(b.start) - new Date(a.start));
                
                const container = document.getElementById('timeline');
                itemsDataSet = new vis.DataSet([]);
                
                const endDate = new Date();
                const startDate = new Date();
                startDate.setDate(endDate.getDate() - 7);

                const options = {
                    height: '160px',
                    start: startDate,
                    end: endDate,
                    zoomMin: 1000 * 60 * 2,
                    zoomMax: 1000 * 60 * 60 * 24 * 30,
                    format: { minorLabels: { minute: 'h:mma', hour: 'ha', day: 'D MMM' } }
                };
                timeline = new vis.Timeline(container, itemsDataSet, options);

                timeline.on('select', function (properties) {
                    if (properties.items.length > 0) {
                        const selectedId = properties.items[0];
                        const clickedIndex = currentFilteredEvents.findIndex(e => e.id === selectedId);
                        if (clickedIndex !== -1) {
                            loadVideo(clickedIndex);
                        }
                    }
                });

                applyFilters();
            });
    </script>
</body>
</html>
EOF

# 4. Crear servicio Systemd (/etc/systemd/system/motion-ui.service)
echo "Configurando servicio systemd..."
sudo tee /etc/systemd/system/motion-ui.service > /dev/null << 'EOF'
[Unit]
Description=Motion UI Web Dashboard
After=network.target

[Service]
User=root
WorkingDirectory=/opt/motion-ui
ExecStart=/usr/bin/python3 /opt/motion-ui/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 5. Habilitar y arrancar el servicio
echo "Habilitando y arrancando el servicio motion-ui..."
sudo systemctl daemon-reload
sudo systemctl enable motion-ui
sudo systemctl restart motion-ui

echo "=== ¡Instalación y actualización completada con éxito! ==="
sudo systemctl status motion-ui --no-pager