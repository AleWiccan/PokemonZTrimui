#!/bin/sh
# Pokemon Z - lanzador para Trimui Smart Pro (JEB+) - motor mkxp-z (RPG Maker XP)
# Va en SDCARD/Roms/PORTS/ ; los datos en SDCARD/Data/ports/pokemonz/  (o junto a este .sh en ./pokemonz)
HERE="$(cd "$(dirname "$0")" && pwd)"
GAMEDIR=""
for d in "$HERE/../../Data/ports/pokemonz" "$HERE/pokemonz"; do
  if [ -d "$d" ]; then GAMEDIR="$(cd "$d" && pwd)"; break; fi
done
[ -n "$GAMEDIR" ] || exit 1
cd "$GAMEDIR" || exit 1

LOGF="$GAMEDIR/log.txt"
echo "[launcher] version 1 (basado en el lanzador de Anil v9) - $(date)" > "$LOGF"

# Libs propias primero, luego la SDL2 de la consola. SDL_VIDEODRIVER sin definir (driver mali).
export LD_LIBRARY_PATH="$GAMEDIR/libs:/usr/trimui/lib:$LD_LIBRARY_PATH"
# OJO: si SDL_VIDEODRIVER esta vacio, mkxp-z FUERZA "kmsdrm" (que la consola no tiene: "kmsdrm not available").
# Hay que nombrar el driver de la consola. Por defecto "mali"; se puede cambiar con un archivo videodriver.txt.
VD="mali"
[ -f "$GAMEDIR/videodriver.txt" ] && VD="$(head -n 1 "$GAMEDIR/videodriver.txt" | tr -d '\r\n ')"
export SDL_VIDEODRIVER="$VD"
# System.user_language (la llama Essentials al empezar Partida nueva) hace std::locale("") y ABORTA si LANG/LC_ALL
# apuntan a un locale que la consola no tiene ("locale::facet::_S_create_c_locale name not valid"). "C" siempre existe.
echo "[launcher] LANG=$LANG LC_ALL=$LC_ALL (se fuerzan a C)" >> "$LOGF"
export LC_ALL=C
export LANG=C
unset LANGUAGE
echo "[launcher] SDL_VIDEODRIVER=$SDL_VIDEODRIVER" >> "$LOGF"
export HOME="$GAMEDIR"
export XDG_DATA_HOME="$GAMEDIR/saves"
export XDG_CONFIG_HOME="$GAMEDIR/saves"
mkdir -p "$XDG_DATA_HOME"

[ -f "$GAMEDIR/gamedata/Game.ini" ] || { echo "No hay juego en $GAMEDIR/gamedata (falta Game.ini)" >> "$LOGF"; exit 1; }
[ -f "$GAMEDIR/mkxp-z" ] || { echo "Falta el binario aarch64 mkxp-z en $GAMEDIR" >> "$LOGF"; exit 1; }
chmod +x "$GAMEDIR/mkxp-z"

# Si el menu de opciones del juego deja la configuracion en mal estado: crea un archivo reset-config.on
# y se borra el mkxp.json de usuario (NO las partidas guardadas).
if [ -f "$GAMEDIR/reset-config.on" ]; then
  find "$GAMEDIR/saves" -name mkxp.json -exec rm -f {} \; 2>/dev/null
  rm -f "$GAMEDIR/reset-config.on"
  echo "[launcher] configuracion de usuario (mkxp.json en saves) borrada" >> "$LOGF"
fi

# mkxp-z falla con un gameFolder RELATIVO ("Failed to check current path"): se genera mkxp.json con rutas absolutas
# a partir de mkxp.base.json (que es el que se edita).
SFPATH=""
for c in "$GAMEDIR/gamedata/soundfont.sf2" "$GAMEDIR/soundfont/TimGM6mb.sf2"; do
  if [ -f "$c" ]; then SFPATH="$c"; break; fi
done
{
  printf '{\n  "gameFolder": "%s/gamedata",\n' "$GAMEDIR"
  [ -n "$SFPATH" ] && printf '  "midiSoundFont": "%s",\n' "$SFPATH"
  tail -n +2 "$GAMEDIR/mkxp.base.json"
} > "$GAMEDIR/mkxp.json"
echo "[launcher] mkxp.json generado (gameFolder=$GAMEDIR/gamedata, soundfont=${SFPATH:-ninguno})" >> "$LOGF"

# El motor NO lee gamedata/mkxp.json (usa el de esta carpeta), pero el menu de opciones del juego (vsync...) lo REESCRIBE,
# y si queda vacio o roto el juego se cierra al arrancar (NameError HTTPLite::JSON::ParserError).
# Se guarda una copia original la primera vez y se restaura en cada arranque.
GJ="$GAMEDIR/gamedata/mkxp.json"
if [ -f "$GJ" ]; then
  [ -f "$GJ.orig" ] || { [ -s "$GJ" ] && cp "$GJ" "$GJ.orig"; }
  [ -f "$GJ.orig" ] && cp "$GJ.orig" "$GJ" && echo "[launcher] gamedata/mkxp.json restaurado desde .orig ($(wc -c < "$GJ") bytes)" >> "$LOGF"
