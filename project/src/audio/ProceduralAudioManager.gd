class_name ProceduralAudioManager
extends Node
## Zero-Asset Procedural Combat Audio Manager (v0.2 Game Feel).
## Synthesizes short 16-bit mono PCM AudioStreamWAV buffers strictly in memory (zero .wav/.ogg files),
## subscribes exclusively to EventBus signals, and degrades cleanly in --headless test runs.

signal cue_played(cue_id: StringName, pitch_scale: float, volume_db: float)

const SAMPLE_RATE: int = 22050
const VOICE_POOL_SIZE: int = 8

const CUE_SWING_WHOOSH: StringName = &"swing_whoosh"
const CUE_FLESH_HIT: StringName = &"flesh_hit"
const CUE_METAL_CLASH: StringName = &"metal_clash"
const CUE_BLOCK_CLANK: StringName = &"block_clank"
const CUE_BONE_CRUNCH: StringName = &"bone_crunch"
const CUE_WALL_BREAK: StringName = &"wall_break"
const CUE_AURA_BURST: StringName = &"aura_burst"
const CUE_WEAPON_DROP: StringName = &"weapon_drop"

var is_headless_mode: bool = false
var muted: bool = false
var master_volume_db: float = -6.0
var last_played_cue: StringName = &""
var played_cue_count: int = 0

var _clips: Dictionary[StringName, AudioStreamWAV] = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice_index: int = 0
var _initialized: bool = false


func _ready() -> void:
	initialize_audio()
	_connect_event_bus()


func _exit_tree() -> void:
	_disconnect_event_bus()


func initialize_audio() -> void:
	if _initialized:
		return
	_initialized = true
	is_headless_mode = (DisplayServer.get_name() == "headless")
	_synthesize_all_clips()
	if not is_headless_mode and AudioServer.get_bus_count() > 0:
		_build_voice_pool()


func get_registered_cues() -> Array[StringName]:
	var cues: Array[StringName] = []
	for k: StringName in _clips.keys():
		cues.append(k)
	return cues


func get_clip(cue_id: StringName) -> AudioStreamWAV:
	return _clips.get(cue_id, null)


func play_cue(cue_id: StringName, intensity: float = 1.0, pitch_scale: float = 1.0) -> bool:
	if muted or not _clips.has(cue_id):
		return false
	var clamped_int: float = clampf(intensity, 0.15, 1.8)
	var clamped_pitch: float = clampf(pitch_scale, 0.55, 1.75)
	var vol_db: float = master_volume_db + linear_to_db(clamped_int)
	last_played_cue = cue_id
	played_cue_count += 1
	cue_played.emit(cue_id, clamped_pitch, vol_db)

	if is_headless_mode or _players.is_empty():
		return true

	var player: AudioStreamPlayer = _players[_next_voice_index]
	_next_voice_index = (_next_voice_index + 1) % _players.size()
	player.stream = _clips[cue_id]
	player.pitch_scale = clamped_pitch * randf_range(0.95, 1.05)
	player.volume_db = clampf(vol_db, -30.0, 2.0)
	player.play()
	return true


func _build_voice_pool() -> void:
	for p: AudioStreamPlayer in _players:
		if is_instance_valid(p):
			p.queue_free()
	_players.clear()
	for i: int in range(VOICE_POOL_SIZE):
		var asp: AudioStreamPlayer = AudioStreamPlayer.new()
		asp.name = "Voice_%d" % i
		asp.bus = &"Master"
		add_child(asp)
		_players.append(asp)


# ---------------------------------------------------------------------------
# EventBus Subscriptions (Zero Entity Coupling)
# ---------------------------------------------------------------------------

