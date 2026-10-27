extends RefCounted
## A soft two-note chime made in code (no sound file): the keeper's warning that a colony's sugar or protein is running
## out (the keeper, 2026-10-27: "a sound too - from code is fine"; hud_controls._refresh_food_warn, game/home.gd). A
## bell-like tone - a sine with two quieter overtones, a quick rise and a long fade - on E5 then A5.

const RATE := 22050
static var _stream: AudioStreamWAV


static func stream() -> AudioStreamWAV:
	if _stream != null:
		return _stream
	var notes := [[659.25, 0.0], [880.0, 0.18]]             # (Hz, start s)
	var length := 1.4
	var n := int(RATE * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for nt in notes:
			var u: float = t - float(nt[1])
			if u < 0.0:
				continue
			var env := minf(1.0, u / 0.008) * exp(-u * 3.2)
			var f: float = nt[0]
			v += env * (sin(TAU * f * u) + 0.35 * sin(TAU * f * 2.0 * u) * exp(-u * 4.0) + 0.12 * sin(TAU * f * 3.01 * u) * exp(-u * 6.0))
		data.encode_s16(i * 2, int(clampf(v * 0.28, -1.0, 1.0) * 32767.0))
	_stream = AudioStreamWAV.new()
	_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_stream.mix_rate = RATE
	_stream.stereo = false
	_stream.data = data
	return _stream


## Plays it once under `parent` (the player frees itself), at `volume` 0..1 (the keeper's music volume).
static func play(parent: Node, volume := 0.8) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream()
	p.volume_db = linear_to_db(clampf(volume, 0.05, 1.0)) - 4.0
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
