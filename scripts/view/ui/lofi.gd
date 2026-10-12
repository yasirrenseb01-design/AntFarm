extends Node
## Background music made in code (no audio files): slow, easy lo-fi pieces, each ~58 s of 16 bars at 66 BPM -
## a warm pad, jazzy seventh/ninth chords on a soft electric piano, a round bass, a nylon guitar picking
## the chords, a breathy flute, a soft brushed beat (not always), and vinyl crackle, through a warm low-pass;
## and now and then a curious "nature film" piece (marimba, plucked and bowed strings; see _doc_piece). Each piece is new (its own chord
## progression, key and tune), made on a worker thread while the one before plays.
## View-only: uses its own random numbers, never the simulation's.

const RATE := 16000                  # (lo-fi: a low sample rate is part of the sound, and quick to make)
const BPM := 66.0
const BARS := 16

# chord progressions, one chord per bar: [bass note, voicing] in MIDI notes (C major / A minor family)
const PROGS := [
	[[38, [53, 57, 60, 64]], [43, [53, 59, 64, 69]], [36, [52, 55, 59, 62]], [45, [55, 60, 64, 71]]],   # Dm9 G13 Cmaj9 Am9
	[[41, [52, 57, 60, 64]], [40, [55, 59, 62, 67]], [38, [53, 57, 60, 65]], [36, [52, 55, 59, 64]]],   # Fmaj7 Em7 Dm7 Cmaj7
	[[45, [55, 60, 64, 67]], [38, [53, 57, 60, 64]], [43, [53, 59, 62, 65]], [36, [52, 55, 59, 64]]],   # Am7 Dm9 G7 Cmaj7
	[[41, [52, 55, 57, 64]], [43, [53, 57, 59, 64]], [40, [55, 59, 62, 64]], [45, [55, 59, 60, 64]]],   # Fmaj9 G9sus Em7 Am(add9)
]
const PENTA := [72, 74, 76, 79, 81, 84]
# the nature-film pieces: minor and suspended chords (Am9 Fmaj7#11 Dm9 E7sus4 / Dm9 Bbmaj7 Gm7 A7sus4)
const DOC_PROGS := [
	[[45, [55, 59, 60, 64]], [41, [52, 57, 59, 64]], [38, [53, 57, 60, 64]], [40, [52, 57, 59, 62]]],
	[[38, [53, 57, 60, 64]], [46, [53, 57, 62, 65]], [43, [53, 58, 62, 65]], [45, [55, 57, 62, 64]]],
]
const PENTA_MINOR := [69, 72, 74, 76, 79, 81]

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
## Arranged in four-bar sections so it breathes: it opens on the pad and the piano alone, the nylon guitar
## and a soft brushed beat come in, a breathy flute wanders over the second half, and it winds down to the
## pad again. About a third of the pieces have no beat at all.
static func _compose(seed: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var beat := 60.0 / BPM
	var bar := beat * 4.0
	var n := int((bar * BARS + 3.0) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	if rng.randf() < 0.4:
		_doc_piece(buf, rng, beat, bar)     # (about two in five: the curious, nature-film kind)
	else:
		var prog: Array = PROGS[rng.randi() % PROGS.size()]
		var key := rng.randi_range(-3, 2)
		var drums := rng.randf() < 0.65
		for b in BARS:
			var t0 := b * bar
			var ch: Array = prog[b % 4]
			var sec := b / 4                       # 0 intro, 1-2 middle, 3 outro
			var last_bar := b == BARS - 1
			var notes: Array = ch[1]
			# a warm pad under everything, two bars to a chord change (held over the bar line, slow in and out)
			_pad(buf, t0, notes.slice(0, 3).map(func(m): return _hz(m + key)), bar * (2.2 if last_bar else 1.15), 0.035)
			# electric piano: a soft spread chord on the one (quieter than before; it lets the others through)
			for k in notes.size():
				_piano(buf, t0 + k * 0.03 + rng.randf() * 0.012, _hz(notes[k] + key), bar * (1.6 if last_bar else 1.0), 0.05)
			# bass: long round notes
			var root: int = ch[0] + key
			_bass(buf, t0, _hz(root), beat * (3.8 if last_bar else 2.6), 0.22)
			if not last_bar and rng.randf() < 0.5:
				_bass(buf, t0 + beat * 3.0, _hz(root + 7), beat * 1.0, 0.13)
			# nylon guitar: a slow broken chord, up and back, in the middle sections
			if sec in [1, 2] and not last_bar:
				var arp := [notes[0], notes[1], notes[2], notes[3], notes[2], notes[1]]
				var start := rng.randi_range(0, 1)
				for e in range(start, 8):
					if rng.randf() < 0.82:
						_pluck(buf, t0 + e * beat * 0.5 + (0.1 * beat if e % 2 == 1 else 0.0), _hz(arp[e % arp.size()] + key + 12), 0.06, rng)
			# brushed beat, soft, in the middle sections only
			if drums and sec in [1, 2]:
				_kick(buf, t0, 0.26)
				_kick(buf, t0 + beat * 2.5, 0.18)
				_snare(buf, t0 + beat, 0.06, rng)
				_snare(buf, t0 + beat * 3.0, 0.06, rng)
				for e in 8:
					_hat(buf, t0 + e * beat * 0.5 + (0.16 * beat if e % 2 == 1 else 0.0), 0.012 + rng.randf() * 0.01, rng)
			# a breathy flute, a few long notes over the second half
			if b >= 6 and b < BARS - 2 and rng.randf() < 0.55:
				var pos := rng.randi_range(0, 3) * beat
				for j in rng.randi_range(1, 2):
					var len := beat * rng.randf_range(1.0, 2.5)
					_flute(buf, t0 + pos, _hz(PENTA[rng.randi() % PENTA.size()] + key), len, 0.05, rng)
					pos += len + beat * 0.5
	# vinyl: a faint hiss and the odd soft crackle
	for i in n:
		buf[i] += rng.randf_range(-1.0, 1.0) * 0.003
	for c in int(n / RATE * 3):
		var i := rng.randi_range(0, n - 4)
		var a := rng.randf_range(0.01, 0.05) * (1.0 if rng.randf() < 0.5 else -1.0)
		buf[i] += a
		buf[i + 1] -= a * 0.6
		buf[i + 2] += a * 0.25
	# warm it: a low-pass (darker than a plain mix), fade in and out, and level it
	var lp := 1.0 - exp(-TAU * 1900.0 / RATE)
	var y := 0.0
	var y2 := 0.0
	var peak := 0.001
	for i in n:
		y += (buf[i] - y) * lp
		y2 += (y - y2) * lp                   # (two poles: a gentler, rounder top end)
		buf[i] = y2
		peak = maxf(peak, absf(y2))
	var gain := 0.6 / peak                     # (the pad fills it out: kept as loud as the old pieces)
	var fade_in := int(RATE * 2.0)
	var fade_out := int(RATE * 3.0)
	var out := PackedByteArray()
	out.resize(n * 2)
	for i in n:
		var g := gain * minf(1.0, float(i) / fade_in) * minf(1.0, float(n - i) / fade_out)
		out.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32000.0))
	return out


