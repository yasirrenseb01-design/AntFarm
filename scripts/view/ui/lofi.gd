extends Node
## Background music made in code (no audio files): slow lo-fi pieces, each ~53 s of 16 bars at 72 BPM -
## jazzy seventh/ninth chords on a soft electric-piano voice, a round bass, a brushed swing beat, a sparse
## pentatonic tune, and vinyl crackle, all through a warm low-pass. Each piece is new (its own chord
## progression, key and tune), made on a worker thread while the one before plays.
## View-only: uses its own random numbers, never the simulation's.

const RATE := 16000                  # (lo-fi: a low sample rate is part of the sound, and quick to make)
const BPM := 72.0
const BARS := 16

# chord progressions, one chord per bar: [bass note, voicing] in MIDI notes (C major / A minor family)
const PROGS := [
	[[38, [53, 57, 60, 64]], [43, [53, 59, 64, 69]], [36, [52, 55, 59, 62]], [45, [55, 60, 64, 71]]],   # Dm9 G13 Cmaj9 Am9
	[[41, [52, 57, 60, 64]], [40, [55, 59, 62, 67]], [38, [53, 57, 60, 65]], [36, [52, 55, 59, 64]]],   # Fmaj7 Em7 Dm7 Cmaj7
	[[45, [55, 60, 64, 67]], [38, [53, 57, 60, 64]], [43, [53, 59, 62, 65]], [36, [52, 55, 59, 64]]],   # Am7 Dm9 G7 Cmaj7
	[[41, [52, 55, 57, 64]], [43, [53, 57, 59, 64]], [40, [55, 59, 62, 64]], [45, [55, 59, 60, 64]]],   # Fmaj9 G9sus Em7 Am(add9)
]
const PENTA := [72, 74, 76, 79, 81, 84]

var volume := 0.4:                   # 0..1 (the keeper's setting; 0 = off)
	set(v):
		volume = clampf(v, 0.0, 1.0)
		if _player != null:
			_player.volume_db = linear_to_db(maxf(volume, 0.0001) * 0.7)
			if volume <= 0.0:
				_player.stop()
			elif not _player.playing and _next != null:
				_play_next()
			elif not _player.playing and not _making:
				_make_next()

var _player: AudioStreamPlayer
var _next: AudioStreamWAV            # the piece made and waiting
var _making := false
var _task := -1                      # the worker making the next piece (waited for on exit)
var _done: PackedByteArray           # its result, picked up on the main thread
var _lock := Mutex.new()
var _seed := 0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_play_next)
	_seed = int(Time.get_unix_time_from_system()) % 100000
	volume = volume
	if volume > 0.0 and not _making:
		_make_next()


func _make_next() -> void:
	_making = true
	_seed += 1
	var s := _seed
	_task = WorkerThreadPool.add_task(func():
		var d := _compose(s)
		_lock.lock()
		_done = d
		_lock.unlock(), false, "lofi piece")


func _process(_delta: float) -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_lock.lock()
	var data := _done
	_done = PackedByteArray()
	_lock.unlock()
	_making = false
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	_next = w
	if volume > 0.0 and not _player.playing:
		_play_next()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)     # (quitting mid-piece must not leave it running)
		_task = -1


func _play_next() -> void:
	if _next == null or volume <= 0.0:
		return
	_player.stream = _next
	_next = null
	_player.play()
	_make_next()                     # the following piece is made while this one plays


