extends Node
## Global EventBus Autoload (GDD Section 12.5).
## Decouples all core systems (Calendar, Combat pipelines, Anatomy, Floor transitions, Penetration logs).

# Calendar & World Degradation Signals (GDD 10.1, 10.2, 12.1)
@warning_ignore("unused_signal")
signal hour_changed(hour: int)
@warning_ignore("unused_signal")
signal day_passed(total_day: int)
@warning_ignore("unused_signal")
signal world_stage_changed(stage: int)
@warning_ignore("unused_signal")
signal blood_moon_changed(active: bool)
@warning_ignore("unused_signal")
signal time_acceleration_interrupted(reason: String)

# Interceptable Mutable Pipelines (GDD 12.5 - allows future MindDomains / buffs to modify or cancel rules)
signal damage_pipeline(context: Dictionary)
signal heal_pipeline(context: Dictionary)
signal control_input_pipeline(context: Dictionary)

# Anatomy, Knockout, Dismemberment & Death Signals (GDD 3.4, 12.4)
@warning_ignore("unused_signal")
signal wound_inflicted(entity: Node, zone: StringName, wound: WoundResource)
@warning_ignore("unused_signal")
signal limb_severed(entity: Node, zone: StringName, attacker: Node)
@warning_ignore("unused_signal")
signal limb_regrown(entity: Node, zone: StringName)
@warning_ignore("unused_signal")
signal organ_reconstructed(entity: Node, zone: StringName)
@warning_ignore("unused_signal")
signal weapon_lodged(entity: Node, zone: StringName, weapon: WeaponData, attacker: Node)
@warning_ignore("unused_signal")
signal weapon_dislodged(entity: Node, zone: StringName, weapon: WeaponData)
@warning_ignore("unused_signal")
signal weapon_dropped(entity: Node, zone: StringName, weapon: WeaponData)
@warning_ignore("unused_signal")
signal anti_regen_applied(entity: Node, zone: StringName, duration_sec: float)
@warning_ignore("unused_signal")
signal entity_knocked_out(entity: Node, reason: String, duration_sec: float)
@warning_ignore("unused_signal")
signal entity_recovered_consciousness(entity: Node)
@warning_ignore("unused_signal")
signal entity_died(entity: Node, cause: String, zone: StringName)

# TempoMode, Hitstop, Combat, Sensory & Game Feel Telemetry (GDD 2.3, 7.2, 7.4, 12.1, 12.2, 14.1, 14.3)
@warning_ignore("unused_signal")
signal tempo_mode_changed(old_mode: int, new_mode: int, reason: String)
@warning_ignore("unused_signal")
signal hitstop_triggered(duration_sec: float, source: Node, target: Node)
@warning_ignore("unused_signal")
signal camera_shake_requested(intensity_px: float, duration_sec: float)
@warning_ignore("unused_signal")
signal spark_effect_requested(world_pos: Vector2, floor_level: int, height_z: float, color: Color, count: int)
@warning_ignore("unused_signal")
signal blood_effect_requested(world_pos: Vector2, floor_level: int, direction: Vector2, amount: float, is_trail: bool)
@warning_ignore("unused_signal")
signal noise_emitted(world_pos: Vector2, floor_level: int, radius_px: float, source: Node)
signal sound_effect_requested(cue_id: StringName, intensity: float, pitch_scale: float)
signal blade_clashed(clash_data: Dictionary)
signal wall_slammed(entity: Node, cell: Vector2i, impulse: float, wall_broken: bool)
signal penetration_resolved(log_data: Dictionary)
signal combat_outcome_logged(outcome_data: Dictionary)
signal debug_highlight_weak_points_changed(enabled: bool)
signal debug_anti_regen_attacks_changed(enabled: bool)

# Spatial / Floor Signals (GDD 12.6, 12.7)
@warning_ignore("unused_signal")
signal floor_changed(entity: Node, old_floor: int, new_floor: int)
@warning_ignore("unused_signal")
signal floor_tile_broken(floor_level: int, cell: Vector2i)

var last_penetration_log: Dictionary = {}
var last_combat_outcome: Dictionary = {}
var last_blade_clash: Dictionary = {}
var debug_highlight_weak_points: bool = false
var debug_anti_regen_attacks: bool = false


func run_damage_pipeline(context: Dictionary) -> Dictionary:
	if not context.has("cancelled"):
		context["cancelled"] = false
	damage_pipeline.emit(context)
	return context


func run_heal_pipeline(context: Dictionary) -> Dictionary:
	if not context.has("cancelled"):
		context["cancelled"] = false
	heal_pipeline.emit(context)
	return context


func run_control_input_pipeline(context: Dictionary) -> Dictionary:
	if not context.has("cancelled"):
		context["cancelled"] = false
	control_input_pipeline.emit(context)
	return context


func publish_penetration_log(log_data: Dictionary) -> void:
	last_penetration_log = log_data.duplicate(true)
	penetration_resolved.emit(last_penetration_log)


func publish_combat_outcome(outcome_data: Dictionary) -> void:
	last_combat_outcome = outcome_data.duplicate()
	combat_outcome_logged.emit(last_combat_outcome)


func publish_blade_clash(clash_data: Dictionary) -> void:
	last_blade_clash = clash_data.duplicate(true)
	blade_clashed.emit(last_blade_clash)


func publish_wall_slam(entity: Node, cell: Vector2i, impulse: float, wall_broken: bool) -> void:
	wall_slammed.emit(entity, cell, impulse, wall_broken)


func request_camera_shake(intensity_px: float, duration_sec: float = 0.16) -> void:
	camera_shake_requested.emit(intensity_px, duration_sec)


func request_sparks(
	world_pos: Vector2,
	floor_level: int,
	height_z: float = 0.0,
	color: Color = Color("#FFE875"),
	count: int = 6
) -> void:
	spark_effect_requested.emit(world_pos, floor_level, height_z, color, count)


func request_blood(
	world_pos: Vector2,
	floor_level: int,
	direction: Vector2 = Vector2.RIGHT,
	amount: float = 1.0,
	is_trail: bool = false
) -> void:
	blood_effect_requested.emit(world_pos, floor_level, direction, amount, is_trail)


func emit_noise(world_pos: Vector2, floor_level: int, radius_px: float, source: Node = null) -> void:
	noise_emitted.emit(world_pos, floor_level, radius_px, source)


func request_sfx(cue_id: StringName, intensity: float = 1.0, pitch_scale: float = 1.0) -> void:
	sound_effect_requested.emit(cue_id, intensity, pitch_scale)


func set_debug_highlight_weak_points(enabled: bool) -> void:
	if debug_highlight_weak_points == enabled:
		return
	debug_highlight_weak_points = enabled
	debug_highlight_weak_points_changed.emit(enabled)


func set_debug_anti_regen_attacks(enabled: bool) -> void:
	if debug_anti_regen_attacks == enabled:
		return
	debug_anti_regen_attacks = enabled
	debug_anti_regen_attacks_changed.emit(enabled)