## A "nature film" piece: curious rather than sleepy - minor and suspended chords, a marimba picking out a
## light bouncing figure, plucked strings walking underneath, a soft shaker, and a string section that
## swells in and out (the way a documentary score follows something small going about its business).
## Still slow and soft: it opens and closes on the strings alone.
static func _doc_piece(buf: PackedFloat32Array, rng: RandomNumberGenerator, beat: float, bar: float) -> void:
	var prog: Array = DOC_PROGS[rng.randi() % DOC_PROGS.size()]
	var key := rng.randi_range(-2, 2)
	var table := _string_table()
	# the marimba figure: one two-bar pattern for the whole piece (steps of an eighth note, -1 = rest)
	var fig := []
	for e in 16:
		fig.append(-1 if rng.randf() < 0.3 else rng.randi_range(0, 3))
	for b in BARS:
		var t0 := b * bar
		var ch: Array = prog[b % 4]
		var notes: Array = ch[1]
		var sec := b / 4
		var last_bar := b == BARS - 1
		# strings: the chord, swelling slowly in and out (louder in the middle of the piece)
		var swell := 0.03 if sec in [0, 3] else 0.042
		_strings(buf, t0, notes.slice(0, 3).map(func(m): return _hz(m + key)), bar * (2.4 if last_bar else 1.1), swell, table)
		# a low string drone on the root in the opening and closing bars
		if sec in [0, 3]:
			_strings(buf, t0, [_hz(ch[0] + key)], bar * (2.4 if last_bar else 1.1), 0.05, table)
		if sec in [1, 2] and not last_bar:
			# plucked strings walking under it: root, fifth, root an octave up, a step
			var walk := [0, 7, 12, 10]
			for q in 4:
				_pluck(buf, t0 + q * beat, _hz(ch[0] + key + walk[q] + 12), 0.08, rng, 0.47)
			# the marimba figure on the chord tones
			for e in 8:
				var step: int = fig[(b % 2) * 8 + e]
				if step >= 0:
					_marimba(buf, t0 + e * beat * 0.5 + (0.06 * beat if e % 2 == 1 else 0.0), _hz(notes[step] + key + 12), 0.05 + rng.randf() * 0.02)
			# shaker on the off-beats
			for e in 8:
				_hat(buf, t0 + e * beat * 0.5 + (0.12 * beat if e % 2 == 1 else 0.0), 0.006 + (0.006 if e % 2 == 1 else 0.0), rng)
		# a few long questioning notes on the flute in the second half
		if sec == 2 and rng.randf() < 0.7:
			var pos := rng.randi_range(0, 2) * beat
			_flute(buf, t0 + pos, _hz(PENTA_MINOR[rng.randi() % PENTA_MINOR.size()] + key), beat * rng.randf_range(1.5, 2.5), 0.05, rng)