func _connect_event_bus() -> void:
	if EventBus == null:
		return
	if not EventBus.sound_effect_requested.is_connected(_on_sfx_requested):
		EventBus.sound_effect_requested.connect(_on_sfx_requested)
	if not EventBus.combat_outcome_logged.is_connected(_on_combat_outcome_logged):
		EventBus.combat_outcome_logged.connect(_on_combat_outcome_logged)
	if not EventBus.blade_clashed.is_connected(_on_blade_clashed):
		EventBus.blade_clashed.connect(_on_blade_clashed)
	if not EventBus.wall_slammed.is_connected(_on_wall_slammed):
		EventBus.wall_slammed.connect(_on_wall_slammed)
	if not EventBus.limb_severed.is_connected(_on_limb_severed):
		EventBus.limb_severed.connect(_on_limb_severed)
	if not EventBus.floor_tile_broken.is_connected(_on_floor_tile_broken):
		EventBus.floor_tile_broken.connect(_on_floor_tile_broken)
	if not EventBus.weapon_dropped.is_connected(_on_weapon_dropped):
		EventBus.weapon_dropped.connect(_on_weapon_dropped)


func _disconnect_event_bus() -> void:
	if EventBus == null:
		return
	if EventBus.sound_effect_requested.is_connected(_on_sfx_requested):
		EventBus.sound_effect_requested.disconnect(_on_sfx_requested)
	if EventBus.combat_outcome_logged.is_connected(_on_combat_outcome_logged):
		EventBus.combat_outcome_logged.disconnect(_on_combat_outcome_logged)
	if EventBus.blade_clashed.is_connected(_on_blade_clashed):
		EventBus.blade_clashed.disconnect(_on_blade_clashed)
	if EventBus.wall_slammed.is_connected(_on_wall_slammed):
		EventBus.wall_slammed.disconnect(_on_wall_slammed)
	if EventBus.limb_severed.is_connected(_on_limb_severed):
		EventBus.limb_severed.disconnect(_on_limb_severed)
	if EventBus.floor_tile_broken.is_connected(_on_floor_tile_broken):
		EventBus.floor_tile_broken.disconnect(_on_floor_tile_broken)
	if EventBus.weapon_dropped.is_connected(_on_weapon_dropped):
		EventBus.weapon_dropped.disconnect(_on_weapon_dropped)


func _on_sfx_requested(cue_id: StringName, intensity: float, pitch_scale: float) -> void:
	play_cue(cue_id, intensity, pitch_scale)


func _on_combat_outcome_logged(outcome_data: Dictionary) -> void:
	var outcome: String = String(outcome_data.get("outcome", ""))
	match outcome:
		"parried":
			play_cue(CUE_METAL_CLASH, 1.10, 1.18)
		"blocked":
			play_cue(CUE_BLOCK_CLANK, 0.95, 1.0)
		"no_penetration", "hardening_bounce":
			play_cue(CUE_BLOCK_CLANK, 0.85, 0.82)
		"guard_break_hit":
			play_cue(CUE_BONE_CRUNCH, 1.20, 0.92)
		"dismembered":
			play_cue(CUE_BONE_CRUNCH, 1.30, 0.85)
		"penetrated", "hardening_lodged", "weapon_lodged", "imperceptible_speed_fatal":
			var is_wp: bool = bool(outcome_data.get("is_weak_point", false))
			play_cue(CUE_FLESH_HIT, 1.20 if is_wp else 0.95, 1.08 if is_wp else 0.96)


func _on_blade_clashed(_clash_data: Dictionary) -> void:
	play_cue(CUE_METAL_CLASH, 1.25, 1.0)


func _on_wall_slammed(_entity: Node, _cell: Vector2i, _impulse: float, wall_broken: bool) -> void:
	if wall_broken:
		play_cue(CUE_WALL_BREAK, 1.25, 0.95)
	else:
		play_cue(CUE_BONE_CRUNCH, 1.15, 0.80)


func _on_limb_severed(_entity: Node, _zone: StringName, _attacker: Node) -> void:
	play_cue(CUE_BONE_CRUNCH, 1.25, 0.88)


func _on_floor_tile_broken(_floor_level: int, _cell: Vector2i) -> void:
	play_cue(CUE_WALL_BREAK, 1.15, 0.88)


