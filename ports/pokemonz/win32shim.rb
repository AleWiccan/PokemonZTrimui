# Shim de Win32API para Linux (Trimui). Se ejecuta ANTES de los scripts del juego (preloadScript de mkxp-z).
# Si el juego pide una DLL de Windows que aqui no existe (kernel32, user32...), en vez de abortar
# se crea un stub: la llamada devuelve 0. Cada stub nuevo se anota en log.txt como "[win32shim] stub: dll.funcion".
module Win32Shim
  SEEN = {}
  def self.note(msg)
    return if SEEN[msg]
    SEEN[msg] = true
    puts "[win32shim] #{msg}"
  end
end

if defined?(Win32API)
  class Win32API
    alias_method :__shim_init, :initialize
    def initialize(*a)
      @shim_ok = true
      begin
        __shim_init(*a)
      rescue Exception => e
        @shim_ok = false
        Win32Shim.note("stub: #{a[0]}.#{a[1]}")
      end
    end
    alias_method :__shim_call, :call
    def call(*args)
      return 0 unless @shim_ok
      begin
        __shim_call(*args)
      rescue Exception => e
        Win32Shim.note("call fallida: #{e.class}")
        0
      end
    end
    alias_method :Call, :call
  end
else
  Win32Shim.note("Win32API no existia: se define un stub completo")
  class Win32API
    def initialize(*a); Win32Shim.note("stub: #{a[0]}.#{a[1]}"); end
    def call(*args); 0; end
    alias_method :Call, :call
  end
end

# ---------------------------------------------------------------------------
# Compatibilidad con Ruby 1.8 (los scripts de RPG Maker XP la esperan)
# ---------------------------------------------------------------------------
# Thread.critical existia en Ruby 1.8 y se retiro en 1.9. El juego la usa en Audio y BitmapCache.
unless Thread.respond_to?(:critical)
  class Thread
    @@__critical = false
    def self.critical; @@__critical; end
    def self.critical=(v); @@__critical = v; end
  end
end
# `return` dentro de un `proc` (Ruby 1.8: salia del proc). En Ruby 3 da LocalJumpError cuando el proc
# se llama despues de que termine el script que lo creo (los scripts de PokemonItems, HiddenMoves,
# PokeRadar... registran decenas de procs asi). Se captura el error y se devuelve el valor del return.
module Kernel
  alias_method :__proc_orig, :proc
  private :__proc_orig
  def proc(&blk)
    return __proc_orig unless blk
    Proc.new do |*args|
      begin
        blk.call(*args)
      rescue LocalJumpError => e
        raise unless e.reason == :return
        e.exit_value
      end
    end
  end
  private :proc
end
# Object#id (1.8) era un alias de object_id; ej. nil.id valia 4. Sombras lo usa sin querer con nil.
unless Object.method_defined?(:id)
  class Object
    def id; object_id; end
  end
end
# Array#nitems (1.8): numero de elementos que no son nil (lo usa PScreen_Storage)
unless [].respond_to?(:nitems)
  class Array
    def nitems; count { |x| !x.nil? }; end
  end
end

# ---------------------------------------------------------------------------
# Variables de entorno de Windows que el juego usa (en Linux no existen)
# ---------------------------------------------------------------------------
# TEMP: carpeta temporal (Dir.chdir(ENV["TEMP"]) al cargar imagenes; en Linux era nil y abortaba)
tmpdir = ["/tmp", ENV["TMPDIR"], "."].compact.find { |d| File.directory?(d) && File.writable?(d) } || "."
ENV["TEMP"] ||= tmpdir
ENV["TMP"]  ||= tmpdir
Win32Shim.note("shim v13 (TEMP=#{ENV['TEMP']})")

