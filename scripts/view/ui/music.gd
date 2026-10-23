extends Node
## Background music: the keeper's two pieces (assets/audio/music/, made with Gemini - the keeper, 2026-10-24), played
## one after the other, over and over. Replaces the pieces made in code (ui/lofi.gd, until v0.11.30).

const TRACKS := ["res://assets/audio/music/bg1_where_the_tall_trees_lean.mp3",
	"res://assets/audio/music/bg2_under_the_canopy.mp3"]

var volume := 0.4:                   # 0..1 (the keeper's setting; 0 = off)
	set(v):
		volume = clampf(v, 0.0, 1.0)
		if _player != null:
			_player.volume_db = linear_to_db(maxf(volume, 0.0001))
			if volume <= 0.0:
				_player.stop()
			elif not _player.playing:
				_play(_at)

var _player: AudioStreamPlayer
var _at := 0                         # the track playing (or next to play)


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(func(): _play((_at + 1) % TRACKS.size()))
	volume = volume


func _play(i: int) -> void:
	if volume <= 0.0:
		return
	_at = i
	var s = load(TRACKS[i])
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = false   # (each once, then the other)
	_player.stream = s
	_player.play()