func _on_weapon_dropped(_entity: Node, _zone: StringName, _weapon: WeaponData) -> void:
	play_cue(CUE_WEAPON_DROP, 0.85, 1.05)


# ---------------------------------------------------------------------------
# Deterministic In-Memory 16-bit PCM Synthesis (AudioStreamWAV)
# ---------------------------------------------------------------------------

func _synthesize_all_clips() -> void:
	_clips.clear()
	_clips[CUE_SWING_WHOOSH] = _synth_whoosh(0.14)
	_clips[CUE_FLESH_HIT] = _synth_flesh_hit(0.13)
	_clips[CUE_METAL_CLASH] = _synth_metal_clash(0.26)
	_clips[CUE_BLOCK_CLANK] = _synth_block_clank(0.15)
	_clips[CUE_BONE_CRUNCH] = _synth_bone_crunch(0.18)
	_clips[CUE_WALL_BREAK] = _synth_wall_break(0.30)
	_clips[CUE_AURA_BURST] = _synth_aura_burst(0.26)
	_clips[CUE_WEAPON_DROP] = _synth_weapon_drop(0.15)


func _build_wav_from_samples(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var byte_buf: PackedByteArray = PackedByteArray()
	byte_buf.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		var v: int = clampi(int(roundf(clampf(samples[i], -1.0, 1.0) * 32767.0)), -32768, 32767)
		var u: int = v if v >= 0 else (v + 65536)
		byte_buf[i * 2] = u & 0xFF
		byte_buf[i * 2 + 1] = (u >> 8) & 0xFF
	wav.data = byte_buf
	return wav


func _synth_whoosh(duration_sec: float) -> AudioStreamWAV:
	var n: int = maxi(1, int(duration_sec * float(SAMPLE_RATE)))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1001
	var lp: float = 0.0
	var hp_prev: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / float(n)
		var env: float = sin(t * PI) * pow(1.0 - t * 0.45, 1.2)
		var raw: float = rng.randf_range(-1.0, 1.0)
		var alpha: float = lerpf(0.08, 0.32, sin(t * PI))
		lp = lp + alpha * (raw - lp)
		var band: float = lp - hp_prev * 0.65
		hp_prev = lp
		out[i] = band * env * 0.65
	return _build_wav_from_samples(out)


func _synth_flesh_hit(duration_sec: float) -> AudioStreamWAV:
	var n: int = maxi(1, int(duration_sec * float(SAMPLE_RATE)))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2002
	var phase: float = 0.0
	var lp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / float(n)
		var freq: float = lerpf(135.0, 42.0, pow(t, 0.55))
		phase += TAU * freq / float(SAMPLE_RATE)
		var thud: float = sin(phase) * exp(-t * 10.5)
		var raw_n: float = rng.randf_range(-1.0, 1.0)
		lp = lp + 0.28 * (raw_n - lp)
		var wet: float = lp * exp(-t * 16.0) * 0.75
		out[i] = (thud * 0.85 + wet) * 0.80
	return _build_wav_from_samples(out)


func _synth_metal_clash(duration_sec: float) -> AudioStreamWAV:
	var n: int = maxi(1, int(duration_sec * float(SAMPLE_RATE)))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3003
	var freqs: Array[float] = [1180.0, 1745.0, 2690.0, 3910.0]
	var weights: Array[float] = [0.42, 0.30, 0.20, 0.14]
	for i: int in range(n):
		var sec: float = float(i) / float(SAMPLE_RATE)
		var t: float = float(i) / float(n)
		var ring: float = 0.0
		for k: int in range(freqs.size()):
			var decay: float = exp(-t * (4.5 + float(k) * 2.2))
			ring += sin(TAU * freqs[k] * sec) * weights[k] * decay
		var transient: float = rng.randf_range(-1.0, 1.0) * exp(-t * 42.0) * 0.55
		out[i] = (ring + transient) * 0.72
	return _build_wav_from_samples(out)


func _synth_block_clank(duration_sec: float) -> AudioStreamWAV:
	var n: int = maxi(1, int(duration_sec * float(SAMPLE_RATE)))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4004
	for i: int in range(n):
		var sec: float = float(i) / float(SAMPLE_RATE)
		var t: float = float(i) / float(n)
		var clank: float = (
			sin(TAU * 840.0 * sec) * 0.45
			+ sin(TAU * 1470.0 * sec) * 0.30
			+ sin(TAU * 2210.0 * sec) * 0.18
		) * exp(-t * 11.0)
		var click: float = rng.randf_range(-1.0, 1.0) * exp(-t * 36.0) * 0.50
		out[i] = (clank + click) * 0.75
	return _build_wav_from_samples(out)


func _synth_bone_crunch(duration_sec: float) -> AudioStreamWAV:
	var n: int = maxi(1, int(duration_sec * float(SAMPLE_RATE)))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5005
	var phase: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / float(n)
		var freq: float = lerpf(160.0, 50.0, t)
		phase += TAU * freq / float(SAMPLE_RATE)
		var snap1: float = exp(-t * 18.0)
		var snap2: float = exp(-maxf(0.0, t - 0.18) * 22.0) if t >= 0.18 else 0.0
		var crackle: float = rng.randf_range(-1.0, 1.0) * (snap1 * 0.75 + snap2 * 0.55)
		var impact: float = sin(phase) * exp(-t * 9.0) * 0.65
		out[i] = (impact + crackle) * 0.78
	return _build_wav_from_samples(out)


func _synth_wall_break(duration_sec: float) -> AudioStreamWAV:
	var n: int = maxi(1, int(duration_sec * float(SAMPLE_RATE)))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 6006
	var phase: float = 0.0
	var lp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / float(n)
		var freq: float = lerpf(92.0, 28.0, pow(t, 0.7))
		phase += TAU * freq / float(SAMPLE_RATE)
		var boom: float = sin(phase) * exp(-t * 5.2) * 0.78
		var raw_n: float = rng.randf_range(-1.0, 1.0)
		lp = lp + 0.18 * (raw_n - lp)
		var debris: float = (lp * 0.75 + raw_n * 0.25) * exp(-t * 6.5) * 0.65
		out[i] = (boom + debris) * 0.80
	return _build_wav_from_samples(out)


func _synth_aura_burst(duration_sec: float) -> AudioStreamWAV:
	var n: int = maxi(1, int(duration_sec * float(SAMPLE_RATE)))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var p1: float = 0.0
	var p2: float = 0.0
	var p3: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / float(n)
		var f1: float = lerpf(210.0, 620.0, pow(t, 0.65))
		p1 += TAU * f1 / float(SAMPLE_RATE)
		p2 += TAU * (f1 * 1.5) / float(SAMPLE_RATE)
		p3 += TAU * (f1 * 2.01) / float(SAMPLE_RATE)
		var attack: float = minf(1.0, t / 0.08)
		var decay: float = exp(-maxf(0.0, t - 0.08) * 5.5)
		var env: float = attack * decay
		out[i] = (sin(p1) * 0.50 + sin(p2) * 0.30 + sin(p3) * 0.20) * env * 0.72
	return _build_wav_from_samples(out)


func _synth_weapon_drop(duration_sec: float) -> AudioStreamWAV:
	var n: int = maxi(1, int(duration_sec * float(SAMPLE_RATE)))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i: int in range(n):
		var sec: float = float(i) / float(SAMPLE_RATE)
		var t: float = float(i) / float(n)
		var bounce1: float = exp(-t * 20.0)
		var bounce2: float = exp(-maxf(0.0, t - 0.35) * 24.0) * 0.55 if t >= 0.35 else 0.0
		var tone: float = sin(TAU * 1380.0 * sec) * 0.55 + sin(TAU * 2140.0 * sec) * 0.35
		out[i] = tone * (bounce1 + bounce2) * 0.65
	return _build_wav_from_samples(out)
