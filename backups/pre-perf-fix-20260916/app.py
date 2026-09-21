import os
import re
import json
from datetime import datetime, timedelta
from flask import Flask, jsonify, render_template, send_from_directory

app = Flask(__name__)
MOTION_DIR = os.getenv("MOTION_DIR", "/media/hdd2/Camara/Recordings")

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
