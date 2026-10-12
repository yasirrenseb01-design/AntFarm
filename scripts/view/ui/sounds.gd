extends RefCounted
## Small sounds made in code (no audio files): a soft two-note chime for the keeper's warnings.


## A gentle chime: two bell-like sine notes (a falling fourth), each with a quick attack and a long fade.
static func chime() -> AudioStreamWAV:
	var rate := 22050
	var length := int(rate * 1.4)
	var data := PackedByteArray()
	data.resize(length * 2)
	for i in length:
		var t := float(i) / rate
		var v := 0.0
		for note in [[880.0, 0.0], [659.25, 0.28]]:
			var dt: float = t - note[1]
			if dt >= 0.0:
				var env := minf(1.0, dt * 80.0) * exp(-dt * 3.2)
				v += sin(TAU * note[0] * dt) * env * 0.35 + sin(TAU * note[0] * 2.0 * dt) * env * 0.08
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s