## One piece as 16-bit samples (runs on a worker thread: touches nothing but its own arrays).
static func _compose(seed: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var beat := 60.0 / BPM
	var bar := beat * 4.0
	var n := int((bar * BARS + 2.0) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var prog: Array = PROGS[rng.randi() % PROGS.size()]
	var key := rng.randi_range(-3, 2)
	for b in BARS:
		var t0 := b * bar
		var ch: Array = prog[b % 4]
		var last_bar := b == BARS - 1
		# chords: a soft strum on the one, sometimes a quieter touch on the "and" of two
		for k in (ch[1] as Array).size():
			var m: int = ch[1][k] + key
			_piano(buf, t0 + k * 0.018 + rng.randf() * 0.01, _hz(m), bar * (1.6 if last_bar else 1.0), 0.075)
			if not last_bar and rng.randf() < 0.35:
				_piano(buf, t0 + beat * 1.5 + k * 0.014, _hz(m), beat * 2.0, 0.035)
		# bass: root on the one, root or fifth on the "and" of three
		var root: int = ch[0] + key
		_bass(buf, t0, _hz(root), beat * 2.2, 0.26)
		if not last_bar:
			_bass(buf, t0 + beat * 2.5, _hz(root + (7 if rng.randf() < 0.4 else 0)), beat * 1.4, 0.2)
		# drums (from the second bar; the last bar only the kick)
		if b > 0:
			_kick(buf, t0, 0.42)
			if not last_bar:
				_kick(buf, t0 + beat * 2.5, 0.32)
				_snare(buf, t0 + beat, 0.16, rng)
				_snare(buf, t0 + beat * 3.0, 0.16, rng)
				for e in 8:                                  # swung eighth-note hats
					var swing := 0.16 * beat if e % 2 == 1 else 0.0
					_hat(buf, t0 + e * beat * 0.5 + swing, 0.03 + rng.randf() * 0.025, rng)
		# a sparse tune over the chords
		if b >= 4 and not last_bar and rng.randf() < 0.6:
			for j in rng.randi_range(1, 3):
				var pos := rng.randi_range(0, 7) * beat * 0.5
				_bell(buf, t0 + pos, _hz(PENTA[rng.randi() % PENTA.size()] + key), beat * 1.5, 0.05)
	# vinyl: a faint hiss and the odd crackle
	for i in n:
		buf[i] += rng.randf_range(-1.0, 1.0) * 0.004
	for c in int(n / RATE * 5):
		var i := rng.randi_range(0, n - 4)
		var a := rng.randf_range(0.02, 0.09) * (1.0 if rng.randf() < 0.5 else -1.0)
		buf[i] += a
		buf[i + 1] -= a * 0.6
		buf[i + 2] += a * 0.25
	# warm it: a gentle low-pass, fade in and out, and level it
	var lp := 1.0 - exp(-TAU * 2600.0 / RATE)
	var y := 0.0
	var peak := 0.001
	for i in n:
		y += (buf[i] - y) * lp
		buf[i] = y
		peak = maxf(peak, absf(y))
	var gain := 0.8 / peak
	var fade_in := int(RATE * 0.6)
	var fade_out := int(RATE * 2.0)
	var out := PackedByteArray()
	out.resize(n * 2)
	for i in n:
		var g := gain * minf(1.0, float(i) / fade_in) * minf(1.0, float(n - i) / fade_out)
		out.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32000.0))
	return out


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## An electric-piano note: a sine with a fading bell overtone, a slow tremolo, and a release.
static func _piano(buf: PackedFloat32Array, at: float, f: float, dur: float, amp: float) -> void:
	var i0 := int(at * RATE)
	var len := int((dur + 0.4) * RATE)
	var rel := int(dur * RATE)
	for i in len:
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		var env := minf(1.0, t * 150.0) * exp(-t * 1.1)
		if i > rel:
			env *= 1.0 - float(i - rel) / (len - rel)
		var ph := TAU * f * t
		var v := sin(ph) + 0.28 * sin(ph * 2.0) * exp(-t * 3.0) + 0.06 * sin(ph * 3.0 + 0.3) * exp(-t * 6.0)
		buf[i0 + i] += v * env * amp * (1.0 + 0.12 * sin(TAU * 4.2 * t))


## A soft high bell for the tune.
static func _bell(buf: PackedFloat32Array, at: float, f: float, dur: float, amp: float) -> void:
	var i0 := int(at * RATE)
	for i in int(dur * RATE):
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		var env := minf(1.0, t * 90.0) * exp(-t * 2.4)
		buf[i0 + i] += (sin(TAU * f * t) + 0.15 * sin(TAU * f * 3.0 * t) * exp(-t * 8.0)) * env * amp


static func _bass(buf: PackedFloat32Array, at: float, f: float, dur: float, amp: float) -> void:
	var i0 := int(at * RATE)
	var len := int(dur * RATE)
	for i in len:
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		var env := minf(1.0, t * 60.0) * exp(-t * 1.4) * minf(1.0, float(len - i) / (RATE * 0.05))
		buf[i0 + i] += (sin(TAU * f * t) + 0.18 * sin(TAU * f * 2.0 * t)) * env * amp


static func _kick(buf: PackedFloat32Array, at: float, amp: float) -> void:
	var i0 := int(at * RATE)
	var ph := 0.0
	for i in int(0.35 * RATE):
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		ph += TAU * (46.0 + 80.0 * exp(-t * 28.0)) / RATE
		buf[i0 + i] += sin(ph) * exp(-t * 9.0) * amp


## A brushed snare: soft noise with a little body.
static func _snare(buf: PackedFloat32Array, at: float, amp: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(at * RATE)
	var y := 0.0
	for i in int(0.22 * RATE):
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.45
		buf[i0 + i] += (y * exp(-t * 16.0) + 0.5 * sin(TAU * 185.0 * t) * exp(-t * 22.0)) * amp


static func _hat(buf: PackedFloat32Array, at: float, amp: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(at * RATE)
	var last := 0.0
	for i in int(0.05 * RATE):
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		buf[i0 + i] += (x - last) * exp(-t * 70.0) * amp       # (high-passed noise)
		last = x
