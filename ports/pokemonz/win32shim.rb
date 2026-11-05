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
Win32Shim.note("shim v8 (TEMP=#{ENV['TEMP']})")

# ---------------------------------------------------------------------------
# Perfil de rendimiento (solo si existe el archivo prof.on en la carpeta del port)
# ---------------------------------------------------------------------------
# Cada 30 s anota en log.txt:
#   - "frames": fotogramas, y cuanto tarda de media Graphics.update ("dentro": dibujar + esperar) frente al
#     resto del fotograma ("fuera": el codigo Ruby del juego). Si "fuera" es grande, el cuello es Ruby (CPU).
#   - desde donde se llama a las funciones mas costosas (quien llama a exist?, load_data...).
# Aviso: el muestreo se ve sesgado hacia llamadas que esperan (archivos, dibujo); usa los ms de "fuera"/"dentro".
if ENV["PZ_PROF"] == "1"
  $stdout.sync = true
  $__pz_in = 0.0; $__pz_out = 0.0; $__pz_frames = 0; $__pz_prev_end = nil
  $__pz_top = Hash.new(0); $__pz_chain = Hash.new(0); $__pz_last = Time.now
  # El informe se imprime desde Graphics.update (hilo del juego), asi no depende del hilo de muestreo.
  def __pz_report
    f = [$__pz_frames, 1].max
    puts "[prof] --- 30 s: #{$__pz_frames} frames; dentro de Graphics.update #{'%.1f' % ($__pz_in * 1000 / f)} ms/frame; fuera (Ruby del juego) #{'%.1f' % ($__pz_out * 1000 / f)} ms/frame ---"
    top = $__pz_top.dup; chain = $__pz_chain.dup
    tot = [top.values.sum, 1].max
    puts "[prof] funciones (sin contar Graphics.update), #{top.values.sum} muestras:"
    top.sort_by { |_, v| -v }.first(8).each { |k, v| puts "[prof]   #{v * 100 / tot}%  #{k}" }
    puts "[prof] quien las llama (4 niveles del juego):"
    chain.sort_by { |_, v| -v }.first(8).each { |k, v| puts "[prof]   #{v * 100 / tot}%  #{k}" }
    $__pz_top.clear; $__pz_chain.clear
    $__pz_in = 0.0; $__pz_out = 0.0; $__pz_frames = 0
  end
  class << Graphics
    alias_method :__pz_prof_update, :update
    def update(*a)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      $__pz_out += (t0 - $__pz_prev_end) if $__pz_prev_end
      r = __pz_prof_update(*a)
      $__pz_prev_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      $__pz_in += ($__pz_prev_end - t0)
      $__pz_frames += 1
      if Time.now - $__pz_last >= 30
        $__pz_last = Time.now
        __pz_report rescue nil
      end
      r
    end
  end
  Thread.new do
    main = Thread.main
    loop do
      sleep 0.02
      bt = (main.backtrace_locations rescue nil)
      next if bt.nil? || bt.empty?
      l = bt[0]
      next if l.label == "update" # Graphics.update en curso: ya se mide aparte
      $__pz_top["#{l.path}:#{l.label}"] += 1
      gs = bt.select { |x| x.path.to_s =~ /\A\d+:/ }.first(4)
      $__pz_chain[gs.map { |x| "#{x.path.split(':',2)[1]}:#{x.lineno} #{x.label}" }.join(" < ")] += 1 unless gs.empty?
    end
  end
  Win32Shim.note("perfil activado (prof.on)")
end