# ---------------------------------------------------------------------------
# Ventana a pantalla completa tras Graphics.resize_screen
# ---------------------------------------------------------------------------
# mkxp-z arranca la pantalla del juego a 640x480 y el juego llama a Graphics.resize_screen(512, 384).
# Esa llamada pide tambien cambiar el tamano de la ventana, y el controlador grafico de la Trimui deja un
# recuadro de 512x384 en lugar de la pantalla completa. Tras cada resize_screen se devuelve la ventana al
# tamano de la pantalla (1280x720); mkxp-z escala la imagen del juego a esa ventana (fixedAspectRatio, etc.).
PZ_WIN_W = (ENV["PZ_WINW"] || 1280).to_i
PZ_WIN_H = (ENV["PZ_WINH"] || 720).to_i
if defined?(Graphics) && Graphics.respond_to?(:resize_screen) && Graphics.respond_to?(:resize_window) && !Graphics.respond_to?(:__pz_resize_screen)
  class << Graphics
    alias_method :__pz_resize_screen, :resize_screen
    def resize_screen(*a)
      r = __pz_resize_screen(*a)
      begin
        Graphics.resize_window(PZ_WIN_W, PZ_WIN_H, false)
        Win32Shim.note("resize_screen#{a.inspect}: ventana devuelta a #{PZ_WIN_W}x#{PZ_WIN_H}")
      rescue Exception => e
        Win32Shim.note("resize_window fallo: #{e.class}")
      end
      r
    end
  end
else
  Win32Shim.note("Graphics.resize_screen/resize_window no disponibles")
end

# mkxp-z arranca con una pantalla logica de 640x480 y el juego (que se disenó para una ventana de 512x384)
# nunca llega a pedir el cambio: dibuja 512x384 en la esquina de un lienzo de 640x480, y por eso se ve un
# "cuadro" que no llena la pantalla aunque se estire. Se fija aqui la resolucion logica real del juego.
begin
  pz_w = (ENV["PZ_WIDE"] == "1" ? 682 : 512)
  Graphics.resize_screen(pz_w, 384)
  Win32Shim.note("resolucion logica fijada a #{pz_w}x384")
rescue Exception => e
  Win32Shim.note("no se pudo fijar la resolucion logica: #{e.class}")
end

