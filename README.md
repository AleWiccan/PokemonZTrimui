# Pokémon Z para Trimui Smart Pro

Port **no oficial** del fangame *Pokémon Z* (RPG Maker XP + Pokémon Essentials) para la **Trimui Smart Pro**, usando el motor libre [mkxp-z](https://github.com/mkxp-z/mkxp-z) compilado para aarch64.

> **Este repositorio NO incluye el juego ni sus scripts.** Tienes que conseguir tu propia copia de *Pokémon Z* desde la página de sus autores. Los arreglos de compatibilidad se aplican **sobre tu copia** con una herramienta incluida (ver [Parchear los scripts del juego](#parchear-los-scripts-del-juego)); no se distribuye ningún archivo del juego, ni modificado ni original.

## Estado

| | |
|---|---|
| Consola | Trimui Smart Pro (Allwinner A133, aarch64, 1 GB de RAM) |
| Firmware | JEB+ (parecido a CrossMix) |
| Versión del juego probada | 2.19 |
| Resultado | Jugable: título, nueva partida, prólogo, mapas, combates, guardado, teclado en pantalla y salida limpia |

Lo que **no** funciona o es distinto a Windows está en [Limitaciones conocidas](#limitaciones-conocidas).

## Requisitos

- Trimui Smart Pro con el sistema Stock OS o un firmware derivado (probado en JEB+).
- El binario `mkxp-z` para aarch64. Es **el mismo** que usa el [port de Pokémon Añil](https://github.com/AleWiccan/Poke-Anil-Trimui): cópialo de allí ya compilado o compílalo con su kit (ver [Compilar mkxp-z](#compilar-mkxp-z)).
- Los archivos de *Pokémon Z* para Windows (carpeta con `Game.ini`, `Data/`, `Graphics/`, `Audio/`, `Fonts/`…).
- Para parchear los scripts: Python 3, o Docker (no hace falta instalar nada más).
- PortMaster es **opcional**: solo se usa su `gptokeyb` si activas `gptokeyb.on`.

## Instalación

1. Copia el contenido de `SDCARD/` de este repositorio a la raíz de la tarjeta SD.
2. Copia el binario `mkxp-z` (aarch64) a `Data/ports/pokemonz/`.
3. Copia los archivos del juego dentro de `Data/ports/pokemonz/gamedata/` (debe existir `gamedata/Game.ini`).
4. **Parchea los scripts** del juego (siguiente sección).
5. Reinicia el menú y lanza **Pokemon Z** desde la lista de Ports.

Estructura final:

```
SDCARD/
├── Roms/PORTS/PokemonZ.sh              ← lanzador
├── Imgs/PORTS/PokemonZ.png             ← carátula
└── Data/ports/pokemonz/
    ├── mkxp-z                          ← motor (aarch64), lo pones tú
    ├── libs/                           ← librerías propias (libgcc_s, libstdc++)
    ├── menuquit                        ← cierra el juego manteniendo el botón Menú
    ├── mkxp.base.json                  ← configuración del motor (editable)
    ├── mkxp.json                       ← se genera solo en cada arranque
    ├── win32shim.rb                    ← capa de compatibilidad Ruby 1.8 / Windows (se carga antes que el juego)
    ├── pokemonz.gptk                   ← mapeo mando → teclado (solo con gptokeyb.on)
    ├── gamedata/                       ← el juego (lo pones tú). Aquí se crean también las partidas guardadas
    ├── saves/                          ← configuración de usuario de mkxp-z (NO las partidas)
    ├── soundfont/                      ← SoundFont MIDI (opcional)
    ├── licenses/
    └── log.txt                         ← se crea al ejecutar
```

## Parchear los scripts del juego

*Pokémon Z* está escrito para el Ruby 1.8 de RPG Maker XP en Windows. mkxp-z usa un Ruby moderno (3.x) y no existe Windows, así que algunos scripts del juego fallan. `tools/patch_scripts.py` corrige esas diferencias **en tu copia** de `Data/Scripts.rxdata`.

Copia `gamedata/Data/Scripts.rxdata` a una carpeta de tu PC, junto a `patch_scripts.py`, y ejecuta una de estas dos opciones:

```powershell
# Con Docker (Windows PowerShell)
docker run --rm -v ${PWD}:/w python:3-slim python /w/patch_scripts.py /w/Scripts.rxdata
```

```bash
# Con Docker (Linux / macOS)
docker run --rm -v "$PWD":/w python:3-slim python /w/patch_scripts.py /w/Scripts.rxdata

# O con Python instalado
python3 patch_scripts.py Scripts.rxdata
```

Después copia el `Scripts.rxdata` resultante de vuelta a `gamedata/Data/`, sobrescribiendo el original.

- Crea una copia de seguridad `Scripts.rxdata.orig` la primera vez y **siempre parte de ella**, así que se puede repetir sin riesgo.
- Antes de escribir comprueba que puede reescribir el archivo idéntico byte a byte; si no puede, no toca nada.
- Solo usa la biblioteca estándar de Python.
- Los demás `.rxdata` de `Data/` (mapas, objetos, tilesets…) son datos, no código, y **no** necesitan parche.
- La herramienta añade al principio una línea que escribe `[scripts] parcheado vN` en `log.txt`, para comprobar que el juego usa el archivo parcheado.

### Qué corrige

Está pensado para *Pokémon Z*, pero la mayoría son problemas típicos de juegos RPG Maker XP en mkxp-z.

| Problema (Ruby 1.8 → 3.x) | Dónde | Corrección |
|---|---|---|
| `when 0:` ya no es sintaxis válida | `AudioUtilities` | `when 0` / `when 0 then …` |
| `retry` dentro de un bloque `loop do` | `PScreen_Load` | `next` |
| Regex con `\x7f-\x9f` inválida en UTF-8 | `PSystem_Utilities` | `\u007f-\u009f` |
| `cadena[i]` devolvía un número; ahora un carácter | lectores de OGG/MP3, BOM de archivos, GIF, `StringInput#getc` (lectura de `dexdata.dat`) | `getbyte` |
| `if file[file.length-1]!=0x2F` (¿acaba en `/`?) | `SpriteWindow` | `file[file.length-1,1]!="/"` |
| `alias getbyte []` pisaba `String#getbyte`/`bytesize` nativos | `Map - Klein` | se eliminan los alias |
| `USEKEYBOARDTEXTENTRY = true` (escribir con teclado físico) | `Settings` | `false`: usa el teclado en pantalla |
| `MAPVIEWMODE = 1`: mapa en Ruby puro, lento | `Settings` | `0`: tilemap nativo de mkxp-z (`tilemap.ruby` vuelve al anterior) |
| Autotiles animados reasignados cada 15 fotogramas: reconstruían el atlas y provocaban tirones en exteriores | `Tilemap_XP` | se pasa la tira completa y mkxp-z la anima solo |
| `Trainer#gender` abría y descomprimía `trainertypes.dat` en cada llamada | `PokeBattle_Trainer` | caché por tipo de entrenador |
| Consultas a la SD (`exist?`, primer byte) repetidas por cada imagen | `SpriteWindow` | caché para `Graphics/`, `Audio/` y `Game.rgss*` |

Además, `win32shim.rb` (se carga **antes** que los scripts, sin tocar el juego) aporta:

| Compatibilidad | Para qué |
|---|---|
| Stubs de `Win32API` | `kernel32`, `user32`, `winmm`, `advapi32`, DLL propias: en vez de abortar, devuelven `0` y se anota en `log.txt` como `[win32shim] stub: dll.funcion` |
| `Thread.critical`, `Array#nitems`, `Object#id` | métodos retirados de Ruby; el juego los usa |
| Envoltorio de `proc` | `return` dentro de un `proc` salía del bloque en Ruby 1.8; en Ruby 3 da `LocalJumpError`. Lo usan decenas de objetos y movimientos de campo |
| `ENV["TEMP"]` / `ENV["TMP"]` | el juego hace `Dir.chdir(ENV["TEMP"])`; en Linux no existe |
| Resolución lógica 512×384 y ventana a pantalla completa | mkxp-z arranca a 640×480; sin esto el juego se ve como un recuadro en una esquina |

## Controles

- **Mando nativo de mkxp-z** (por defecto): el que mejor funciona en la consola.
- **Salir del juego:** mantén pulsado el botón **Menú** (el central) durante 1 segundo. Es un cierre normal; las partidas se guardan desde el propio juego (ver [Partidas guardadas](#partidas-guardadas)). Para cambiar el tiempo, crea `menuquit-hold.txt` con los milisegundos (`0` = al pulsar).
- **Escribir nombres:** aparece el **teclado en pantalla** del juego, que se maneja con la cruceta y los botones del mando. No hace falta teclado físico.
- **gptokeyb (opcional):** crea un archivo vacío `gptokeyb.on` para convertir el mando en teclado con `pokemonz.gptk` (requiere PortMaster). Mezclarlo con el mando nativo puede dar pulsaciones dobles.

## Partidas guardadas

Las partidas se guardan **dentro de la carpeta del juego**, en `Data/ports/pokemonz/gamedata/`:

| Archivo | Contenido |
|---|---|
| `Game.rxdata` | Partida del primer hueco |
| `Game_2.rxdata`, `Game_3.rxdata`… | Partidas de los demás huecos |
| `Game_autosave.rxdata`, `Game_N_autosave.rxdata` | Autoguardados |
| `Data/LastSave.dat` | Recuerda qué partida se usó la última vez |

**No** están en `saves/`: el juego calcula él mismo su carpeta de guardado. En Windows usa la carpeta «Partidas guardadas»; como aquí no existe, usa la carpeta actual, que para mkxp-z es la del juego. La carpeta `saves/` solo contiene la configuración de usuario de mkxp-z.

- **Copia de seguridad:** copia los `Game*.rxdata` (y `Data/LastSave.dat`) de `gamedata/`.
- **Al actualizar o reinstalar el juego**, no borres ni sobrescribas esos archivos.

## Configuración

Edita `mkxp.base.json`, no `mkxp.json`: el lanzador regenera `mkxp.json` en cada arranque añadiendo las rutas absolutas de `gamedata/`, el SoundFont y `win32shim.rb`.

El lanzador también reconoce **archivos vacíos** en `Data/ports/pokemonz/`; así se cambian opciones sin editar nada:

| Archivo | Efecto |
|---|---|
| `frameskip.off` | **Recomendado.** No salta fotogramas. Sin él, si la consola no llega a 60 FPS, la imagen parece congelada aunque el juego siga respondiendo |
| `vsync.off` | **Recomendado.** Desactiva la sincronización vertical; mejora el rendimiento |
| `stretch.on` | Estira la imagen a 16:9 (rellena la pantalla, pero deforma: el juego es 4:3) |
| `smooth.on` | Suaviza el escalado (la escala 1,875× no es entera y con píxeles nítidos se ven irregulares) |
| `wide.on` | **Experimental.** Resolución interna 682×384 (16:9): muestra más mapa a los lados, pero menús y combates están hechos para 512×384 y pueden verse descolocados |
| `subimage.off` | Desactiva `subImageFix` (corrige rayas negras en GPUs con driver defectuoso) |
| `tilemap.ruby` | Vuelve al mapa en Ruby puro del juego (más lento) |
| `swap.on` | Crea y activa un swapfile de 768 MB en la SD (si el juego se cierra con código 137 = falta de memoria) |
| `gptokeyb.on` | Usa `gptokeyb` en vez del mando nativo |
| `menuquit-hold.txt` | Milisegundos que hay que mantener el botón Menú para salir |
| `videodriver.txt` | Nombre del driver de vídeo si no es `mali` |
| `reset-config.on` | Borra el `mkxp.json` de usuario de `saves/` (configuración de mkxp-z; las partidas no están ahí, ver [Partidas guardadas](#partidas-guardadas)) |
| `fps.on` | El log anota `FPS: N` cada segundo |
| `prof.on` | Perfil de rendimiento: cada 30 s el log anota el tiempo por fotograma, los tirones, las pasadas del recolector de basura y el tiempo medido de los métodos del mapa (`Scene_Map`, `Spriteset_Map`, eventos, sprites, sombras…). Gasta algo de CPU: quítalo al terminar |

> El menú de Opciones del juego muestra una opción **«VSync»**. Solo lee el `mkxp.json` original del juego; **no** refleja ni cambia la configuración real del motor en esta consola. Usa `vsync.off` para controlar el vsync.

## Rendimiento

El juego es pesado para la CPU de la consola (Ruby interpretado en 4× Cortex-A53). Los cuellos de botella encontrados y corregidos fueron: el mapa en Ruby puro, las consultas repetidas a la SD, la lectura repetida de `trainertypes.dat` y la reconstrucción del atlas en cada fotograma de autotile animado. Con `fps.on` y `prof.on` puedes medir en tu consola; si abres un *issue* sobre rendimiento, adjunta las líneas `[prof]` y `FPS:` de `log.txt`.

## Limitaciones conocidas

- Los **stubs de Windows** devuelven `0`: las funciones que dependen de DLL (conversión de GIF a PNG, registro de Windows, audio MCI y utilidades gráficas como `rubyscreen.dll`) no hacen nada. En el juego probado no se ha visto ningún efecto visible, pero cualquier cosa que dependa de ellas no funcionará. El log lista cuáles se han pedido (`[win32shim] stub: …`).
- Los **cuadros de texto libre dentro de mensajes** (contraseñas o similares) siguen necesitando teclado físico. El teclado en pantalla solo cubre las pantallas de nombres.
- La opción **«Tamaño de pantalla»** del menú del juego está pensada para ventanas de Windows y no se ha probado en la consola.
- `wide.on` es una prueba y puede romper el diseño de menús y combates.

## Solución de problemas

Todo se registra en `pokemonz/log.txt` (incluye el código de salida del motor). Si abres un *issue*, adjunta una copia del log.

| Síntoma | Posible causa |
|---|---|
| Se cierra al arrancar con un error en un script del juego (`Win32API`, `LocalJumpError`, `undefined method`…) | No has parcheado `Scripts.rxdata`, o el parche es de una versión anterior. Comprueba que el log muestra `[scripts] parcheado vN` y vuelve a ejecutar `patch_scripts.py` |
| `Error creating window: kmsdrm not available` | mkxp-z fuerza `kmsdrm` si no se indica driver. El lanzador usa `mali`; si tu firmware usa otro, ponlo en `videodriver.txt` |
| Se cierra al empezar *Partida nueva* con `locale::facet::_S_create_c_locale name not valid` | La consola tiene un `LANG` que no existe; el lanzador fuerza `LC_ALL=C` |
| La imagen se ve en un **recuadro** que no llena la pantalla | `win32shim.rb` antiguo o ausente. Debe salir `resolucion logica fijada a 512x384` en el log |
| La imagen se **congela** pero el juego responde | Salto de fotogramas con la consola por debajo de 60 FPS: crea `frameskip.off` |
| **Tirones** periódicos al caminar por exteriores | `Scripts.rxdata` sin el parche de autotiles (versión anterior a v12): vuelve a ejecutar `patch_scripts.py` |
| Rayas negras en los sprites del mapa | Comprueba que no existe `tilemap.ruby` (el mapa en Ruby puro las produce) ni `subimage.off` |
| No escribe el nombre | `Scripts.rxdata` sin parchear (`USEKEYBOARDTEXTENTRY` sigue en `true`) |
| Se cierra con código 137 | Falta de memoria: activa `swap.on` |
| No suena la música MIDI | Falta el SoundFont: el lanzador busca `gamedata/soundfont.sf2` y luego `soundfont/TimGM6mb.sf2` |
| Se cierra al arrancar tras tocar opciones del menú del juego | El menú reescribe `gamedata/mkxp.json`; el lanzador lo restaura desde `mkxp.json.orig`. Si hace falta, crea `reset-config.on` |
| No pasa de la pantalla de carga / no abre | Falta `mkxp-z` o `gamedata/Game.ini`; mira el log |

## Compilar mkxp-z

El binario `mkxp-z` es el mismo que el del port de Añil. Se compila con Docker (Windows, Linux o macOS) usando el kit de [AleWiccan/Poke-Anil-Trimui](https://github.com/AleWiccan/Poke-Anil-Trimui):

- Base `debian:bullseye-slim` (glibc 2.31; la consola admite hasta 2.33).
- Cross-compilación a **aarch64** con meson, OpenGL ES y la **SDL2 de la consola** (se compila contra SDL 2.26.5 solo para enlazar; en ejecución se usa la de `/usr/trimui/lib`, con su driver de vídeo `mali`).
- Sin PulseAudio, JACK, PipeWire, OSS ni OpenSSL. Audio por ALSA.
- Commit de mkxp-z fijado: `37a04d14413454551a7b6aadbb4e93e67168accb`.

## Licencias

- Este repositorio (lanzador, `win32shim.rb`, `patch_scripts.py` y demás herramientas): **GPL-3.0**, ver `LICENSE`. `tools/menuquit.c` es MIT.
- **mkxp-z**: GPL-2.0 o posterior. Se incluye su licencia y el commit exacto en `licenses/`.
- **TimGM6mb.sf2** (si lo usas): GPL-2.
- **Pokémon Z** pertenece a sus autores y **no se distribuye aquí**, ni sus scripts ni sus datos.
- Proyecto de aficionados sin ánimo de lucro, sin relación con Nintendo, Game Freak ni Creatures Inc. *Pokémon* es marca registrada de sus respectivos propietarios.

## Créditos

- Autores de *Pokémon Z*: _(añade aquí el nombre y el enlace oficial de los autores)_.
- [mkxp-z](https://github.com/mkxp-z/mkxp-z) y [mkxp](https://github.com/Ancurio/mkxp): motor RGSS libre.
- [Poke-Anil-Trimui](https://github.com/AleWiccan/Poke-Anil-Trimui): base del port, lanzador y kit de compilación.
- [PortMaster](https://portmaster.games/): `gptokeyb` y la comunidad de ports.
- [Periko21/mkxp-z-r36s](https://github.com/Periko21/mkxp-z-r36s): referencia para adaptar mkxp-z a consolas portátiles.
