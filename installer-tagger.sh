#!/bin/bash
# install_tagger.sh - Instalador idempotente (Versión Final)

APP_DIR="/opt/video_tagger"
VENV_DIR="$APP_DIR/venv"
PYTHON_SCRIPT="$APP_DIR/tagger.py"
SERVICE_FILE="/etc/systemd/system/video_tagger.service"

# Pon tu clave AQ... aquí
API_KEY="TU_API_KEY_AQUI" 

echo "=== Iniciando instalación del Video Tagger (Versión Final) ==="

# 1. Crear directorios y entorno virtual
echo "-> Configurando entorno..."
mkdir -p "$APP_DIR"
apt-get update -y && apt-get install -y python3-venv python3-pip
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

# 2. Instalar el NUEVO SDK de Google
echo "-> Instalando dependencias (google-genai)..."
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" uninstall -y google-generativeai
"$VENV_DIR/bin/pip" install google-genai

# 3. Crear el script de Python actualizado
echo "-> Creando el script de procesamiento..."
cat << 'EOF' > "$PYTHON_SCRIPT"
import os
import time
import json
from datetime import datetime
from google import genai
from google.genai import types

# Configuración
API_KEY = "TU_API_KEY_AQUI" # Se inyecta dinámicamente
BASE_DIR = "/media/hdd2/Camara/Recordings"
MIN_DATE = datetime(2026, 9, 10).date()
CHECK_INTERVAL_SECONDS = 300  # 5 minutos

# Inicializar el nuevo cliente de Gemini
client = genai.Client(api_key=API_KEY)

def procesar_video(video_path, json_path):
    print(f"Procesando nuevo video: {video_path}")
    uploaded_file = None
    try:
        # Subir el video a la API
        uploaded_file = client.files.upload(file=video_path)
        
        # Esperar a que los servidores de Google procesen el video (Pausa de 10s)
        while "PROCESSING" in str(uploaded_file.state):
            print(".", end="", flush=True)
            time.sleep(10)
            uploaded_file = client.files.get(name=uploaded_file.name)
            
        if "FAILED" in str(uploaded_file.state):
            print("\nError al procesar el archivo en los servidores de Google.")
            return

        print("\nAnalizando contenido...")
        prompt = """
        Analiza este video de seguridad. Devuelve estrictamente un JSON válido con esta estructura:
        {
          "evento_principal": "palabra_clave",
          "descripcion": "breve resumen de lo que sucede",
          "hay_personas": true,
          "hay_animales": true
        }
        El 'evento_principal' debe ser una sola palabra (ej. Persona, Gato, Auto, Vacio, Arboles).
        """
        
        # Usamos el modelo Flash-Lite para evitar el límite diario
        response = client.models.generate_content(
            model='gemini-3.5-flash-lite',
            contents=[uploaded_file, prompt],
            config=types.GenerateContentConfig(
                response_mime_type="application/json"
            )
        )
        
        metadata = json.loads(response.text)
        
        # Guardar el JSON junto al video
        with open(json_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, ensure_ascii=False, indent=4)
            
        print(f"Etiquetado exitoso: {metadata.get('evento_principal', 'Desconocido')}")

    except Exception as e:
        print(f"Error procesando {video_path}: {e}")
    finally:
        # Limpieza: borrar el archivo de los servidores de Google
        if uploaded_file:
            try:
                client.files.delete(name=uploaded_file.name)
            except:
                pass
        
        # Pausa obligatoria de 30 segundos para no exceder los límites de velocidad de la API
        print("Pausa de 30s para respetar los límites de la API...")
        time.sleep(30)

def es_fecha_valida(folder_name):
    try:
        folder_date = datetime.strptime(folder_name, "%Y-%m-%d").date()
        return folder_date >= MIN_DATE
    except ValueError:
        return False

def buscar_y_procesar():
    if not os.path.exists(BASE_DIR):
        print(f"La ruta {BASE_DIR} no existe. Esperando...")
        return

    for folder in os.listdir(BASE_DIR):
        folder_path = os.path.join(BASE_DIR, folder)
        if os.path.isdir(folder_path) and es_fecha_valida(folder):
            for file in os.listdir(folder_path):
                if file.endswith(('.mp4', '.mkv', '.avi')):
                    video_path = os.path.join(folder_path, file)
                    json_filename = os.path.splitext(file)[0] + '.json'
                    json_path = os.path.join(folder_path, json_filename)
                    
                    if not os.path.exists(json_path):
                        procesar_video(video_path, json_path)

if __name__ == "__main__":
    print("Iniciando servicio de etiquetado de videos (Gemini 3.5 Flash-Lite)...")
    while True:
        buscar_y_procesar()
        print(f"Durmiendo por {CHECK_INTERVAL_SECONDS / 60} minutos...")
        time.sleep(CHECK_INTERVAL_SECONDS)
EOF

# Inyectar la API key real usando sed
sed -i "s/TU_API_KEY_AQUI/$API_KEY/g" "$PYTHON_SCRIPT"

# 4. Crear y recargar el servicio systemd
echo "-> Configurando servicio systemd..."
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Video Security Tagger (Gemini API)
After=network.target

[Service]
Type=simple
User=root
ExecStart=$VENV_DIR/bin/python $PYTHON_SCRIPT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable video_tagger.service
systemctl restart video_tagger.service

echo "=== Actualización e Instalación Completada ==="
echo "Puedes ver los logs en tiempo real ejecutando:"
echo "sudo journalctl -u video_tagger.service -f"