else
  echo "[launcher] AVISO: no existe gamedata/mkxp.json" >> "$LOGF"
fi

# --- Diagnostico: que ha guardado el juego/menu de opciones (aparece en log.txt) ---
{
  echo "[launcher] archivos en saves:"; find "$GAMEDIR/saves" -type f 2>/dev/null | head -n 20
  for f in $(find "$GAMEDIR/saves" -name mkxp.json 2>/dev/null); do echo "[launcher] contenido de $f:"; cat "$f"; echo; done
  echo "[launcher] archivos de gamedata modificados despues de Game.ini:"
  find "$GAMEDIR/gamedata" -type f -newer "$GAMEDIR/gamedata/Game.ini" 2>/dev/null | head -n 20
} >> "$LOGF"

# --- Swap opcional (1 GB de RAM). Crea un archivo swap.on para activarlo ---
if [ -f "$GAMEDIR/swap.on" ] && ! grep -q "$GAMEDIR/swapfile" /proc/swaps 2>/dev/null; then
  [ -f "$GAMEDIR/swapfile" ] || { dd if=/dev/zero of="$GAMEDIR/swapfile" bs=1M count=768 >/dev/null 2>&1
                                  chmod 600 "$GAMEDIR/swapfile"; mkswap "$GAMEDIR/swapfile" >/dev/null 2>&1; }
  swapon "$GAMEDIR/swapfile" >/dev/null 2>&1 || echo "[launcher] swapon FALLO" >> "$LOGF"
fi

# --- Controles ---
# Por defecto se usa el mando NATIVO de mkxp-z (es el que mejor funciona en esta consola), SIN gptokeyb.
# Para usar gptokeyb (mando -> teclado, mapeo en pokemonz.gptk), crea un archivo vacio gptokeyb.on
GPTK=""
if [ -f "$GAMEDIR/gptokeyb.on" ]; then
  for c in /mnt/SDCARD/Data/ports/PortMaster /mnt/SDCARD/Apps/PortMaster/PortMaster /mnt/SDCARD/Roms/PORTS/PortMaster \
           /mnt/SDCARD/Apps/PortMaster /opt/system/Tools/PortMaster /roms/ports/PortMaster "$HERE/PortMaster"; do
    if [ -x "$c/gptokeyb" ]; then GPTK="$c/gptokeyb"; break; fi
  done
  if [ -n "$GPTK" ]; then
    echo "[launcher] gptokeyb ACTIVADO (gptokeyb.on): $GPTK" >> "$LOGF"
    CTRLDIR="$(dirname "$GPTK")"
    [ -f "$CTRLDIR/gamecontrollerdb.txt" ] && export SDL_GAMECONTROLLERCONFIG_FILE="$CTRLDIR/gamecontrollerdb.txt"
    [ -d "$CTRLDIR/libs" ] && export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CTRLDIR/libs"
    "$GPTK" "mkxp-z" -c "$GAMEDIR/pokemonz.gptk" >> "$LOGF" 2>&1 &
    GPTK_PID=$!
  else
    echo "[launcher] AVISO: gptokeyb.on existe pero no se encontro gptokeyb" >> "$LOGF"
  fi
else
  echo "[launcher] controles: mando nativo de mkxp-z (gptokeyb desactivado; crea gptokeyb.on para activarlo)" >> "$LOGF"
fi

# --- Salir del juego manteniendo el boton Menu (indice 8) ---
# menuquit vigila el mando y envia SIGTERM a mkxp-z. Tiempo que hay que mantenerlo: 1000 ms por defecto;
# se cambia con un archivo menuquit-hold.txt que contenga los milisegundos (0 = al pulsar, sin mantener).
chmod +x "$GAMEDIR/menuquit" 2>/dev/null
MQ_HOLD=1000
[ -f "$GAMEDIR/menuquit-hold.txt" ] && MQ_HOLD="$(head -n 1 "$GAMEDIR/menuquit-hold.txt" | tr -d '\r\n ')"

sync 2>/dev/null   # que el log llegue a la SD aunque la consola se cuelgue
"$GAMEDIR/mkxp-z" >> "$LOGF" 2>&1 &
MK_PID=$!
if [ -x "$GAMEDIR/menuquit" ]; then
  "$GAMEDIR/menuquit" "$MK_PID" 8 "$MQ_HOLD" >> "$LOGF" 2>&1 &
  MQ_PID=$!
else
  echo "[launcher] AVISO: falta menuquit; no se podra salir con el boton Menu" >> "$LOGF"
fi
wait "$MK_PID"
CODE=$?
[ -n "$MQ_PID" ] && kill "$MQ_PID" 2>/dev/null
echo "[launcher] codigo de salida: $CODE  (137 = falta de memoria, 143 = cerrado con Menu)" >> "$LOGF"
[ "$CODE" = "137" ] && dmesg 2>/dev/null | grep -i -E "killed process|out of memory|oom" | tail -5 >> "$LOGF"
[ -n "$GPTK_PID" ] && kill "$GPTK_PID" 2>/dev/null
exit 0