## One cycle of a soft string tone (a few harmonics falling away), looked up instead of summing sines.
static func _string_table() -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(1024)
	for i in 1024:
		var ph := TAU * i / 1024.0
		t[i] = sin(ph) + 0.45 * sin(2.0 * ph) + 0.25 * sin(3.0 * ph) + 0.12 * sin(4.0 * ph) + 0.06 * sin(5.0 * ph)
	return t


## A string section: each note from the table with a slow vibrato, a long bow-in and bow-out.
static func _strings(buf: PackedFloat32Array, at: float, fs: Array, dur: float, amp: float, table: PackedFloat32Array) -> void:
	var i0 := int(at * RATE)
	var len := int((dur + 1.8) * RATE)
	var rel := int(dur * RATE)
	var att := RATE * 1.6
	var phs := []
	for f in fs:
		phs.append(0.0)
	for i in len:
		if i0 + i >= buf.size():
			return
		var env := minf(1.0, i / att)
		env *= env
		if i > rel:
			env *= 1.0 - float(i - rel) / (len - rel)
		var vib := 1.0 + 0.003 * sin(TAU * 5.2 * i / RATE)
		var v := 0.0
		for k in fs.size():
			phs[k] = fmod(phs[k] + fs[k] * vib * 1024.0 / RATE, 1024.0)
			v += table[int(phs[k])]
		buf[i0 + i] += v * env * amp


## A marimba note: a wooden bar's tone (the fundamental and its bright fourth harmonic, quickly gone).
static func _marimba(buf: PackedFloat32Array, at: float, f: float, amp: float) -> void:
	var i0 := int(at * RATE)
	for i in int(0.7 * RATE):
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		var ph := TAU * f * t
		buf[i0 + i] += (sin(ph) * exp(-t * 5.5) + 0.25 * sin(ph * 4.0) * exp(-t * 22.0)) * minf(1.0, t * 300.0) * amp


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## A pad: each note two slightly detuned sines, swelling in over a second and fading out slowly.
static func _pad(buf: PackedFloat32Array, at: float, fs: Array, dur: float, amp: float) -> void:
	var i0 := int(at * RATE)
	var len := int((dur + 1.5) * RATE)
	var att := RATE * 1.2
	var rel := int(dur * RATE)
	var w := []
	for f in fs:
		w.append([TAU * f / RATE, TAU * f * 1.004 / RATE])
	for i in len:
		if i0 + i >= buf.size():
			return
		var env := minf(1.0, i / att)
		if i > rel:
			env *= 1.0 - float(i - rel) / (len - rel)
		var v := 0.0
		for p in w:
			v += sin(p[0] * i) + sin(p[1] * i)
		buf[i0 + i] += v * env * amp