# ---------------------------------------------------------------------------
# Perfil de rendimiento (solo si existe el archivo prof.on en la carpeta del port)
# ---------------------------------------------------------------------------
# Cada 30 s anota en log.txt:
#   - frames y cuanto tarda de media Graphics.update ("dentro": dibujar/esperar) frente al resto del fotograma
#     ("fuera": el codigo Ruby del juego). Si "fuera" es grande, el cuello es Ruby (CPU).
#   - tirones (fotogramas largos), pasadas del recolector de basura y numero de eventos del mapa.
#   - tiempo MEDIDO de los metodos clave del mapa (update de Scene_Map, Spriteset_Map, Game_Event, Sprite_Character,
#     sombras, interprete...). Es tiempo inclusivo: un metodo incluye lo que llama (Game_Event#update incluye Game_Character#update).
#     "max" es la llamada individual mas larga: si coincide con los tirones, ahi esta el problema.
if ENV["PZ_PROF"] == "1"
  $stdout.sync = true
  $__pz_in = 0.0; $__pz_out = 0.0; $__pz_frames = 0; $__pz_prev_end = nil; $__pz_last = Time.now
  $__pz_max = 0.0; $__pz_n50 = 0; $__pz_n100 = 0
  $__pz_gc0 = GC.count; $__pz_gct0 = (GC.stat(:time) rescue 0)
  $__pz_t = Hash.new { |h, k| h[k] = [0.0, 0, 0.0] }   # etiqueta => [total s, llamadas, max s]
  $__pz_instr_done = false
  PZ_INSTR = [
    ["Scene_Map", :update], ["Spriteset_Map", :update], ["Game_Map", :update], ["Game_Player", :update],
    ["Game_Event", :update], ["Game_Character", :update], ["Sprite_Character", :update],
    ["Sprite_Shadow", :update], ["ShadowSprite", :update], ["Interpreter", :update], ["Game_Screen", :update],
    ["SynchronizedTilemap", :update], ["CustomTilemap", :update], ["Event", :trigger],
    ["Particle_Engine", :update], ["Object", :pbDayNightTint], ["Object", :pbEventCommentInput],
    ["Object", :pbUpdateSceneMap], ["Interpreter", :command_355]
  ]
  def __pz_install_instrumentation
    PZ_INSTR.each do |cname, mname|
      begin
        k = Object.const_get(cname)
        next unless k.method_defined?(mname) || k.private_method_defined?(mname)
        label = "#{cname}##{mname}"
        mod = Module.new do
          define_method(mname) do |*a, &b|
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            begin
              super(*a, &b)
            ensure
              d = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
              h = $__pz_t[label]
              h[0] += d; h[1] += 1; h[2] = d if d > h[2]
            end
          end
        end
        k.prepend(mod)
      rescue NameError
        next   # esa clase no existe en este juego
      rescue Exception => e
        Win32Shim.note("perfil: no se pudo medir #{cname}##{mname}: #{e.class}")
      end
    end
    Win32Shim.note("perfil: metodos del mapa instrumentados")
  end
  def __pz_report
    f = [$__pz_frames, 1].max
    puts "[prof] --- 30 s: #{$__pz_frames} frames; dentro de Graphics.update #{'%.1f' % ($__pz_in * 1000 / f)} ms/frame; fuera (Ruby del juego) #{'%.1f' % ($__pz_out * 1000 / f)} ms/frame ---"
    gct = (GC.stat(:time) rescue 0)
    puts "[prof] tirones: fotograma mas largo #{'%.0f' % ($__pz_max * 1000)} ms; >50 ms: #{$__pz_n50}; >100 ms: #{$__pz_n100}; recolector de basura (GC): #{GC.count - $__pz_gc0} pasadas, #{gct - $__pz_gct0} ms en total"
    if defined?($game_map) && $game_map
      puts "[prof] mapa #{($game_map.map_id rescue '?')}: #{($game_map.events.size rescue '?')} eventos"
    end
    puts "[prof] metodos medidos (ms por fotograma | llamadas por fotograma | llamada mas larga):"
    $__pz_t.sort_by { |_, v| -v[0] }.first(14).each do |k, v|
      puts "[prof]   #{'%6.2f' % (v[0] * 1000 / f)} ms  #{'%6.1f' % (v[1].to_f / f)} llam  max #{'%5.0f' % (v[2] * 1000)} ms  #{k}"
    end
    $__pz_t.clear
    $__pz_in = 0.0; $__pz_out = 0.0; $__pz_frames = 0
    $__pz_max = 0.0; $__pz_n50 = 0; $__pz_n100 = 0
    $__pz_gc0 = GC.count; $__pz_gct0 = gct
  end
  class << Graphics
    alias_method :__pz_prof_update, :update
    def update(*a)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      $__pz_out += (t0 - $__pz_prev_end) if $__pz_prev_end
      r = __pz_prof_update(*a)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ft = $__pz_prev_end ? (t1 - $__pz_prev_end) : 0.0
      $__pz_prev_end = t1
      $__pz_in += (t1 - t0)
      $__pz_frames += 1
      $__pz_max = ft if ft > $__pz_max
      $__pz_n50 += 1 if ft > 0.05
      $__pz_n100 += 1 if ft > 0.1
      if !$__pz_instr_done && defined?(Scene_Map) && defined?(Spriteset_Map)
        $__pz_instr_done = true
        __pz_install_instrumentation rescue nil
      end
      if Time.now - $__pz_last >= 30
        $__pz_last = Time.now
        __pz_report rescue nil
      end
      r
    end
  end
  Win32Shim.note("perfil activado (prof.on)")
end
