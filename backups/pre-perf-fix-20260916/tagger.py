# API_KEY = "XXXXXXXXXXXXXXX" # Se inyecta dinámicamente
#BASE_DIR = "/media/hdd2/Camara/Recordings"
import os
import time
import json
from datetime import datetime, timedelta
from google import genai
from google.genai import types

# --- CONFIGURACIÓN ---
# ¡IMPORTANTE! Pon aquí tu clave que empieza con AQ.
API_KEY = "XXXXXXXXXXXXXXX" 
BASE_DIR = "/media/hdd2/Camara/Recordings"
MIN_DATE = datetime(2026, 9, 10).date()
CHECK_INTERVAL_SECONDS = 300  # 5 minutos de espera entre revisiones de carpetas

# Inicializar el cliente de Gemini (Nuevo SDK)
client = genai.Client(api_key=API_KEY)

def procesar_video(video_path, json_path):
    print(f"Procesando nuevo video: {video_path}")
    uploaded_file = None
    try:
        # Subir el video a la API
        uploaded_file = client.files.upload(file=video_path)
        
        # Esperar a que los servidores de Google procesen el video
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
          "hay_animales": true,
          "movimiento_vegetacion": true
        }
        REGLAS PARA EL EVENTO PRINCIPAL:
        - Debe ser una sola palabra (ej. Persona, Animal, Auto, Vegetacion, Vacio).
        - Si el único movimiento en el video es de plantas, árboles, hojas o césped moviéndose por el viento, el 'evento_principal' DEBE ser 'Vegetacion'.
        - Si hay una persona o animal, prioriza etiquetar a la Persona o Animal como evento principal, incluso si también hay viento.
        """
        # Usamos el modelo Flash-Lite (Límite de 500 diarios en nivel gratuito)
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
        error_msg = str(e)
        print(f"Error procesando {video_path}: {error_msg}")
        
        # Manejo de error 429: Cuota diaria excedida
        if "429" in error_msg and "quota" in error_msg.lower():
            ahora = datetime.now()
            
            # Google resetea la cuota a la medianoche del Pacífico (04:00 AM en Argentina)
            # Calculamos para despertar a las 04:05 AM por seguridad
            if ahora.hour >= 4:
                proximo_reinicio = (ahora + timedelta(days=1)).replace(hour=4, minute=5, second=0, microsecond=0)
            else:
                proximo_reinicio = ahora.replace(hour=4, minute=5, second=0, microsecond=0)
                
            segundos_espera = (proximo_reinicio - ahora).total_seconds()
            horas_espera = segundos_espera / 3600
            
            print(f"\n[!] Límite diario de 500 videos alcanzado.")
            print(f"[!] Durmiendo {horas_espera:.2f} horas hasta las 04:05 AM...")
            time.sleep(segundos_espera)

    finally:
        # Limpieza: borrar el archivo de los servidores de Google
        if uploaded_file:
            try:
                client.files.delete(name=uploaded_file.name)
            except:
                pass
        
        # Pausa obligatoria de 30 segundos para evitar límite de peticiones por minuto (RPM)
        print("Pausa de 30s para respetar los límites de velocidad de la API...")
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

    for folder in sorted(os.listdir(BASE_DIR)): # Usamos sorted para ir en orden de fechas
        folder_path = os.path.join(BASE_DIR, folder)
        if os.path.isdir(folder_path) and es_fecha_valida(folder):
            for file in sorted(os.listdir(folder_path)):
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
        print(f"Escaneo finalizado. Durmiendo por {CHECK_INTERVAL_SECONDS / 60} minutos...")
        time.sleep(CHECK_INTERVAL_SECONDS)