## A nylon-string pluck (Karplus-Strong: a burst of noise round a delay line, softened on every pass).
static func _pluck(buf: PackedFloat32Array, at: float, f: float, amp: float, rng: RandomNumberGenerator, keep := 0.4985) -> void:
	var p := maxi(2, int(RATE / f))
	var line := PackedFloat32Array()
	line.resize(p)
	var last := 0.0
	for k in p:
		var x := rng.randf_range(-1.0, 1.0)
		line[k] = (x + last) * 0.5                 # (a softer, rounder attack than raw noise)
		last = x
	var i0 := int(at * RATE)
	var len := int(2.2 * RATE)
	var k := 0
	for i in len:
		if i0 + i >= buf.size():
			return
		var nxt := (k + 1) % p
		var v := line[k]
		line[k] = keep * (v + line[nxt])          # (keep: how long it rings - nylon ~2 s, pizzicato short)
		buf[i0 + i] += v * amp
		k = nxt


## A breathy flute: a sine with a touch of its octave, a gentle vibrato once the note settles, and a
## little breath noise, slow to start and stop.
static func _flute(buf: PackedFloat32Array, at: float, f: float, dur: float, amp: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(at * RATE)
	var len := int((dur + 0.3) * RATE)
	var ph := 0.0
	var br := 0.0
	for i in len:
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.15) * minf(1.0, (len - i) / (RATE * 0.3))
		var vib := 1.0 + 0.004 * sin(TAU * 5.0 * t) * minf(1.0, maxf(0.0, t - 0.3) * 3.0)
		ph += TAU * f * vib / RATE
		br += (rng.randf_range(-1.0, 1.0) - br) * 0.08
		buf[i0 + i] += (sin(ph) + 0.12 * sin(ph * 2.0) + br * 0.35) * env * amp


## An electric-piano note: a sine with a fading bell overtone, a slow tremolo, and a release.
static func _piano(buf: PackedFloat32Array, at: float, f: float, dur: float, amp: float) -> void:
	var i0 := int(at * RATE)
	var len := int((dur + 0.6) * RATE)
	var rel := int(dur * RATE)
	for i in len:
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		var env := minf(1.0, t * 60.0) * exp(-t * 0.8)
		if i > rel:
			env *= 1.0 - float(i - rel) / (len - rel)
		var ph := TAU * f * t
		var v := sin(ph) + 0.22 * sin(ph * 2.0) * exp(-t * 3.0) + 0.04 * sin(ph * 3.0 + 0.3) * exp(-t * 6.0)
		buf[i0 + i] += v * env * amp * (1.0 + 0.1 * sin(TAU * 3.6 * t))


static func _bass(buf: PackedFloat32Array, at: float, f: float, dur: float, amp: float) -> void:
	var i0 := int(at * RATE)
	var len := int(dur * RATE)
	for i in len:
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		var env := minf(1.0, t * 30.0) * exp(-t * 0.9) * minf(1.0, float(len - i) / (RATE * 0.12))
		buf[i0 + i] += (sin(TAU * f * t) + 0.12 * sin(TAU * f * 2.0 * t)) * env * amp


static func _kick(buf: PackedFloat32Array, at: float, amp: float) -> void:
	var i0 := int(at * RATE)
	var ph := 0.0
	for i in int(0.35 * RATE):
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		ph += TAU * (44.0 + 55.0 * exp(-t * 25.0)) / RATE
		buf[i0 + i] += sin(ph) * exp(-t * 8.0) * minf(1.0, t * 400.0) * amp


## A brush across the snare: soft, slowly swelling noise.
static func _snare(buf: PackedFloat32Array, at: float, amp: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(at * RATE)
	var y := 0.0
	for i in int(0.3 * RATE):
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.3
		buf[i0 + i] += y * minf(1.0, t * 40.0) * exp(-t * 11.0) * amp


static func _hat(buf: PackedFloat32Array, at: float, amp: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(at * RATE)
	var last := 0.0
	for i in int(0.04 * RATE):
		if i0 + i >= buf.size():
			return
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		buf[i0 + i] += (x - last) * exp(-t * 80.0) * amp       # (high-passed noise)
		last = x
