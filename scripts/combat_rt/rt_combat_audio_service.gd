class_name RTCombatAudioService
extends RefCounted

var _audio_player: AudioStreamPlayer = null

func setup(owner: Node) -> void:
	if owner == null:
		return
	_audio_player = AudioStreamPlayer.new()
	_audio_player.volume_db = -18.0
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.12
	_audio_player.stream = stream
	owner.add_child(_audio_player)
	_audio_player.play()

func play(kind: String) -> void:
	if _audio_player == null:
		return
	var playback := _audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var cue := _cue(kind)
	var frequency: float = float(cue.get("frequency", 280.0))
	var duration: float = float(cue.get("duration", 0.045))
	var volume: float = float(cue.get("volume", 0.055))
	var mix_rate := 22050.0
	var frame_count := int(mix_rate * duration)
	for i in range(frame_count):
		var t := float(i) / mix_rate
		var fade := 1.0 - float(i) / float(maxi(1, frame_count))
		var sample := sin(t * frequency * TAU) * volume * fade
		playback.push_frame(Vector2(sample, sample))

func play_music(mode: String) -> void:
	var notes: Array[float] = []
	match mode:
		"tower":
			notes = [146.0, 196.0, 233.0, 196.0]
		"raid":
			notes = [110.0, 165.0, 196.0, 147.0]
		_:
			notes = [130.0, 174.0, 196.0, 174.0]
	for note in notes:
		_play_note(note, 0.18, 0.018)

func _play_note(frequency: float, duration: float, volume: float) -> void:
	if _audio_player == null:
		return
	var playback := _audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var mix_rate := 22050.0
	var frame_count := int(mix_rate * duration)
	for i in range(frame_count):
		var t := float(i) / mix_rate
		var fade_in := minf(1.0, float(i) / float(maxi(1, frame_count / 5)))
		var fade_out := 1.0 - float(i) / float(maxi(1, frame_count))
		var sample := sin(t * frequency * TAU) * volume * fade_in * fade_out
		playback.push_frame(Vector2(sample, sample))

func _cue(kind: String) -> Dictionary:
	match kind:
		"battle_start":
			return {"frequency": 220.0, "duration": 0.11, "volume": 0.035}
		"attack":
			return {"frequency": 360.0, "duration": 0.035, "volume": 0.055}
		"hit":
			return {"frequency": 130.0, "duration": 0.05, "volume": 0.075}
		"death":
			return {"frequency": 82.0, "duration": 0.18, "volume": 0.072}
		"spell":
			return {"frequency": 520.0, "duration": 0.075, "volume": 0.05}
		"heal":
			return {"frequency": 660.0, "duration": 0.08, "volume": 0.042}
		"buff":
			return {"frequency": 470.0, "duration": 0.06, "volume": 0.04}
		"step_water":
			return {"frequency": 95.0, "duration": 0.035, "volume": 0.032}
		"step_door":
			return {"frequency": 180.0, "duration": 0.032, "volume": 0.04}
		"door":
			return {"frequency": 205.0, "duration": 0.06, "volume": 0.045}
		"victory":
			return {"frequency": 740.0, "duration": 0.14, "volume": 0.055}
		"defeat":
			return {"frequency": 105.0, "duration": 0.16, "volume": 0.06}
		_:
			return {"frequency": 280.0, "duration": 0.045, "volume": 0.055}
