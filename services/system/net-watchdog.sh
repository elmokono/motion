#!/bin/bash
# Vigila que el Pi tenga red y la recupera solo.
#
# Motivo: tras un corte de luz el router tarda mas en volver que el Pi. El wifi
# no se reasocia y el sistema queda sin red por horas o dias. Verificado dos
# veces en el log de motion: 47 h (6-8 sep 2026) y 25 h (19-20 sep 2026), ambas
# resueltas solo con un reinicio manual. Motion no tiene la culpa: reintenta
# cada 10 s para siempre, pero contra una red que no existe.
#
# Escalonado: primero reintenta el wifi; si sigue sin red, reinicia el equipo.

set -u
GATEWAY="${GATEWAY:-192.168.0.1}"
IFACE="${IFACE:-wlan0}"
FALLOS_SOFT="${FALLOS_SOFT:-3}"    # ~3 min -> reasociar wifi
FALLOS_HARD="${FALLOS_HARD:-10}"   # ~10 min -> reiniciar
UPTIME_MIN=900                     # no reiniciar en los primeros 15 min de vida
ESTADO=/run/net-watchdog.fails     # en /run: se reinicia solo en cada arranque

if ping -c2 -W3 "$GATEWAY" >/dev/null 2>&1; then
    if [ -s "$ESTADO" ] && [ "$(cat "$ESTADO")" != "0" ]; then
        logger -t net-watchdog "red recuperada tras $(cat "$ESTADO") chequeos fallidos"
    fi
    echo 0 > "$ESTADO"
    exit 0
fi

n=$(( $(cat "$ESTADO" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$ESTADO"
logger -t net-watchdog "gateway $GATEWAY inalcanzable (fallo $n)"

if [ "$n" -eq "$FALLOS_SOFT" ]; then
    logger -t net-watchdog "reasociando $IFACE"
    nmcli device disconnect "$IFACE" >/dev/null 2>&1
    sleep 3
    if ! nmcli device connect "$IFACE" >/dev/null 2>&1; then
        logger -t net-watchdog "nmcli fallo, reiniciando NetworkManager"
        systemctl restart NetworkManager
    fi
elif [ "$n" -ge "$FALLOS_HARD" ]; then
    up=$(cut -d. -f1 /proc/uptime)
    if [ "$up" -lt "$UPTIME_MIN" ]; then
        # Evita el bucle de reinicios si el router sigue apagado.
        logger -t net-watchdog "sin red pero uptime ${up}s < ${UPTIME_MIN}s: no reinicio todavia"
    else
        logger -t net-watchdog "sin red tras $n chequeos, reiniciando el sistema"
        systemctl reboot
    fi
fi
