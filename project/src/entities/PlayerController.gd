class_name PlayerController
extends CombatActor
## Player controller strictly driven by v0.2 InputMap (GDD Section 14.5), SimulationClock,
## StatSheet, AnatomyComponent, VerticalityComponent, and WeaponRaySweeper.
## Contains ZERO hardcoded enemy logic or direct stat mutations bypassing StatSheet.

const DAGGER_TEMPLATE_PATH: String = "res://data/dagger.tres"
const GREATSWORD_TEMPLATE_PATH: String = "res://data/greatsword.tres"
const WARHAMMER_TEMPLATE_PATH: String = "res://data/warhammer.tres"
const BASE_CAMERA_ZOOM: Vector2 = Vector2(1.0, 1.0)
const CAMERA_ZOOM_LERP_SPEED: float = 6.0
const CLINCH_HOLD_THRESHOLD_SEC: float = 0.22
const CAREFUL_EXTRACT_HOLD_SEC: float = 0.35
const STEALTH_DISTRACT_MAX_DIST_PX: float = 180.0
const STEALTH_DISTRACT_NOISE_RADIUS_PX: float = 170.0
const STEALTH_DISTRACT_COOLDOWN_SEC: float = 0.75

var weapon_slots: Array[WeaponData] = []
var _initial_weapon_templates: Array[WeaponData] = []
var active_weapon_index: int = 0

var camera: Camera2D = null
var flash_layer: CanvasLayer = null
var flash_rect: ColorRect = null
var interact_prompt_label: Label = null
var takedown_prompt_label: Label = null
var last_interact_prompt: Dictionary = {"visible": false, "action": &"", "text": ""}
var last_takedown_prompt: Dictionary = {"visible": false, "target": null, "text": ""}
var _distract_cooldown_timer: float = 0.0
var _flash_tween: Tween = null
var _drift_velocity: Vector2 = Vector2.ZERO
var _clinch_key_held: bool = false
var _clinch_hold_elapsed: float = 0.0
var _clinch_triggered_while_held: bool = false
var _interact_key_held: bool = false
var _interact_hold_elapsed: float = 0.0
var _interact_triggered_while_held: bool = false
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0
var _shake_phase: float = 0.0


func _ready() -> void:
	actor_display_name = "Player"
	actor_body_color = Color("#3498DB")
	visual_style = VisualStyle.PLAYER_ADVENTURER
	actor_size_mult = 1.0
	actor_base_anatomy_thickness = PenetrationResolver.DEFAULT_BASE_ANATOMY_THICKNESS
	actor_bone_density = 100.0
	enable_instinct_dodge = true

	# Human template per GDD Section 14.4 (12 stats=10, MP_CAP=0, M_CTRL=0, cap 22, REG<=12)
	stat_sheet = StatSheet.new(StatSheet.DEFAULT_HUMAN_RACIAL_CAP, StatSheet.RacePreset.HUMAN)

	super._ready()
	add_to_group(&"player")
	verticality.is_focus_entity = true

	# Bind StatSheet directly to SimulationClock (no entity script coupling inside SimulationClock)
	SimulationClock.bind_player_stats(stat_sheet)

	# Clone read-only .tres weapon templates (1: Dagger, 2: Greatsword, 3: Heavy Warhammer)
	var dagger_tpl: WeaponData = load(DAGGER_TEMPLATE_PATH) as WeaponData
	var greatsword_tpl: WeaponData = load(GREATSWORD_TEMPLATE_PATH) as WeaponData
	var warhammer_tpl: WeaponData = load(WARHAMMER_TEMPLATE_PATH) as WeaponData
	_initial_weapon_templates.clear()
	weapon_slots.clear()
	if dagger_tpl != null:
		_initial_weapon_templates.append(dagger_tpl)
		weapon_slots.append(dagger_tpl.create_runtime_copy())
	if greatsword_tpl != null:
		_initial_weapon_templates.append(greatsword_tpl)
		weapon_slots.append(greatsword_tpl.create_runtime_copy())
	if warhammer_tpl != null:
		_initial_weapon_templates.append(warhammer_tpl)
		weapon_slots.append(warhammer_tpl.create_runtime_copy())
	if not weapon_slots.is_empty():
		select_weapon_slot(0)

	# Player anatomical HitboxZones (Head + Chest weak points)
	rebuild_hitbox_zones(0.0, 0.0, {
		AnatomyComponent.ZONE_HEAD: [Vector2(0.0, -6.0)],
		AnatomyComponent.ZONE_CHEST: [Vector2(0.0, 0.0)],
	})

	_setup_camera_and_flash()
	_setup_interact_prompt()
	if EventBus != null and not EventBus.camera_shake_requested.is_connected(trigger_camera_shake):
		EventBus.camera_shake_requested.connect(trigger_camera_shake)


func _exit_tree() -> void:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			var clock: Node = tree.root.get_node_or_null("SimulationClock")
			if clock != null and clock.has_method("unbind_player_stats_if_matches"):
				clock.call("unbind_player_stats_if_matches", stat_sheet)
			var bus: Node = tree.root.get_node_or_null("EventBus")
			if bus != null and bus.is_connected("camera_shake_requested", Callable(self, "trigger_camera_shake")):
				bus.disconnect("camera_shake_requested", Callable(self, "trigger_camera_shake"))


func _setup_camera_and_flash() -> void:
	camera = get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		add_child(camera)
	camera.enabled = true
	camera.make_current()
	camera.zoom = compute_target_camera_zoom()

	flash_layer = get_node_or_null("FlashLayer") as CanvasLayer
	if flash_layer == null:
		flash_layer = CanvasLayer.new()
		flash_layer.name = "FlashLayer"
		flash_layer.layer = 100
		add_child(flash_layer)

	flash_rect = flash_layer.get_node_or_null("FlashRect") as ColorRect
	if flash_rect == null:
		flash_rect = ColorRect.new()
		flash_rect.name = "FlashRect"
		flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
		flash_layer.add_child(flash_rect)


func _setup_interact_prompt() -> void:
	if body_visual == null:
		return
	interact_prompt_label = body_visual.get_node_or_null("InteractPromptLabel") as Label
	if interact_prompt_label == null:
		interact_prompt_label = Label.new()
		interact_prompt_label.name = "InteractPromptLabel"
		body_visual.add_child(interact_prompt_label)
	interact_prompt_label.z_as_relative = false
	interact_prompt_label.z_index = 850
	interact_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_prompt_label.custom_minimum_size = Vector2(180.0, 0.0)
	interact_prompt_label.position = Vector2(-90.0, -34.0)
	interact_prompt_label.add_theme_font_size_override("font_size", 7)
	interact_prompt_label.add_theme_color_override("font_color", Color("#FFF3B0"))
	interact_prompt_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.09, 0.95))
	interact_prompt_label.add_theme_constant_override("outline_size", 2)
	interact_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interact_prompt_label.focus_mode = Control.FOCUS_NONE
	interact_prompt_label.visible = false

	takedown_prompt_label = body_visual.get_node_or_null("TakedownPromptLabel") as Label
	if takedown_prompt_label == null:
		takedown_prompt_label = Label.new()
		takedown_prompt_label.name = "TakedownPromptLabel"
		body_visual.add_child(takedown_prompt_label)
	takedown_prompt_label.z_as_relative = false
	takedown_prompt_label.z_index = 851
	takedown_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	takedown_prompt_label.custom_minimum_size = Vector2(180.0, 0.0)
	takedown_prompt_label.position = Vector2(-90.0, -44.0)
	takedown_prompt_label.add_theme_font_size_override("font_size", 7)
	takedown_prompt_label.add_theme_color_override("font_color", Color("#74EBD5"))
	takedown_prompt_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.09, 0.95))
	takedown_prompt_label.add_theme_constant_override("outline_size", 2)
	takedown_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	takedown_prompt_label.focus_mode = Control.FOCUS_NONE
	takedown_prompt_label.visible = false


func _process(delta: float) -> void:
	# Camera & subjective parry window always run on pure system delta (GDD 2.3, 7.4, 12.7)
	tick_parry_window_subjective(delta)
	tick_crouch_visual(delta)
	if _distract_cooldown_timer > 0.0:
		_distract_cooldown_timer = maxf(0.0, _distract_cooldown_timer - delta)
	_update_dynamic_camera(delta)
	_update_weak_point_highlight()
	_update_interact_prompt()
	_update_stealth_takedown_prompt()

	# Hold-Q Clinch trigger (GDD 14.5: hold Q in close quarters -> Clinch Throw / Sweep)
	if _clinch_key_held and not _clinch_triggered_while_held and is_alive():
		_clinch_hold_elapsed += delta
		if _clinch_hold_elapsed >= CLINCH_HOLD_THRESHOLD_SEC:
			_clinch_triggered_while_held = true
			_execute_clinch_hold()

	# Hold-E Careful Extraction trigger (extracts LodgedWeapon without ripping tissue)
	if _interact_key_held and not _interact_triggered_while_held and is_alive():
		_interact_hold_elapsed += delta
		if _interact_hold_elapsed >= CAREFUL_EXTRACT_HOLD_SEC:
			_interact_triggered_while_held = true
			handle_interact_action(true)


func _physics_process(delta: float) -> void:
	var w_delta: float = SimulationClock.get_world_delta(delta)
	var action_delta: float = SimulationClock.get_player_action_delta(delta, get_instance_id())

	# Step active knockback / Wall Slam first
	if knockback_timer > 0.0:
		step_knockback(w_delta)

	# Update mouse aim with inertial turn lag when SPD/TP > 1.5 (GDD 2.3)
	update_aim_with_drift(get_global_mouse_position(), delta)

	# Read movement vector via InputMap & allow EventBus control_input_pipeline interception
	var input_vec: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var ctrl_ctx: Dictionary = EventBus.run_control_input_pipeline({
		"entity": self,
		"move_input": input_vec,
		"cancelled": false,
	})
	if bool(ctrl_ctx.get("cancelled", false)):
		input_vec = Vector2.ZERO
	else:
		input_vec = ctrl_ctx.get("move_input", input_vec) as Vector2

	# Hold-block state (ПКМ / offhand_defend)
	set_block_held(Input.is_action_pressed(&"offhand_defend"))

	# Subjective/action status timers (Hardening, Prone, Counter Window) never freeze 50x at TP=500!
	tick_combat_status_timers(action_delta, delta)

	# Lockstep micro-stepped movement (clamps dash/sidestep duration cleanly) + combat FSM
	var moved: bool = step_movement_and_combat(input_vec, action_delta, delta)

	# Physiology, bleeding, REG, stamina/MP regen & Aura drain strictly on world_delta!
	tick_physiology(w_delta, moved)


## Computes run velocity with genuine raw_delta-based inertial drift when SPD/TP > 1.5 (GDD 2.3).
## Releasing WASD slides smoothly instead of snapping to zero.
func compute_run_velocity_with_drift(input_vec: Vector2, raw_delta: float) -> Vector2:
	var desired_vel: Vector2 = Vector2.ZERO
	if input_vec.length_squared() > 0.001:
		desired_vel = input_vec.normalized() * BASE_RUN_SPEED_PX * get_flight_speed_mult() * get_crouch_speed_mult()
		if is_blocking:
			desired_vel *= 0.45

	if SimulationClock != null and SimulationClock.is_player_losing_control():
		var ratio: float = maxf(SimulationClock.LOSS_OF_CONTROL_SPD_TP_RATIO, SimulationClock.get_player_spd_to_tp_ratio())
		var blend_rate: float = clampf(5.5 / ratio, 0.35, 3.5) if desired_vel.length_squared() > 0.001 else clampf(4.2 / ratio, 0.28, 2.8)
		var alpha: float = 1.0 - exp(-blend_rate * maxf(0.0, raw_delta))
		_drift_velocity = _drift_velocity.lerp(desired_vel, clampf(alpha, 0.0, 1.0))
		if desired_vel.length_squared() <= 0.001 and _drift_velocity.length_squared() < 4.0:
			_drift_velocity = Vector2.ZERO
		return _drift_velocity

	_drift_velocity = desired_vel
	return desired_vel


## Updates aim_angle toward target_world_pos, applying angular inertia lag while SPD/TP > 1.5.
func update_aim_with_drift(target_world_pos: Vector2, raw_delta: float) -> float:
	aim_world_pos = target_world_pos
	var desired_angle: float = (target_world_pos - get_combat_origin()).angle()
	if SimulationClock != null and SimulationClock.is_player_losing_control() and raw_delta > 0.0:
		var ratio: float = maxf(SimulationClock.LOSS_OF_CONTROL_SPD_TP_RATIO, SimulationClock.get_player_spd_to_tp_ratio())
		var turn_rate: float = clampf(12.0 / ratio, 1.2, 8.0)
		var alpha: float = 1.0 - exp(-turn_rate * raw_delta)
		aim_angle = lerp_angle(aim_angle, desired_angle, clampf(alpha, 0.0, 1.0))
	else:
		aim_angle = desired_angle
	return aim_angle


## Steps movement and combat FSM in lockstep micro-steps so high-SPD dashes/sidesteps
## never overshoot their exact timer duration (e.g. SPD=500, TP=10 -> action_delta=0.83s).
func step_movement_and_combat(input_vec: Vector2, action_delta: float, raw_delta: float) -> bool:
	var run_vel: Vector2 = compute_run_velocity_with_drift(input_vec, raw_delta) if can_act() else Vector2.ZERO
	if not can_act():
		_drift_velocity = Vector2.ZERO
	if action_delta <= 0.0 or not is_alive():
		current_move_velocity = Vector2.ZERO
		return false

	var moved_any: bool = false
	var micro_steps: Array[float] = SimulationClock.compute_action_micro_steps(action_delta)
	for step_dt: float in micro_steps:
		if not is_alive():
			break
		if can_act():
			if sidestep_timer > 0.0:
				var side_speed: float = BASE_SIDESTEP_SPEED_PX * (1.0 + maxf(0.0, stat_sheet.get_stat(StatSheet.Stat.AGI) - 10.0) * 0.015)
				var side_dt: float = minf(step_dt, sidestep_timer)
				var rem_dt: float = step_dt - side_dt
				move_with_substepping(sidestep_direction * side_speed, side_dt, false)
				moved_any = true
				if rem_dt > 0.0 and run_vel.length_squared() > 1e-4:
					move_with_substepping(run_vel, rem_dt, false)
			elif dash_timer > 0.0:
				var dash_speed: float = BASE_DASH_SPEED_PX * stat_sheet.get_dash_mult() * (0.78 if is_crouching else 1.0)
				var d_dt: float = minf(step_dt, dash_timer)
				var rem_dt: float = step_dt - d_dt
				move_with_substepping(dash_direction * dash_speed, d_dt, true)
				moved_any = true
				if rem_dt > 0.0 and run_vel.length_squared() > 1e-4:
					move_with_substepping(run_vel, rem_dt, false)
			elif run_vel.length_squared() > 1e-4:
				move_with_substepping(run_vel, step_dt, false)
				moved_any = true
			else:
				current_move_velocity = Vector2.ZERO
		else:
			current_move_velocity = Vector2.ZERO
		_step_combat_micro(step_dt)

	return moved_any


func _unhandled_input(event: InputEvent) -> void:
	if not is_alive():
		return

	# Check attack_thrust (Shift+LMB / V) BEFORE attack_slash (LMB) to prevent Shift+LMB overlap!
	if event.is_action_pressed(&"attack_thrust"):
		var target_pt: Vector2 = _resolve_input_aim_point()
		start_attack(target_pt, PenetrationResolver.AttackType.THRUST)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"attack_slash"):
		var target_pt: Vector2 = _resolve_input_aim_point()
		start_attack(target_pt, PenetrationResolver.AttackType.SLASH)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"attack_blunt_clinch"):
		_clinch_key_held = true
		_clinch_hold_elapsed = 0.0
		_clinch_triggered_while_held = false
		if is_crouching:
			var td_target: CombatActor = find_stealth_takedown_target()
			if td_target != null:
				_clinch_triggered_while_held = true
				perform_stealth_takedown(td_target)
				get_viewport().set_input_as_handled()
	elif event.is_action_released(&"attack_blunt_clinch"):
		var was_triggered: bool = _clinch_triggered_while_held
		_clinch_key_held = false
		_clinch_hold_elapsed = 0.0
		_clinch_triggered_while_held = false
		if not was_triggered:
			var target_pt: Vector2 = _resolve_input_aim_point()
			var close_tgt: CombatActor = find_clinch_target(CLINCH_RANGE_PX)
			if close_tgt != null:
				if is_crouching and can_perform_stealth_takedown(close_tgt):
					perform_stealth_takedown(close_tgt)
				elif Input.is_key_pressed(KEY_SHIFT):
					perform_clinch_sweep(close_tgt)
				else:
					perform_clinch_shove(close_tgt, (target_pt - get_combat_origin()).normalized())
			else:
				start_attack(target_pt, PenetrationResolver.AttackType.BLUNT)
	elif event.is_action_pressed(&"toggle_crouch"):
		var crouched_now: bool = toggle_crouch()
		print("[Player] Crouch: %s" % ("ON" if crouched_now else "OFF"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"stealth_distract"):
		perform_stealth_distract(_resolve_input_aim_point())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"offhand_defend"):
		trigger_block_pressed()
	elif event.is_action_pressed(&"sidestep_dash"):
		var move_dir: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if move_dir.length_squared() <= 0.001:
			move_dir = Vector2.from_angle(aim_angle)
		start_sidestep_or_dash(move_dir)
	elif event.is_action_pressed(&"hardening_guard"):
		if activate_hardening():
			print("[Player] Hardening activated (+%.0f barrier)!" % hardening_bonus_value)
	elif event.is_action_pressed(&"toggle_halfsword"):
		var hs_on: bool = toggle_half_swording()
		print("[Player] Half-swording: %s" % ("ON" if hs_on else "OFF"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"feint_cancel"):
		if try_feint_cancel():
			print("[Player] Feint cancel!")
	elif event.is_action_pressed(&"toggle_tempo_mode"):
		var ok: bool = SimulationClock.toggle_player_tempo()
		if ok:
			print("[Player] TempoMode -> %s" % ("COMBAT_OVERDRIVE" if SimulationClock.is_combat_overdrive() else "PEACEFUL 1.0x"))
		else:
			print("[Player] Cannot disable COMBAT_OVERDRIVE while pursued (%d active aggro)!" % SimulationClock.get_active_aggro_count())
	elif event.is_action_pressed(&"toggle_perception_regulator"):
		var new_perc: float = SimulationClock.toggle_perception_regulator()
		print("[Player] perception_regulator -> %.2f (WTS=%.3fx)" % [new_perc, SimulationClock.get_world_time_scale()])
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"aura_and_burst"):
		var res: Dictionary = handle_aura_or_burst_input()
		if String(res.get("action", "")) == "aura_burst":
			if bool(res.get("success", false)):
				print("[Player] AURA BURST triggered! (MP=%.1f/%.1f)" % [current_mp, stat_sheet.get_max_mp()])
		else:
			print("[Player] Aura: %s (MP=%.1f/%.1f)" % ["ON" if aura_active else "OFF", current_mp, stat_sheet.get_max_mp()])
	elif event.is_action_pressed(&"switch_weapon_1"):
		select_weapon_slot(0)
	elif event.is_action_pressed(&"switch_weapon_2"):
		select_weapon_slot(1)
	elif event.is_action_pressed(&"switch_weapon_3"):
		select_weapon_slot(2)
	elif event.is_action_pressed(&"toggle_flight"):
		var fl_res: Dictionary = try_toggle_flight(VerticalityComponent.HEIGHT_HIGH_FLIGHT)
		if bool(fl_res.get("success", false)):
			print("[Player] Flight -> %s (height_z=%.1f)" % [
				VerticalityComponent.get_flight_mode_name(get_flight_mode()),
				get_height_z(),
			])
		else:
			var fl_msg: String = String(fl_res.get("message", ""))
			if not fl_msg.is_empty():
				print("[Player] %s" % fl_msg)
				var arena_fl: TestArena = _find_arena()
				if arena_fl != null:
					arena_fl.spawn_floating_callout(global_position, get_floor_level(), get_height_z(), fl_msg, Color("#FF9F43"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
		if Input.is_key_pressed(KEY_SHIFT):
			_interact_key_held = false
			_interact_hold_elapsed = 0.0
			_interact_triggered_while_held = true
			var res: Dictionary = handle_interact_action(true)
			if bool(res.get("handled", false)):
				get_viewport().set_input_as_handled()
		else:
			_interact_key_held = true
			_interact_hold_elapsed = 0.0
			_interact_triggered_while_held = false
	elif event.is_action_released(&"interact"):
		var was_handled: bool = _interact_triggered_while_held
		_interact_key_held = false
		_interact_hold_elapsed = 0.0
		_interact_triggered_while_held = false
		if not was_handled:
			var res: Dictionary = handle_interact_action(false)
			if bool(res.get("handled", false)):
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"speed_reg_down"):
		var new_reg: float = SimulationClock.adjust_speed_regulator(-1)
		print("[Player] speed_regulator -> %.2f" % new_reg)
	elif event.is_action_pressed(&"speed_reg_up"):
		var new_reg: float = SimulationClock.adjust_speed_regulator(1)
		print("[Player] speed_regulator -> %.2f" % new_reg)


func _resolve_input_aim_point() -> Vector2:
	var mouse_pt: Vector2 = get_global_mouse_position()
	if SimulationClock != null and SimulationClock.is_player_losing_control():
		var origin: Vector2 = get_combat_origin()
		var dist: float = maxf(24.0, origin.distance_to(mouse_pt))
		return origin + Vector2.from_angle(aim_angle) * dist
	aim_world_pos = mouse_pt
	return mouse_pt


## Unified interact handler (single source of truth for E):
## - careful == true (Shift+E or Hold E >= 0.35s): ONLY careful LodgedWeapon extraction (stairs never fire).
## - careful == false (short tap E): fast LodgedWeapon extract -> ground pickup -> stairs.
func handle_interact_action(careful: bool = false) -> Dictionary:
	var ext: Dictionary = try_extract_lodged_weapon(careful)
	if bool(ext.get("extracted", false)):
		print("[Player] Extracted lodged weapon from %s (%s)!" % [String(ext.get("zone", "")), "careful" if careful else "fast rip"])
		ext["handled"] = true
		ext["action"] = &"extract_lodged"
		return ext
	if careful:
		return {"handled": false, "action": &""}
	var picked: WeaponData = try_pickup_dropped_weapon()
	if picked != null:
		print("[Player] Picked up %s from the ground!" % picked.display_name)
		return {"handled": true, "action": &"pickup", "weapon": picked}
	var arena: TestArena = _find_arena()
	if arena != null and arena.try_use_stairs(self):
		return {"handled": true, "action": &"stairs"}
	return {"handled": false, "action": &""}


## Computes the contextual world-space [E] interact prompt matching handle_interact_action() priority:
## 1. LodgedWeapon on self or adjacent actor (<= 48px, same floor)
## 2. Nearby dropped weapon pickup (<= 42px, same floor, free weapon slot / hands)
## 3. StairsArea floor transition (0 <-> +1)
func compute_interact_prompt() -> Dictionary:
	var empty_prompt: Dictionary = {"visible": false, "action": &"", "text": ""}
	if not is_alive() or (anatomy != null and anatomy.is_unconscious):
		return empty_prompt

	if not has_both_arms_severed():
		var has_lodged: bool = anatomy != null and anatomy.has_lodged_weapon()
		if not has_lodged and is_inside_tree():
			for grp: StringName in [&"enemies", &"player"]:
				for n: Node in get_tree().get_nodes_in_group(grp):
					if n == self or not (n is CombatActor):
						continue
					var other: CombatActor = n as CombatActor
					if other.get_floor_level() != get_floor_level():
						continue
					if global_position.distance_to(other.global_position) <= 48.0 and other.anatomy != null and other.anatomy.has_lodged_weapon():
						has_lodged = true
						break
				if has_lodged:
					break
		if has_lodged:
			return {
				"visible": true,
				"action": &"extract_lodged",
				"text": "[E] Вырвать / [Удерж. E] Аккуратно",
			}

	var arena: TestArena = _find_arena()
	if arena != null:
		if can_accept_weapon():
			var drop_info: Dictionary = arena.find_nearest_dropped_weapon_info(global_position, get_floor_level(), 42.0)
			if bool(drop_info.get("found", false)):
				var wpn: WeaponData = drop_info.get("weapon", null) as WeaponData
				var wname: String = wpn.display_name if wpn != null else "оружие"
				return {
					"visible": true,
					"action": &"pickup",
					"text": "[E] Поднять %s" % wname,
				}
		if arena.is_entity_on_stairs(self):
			var next_floor_str: String = "+1" if get_floor_level() == 0 else "0"
			return {
				"visible": true,
				"action": &"stairs",
				"text": "[E] Этаж %s" % next_floor_str,
			}

	return empty_prompt


func _update_interact_prompt() -> Dictionary:
	last_interact_prompt = compute_interact_prompt()
	if interact_prompt_label != null and is_instance_valid(interact_prompt_label):
		var show_now: bool = bool(last_interact_prompt.get("visible", false))
		interact_prompt_label.visible = show_now
		if show_now:
			interact_prompt_label.text = String(last_interact_prompt.get("text", ""))
	return last_interact_prompt


func compute_stealth_takedown_prompt() -> Dictionary:
	var empty_td: Dictionary = {"visible": false, "target": null, "text": ""}
	if not is_alive() or not is_crouching or (anatomy != null and anatomy.is_unconscious):
		return empty_td
	var td_target: CombatActor = find_stealth_takedown_target()
	if td_target == null:
		return empty_td
	return {
		"visible": true,
		"target": td_target,
		"text": "[Q] Оглушить",
	}


func _update_stealth_takedown_prompt() -> Dictionary:
	last_takedown_prompt = compute_stealth_takedown_prompt()
	if takedown_prompt_label != null and is_instance_valid(takedown_prompt_label):
		var show_td: bool = bool(last_takedown_prompt.get("visible", false))
		takedown_prompt_label.visible = show_td
		if show_td:
			takedown_prompt_label.text = String(last_takedown_prompt.get("text", ""))
	return last_takedown_prompt


## Throws a small pebble / noise distraction toward target_world_pos (up to 180px, stopped by high walls).
## Emits a 170px noise event and floor ripple ring that lures nearby PATROL enemies into SEARCH.
func perform_stealth_distract(target_world_pos: Vector2) -> Dictionary:
	if not can_act() or has_both_arms_severed() or _distract_cooldown_timer > 0.0:
		return {"success": false, "reason": "unavailable", "pos": global_position, "radius": 0.0, "blocked_by_wall": false}
	var delta_vec: Vector2 = target_world_pos - global_position
	var dist: float = delta_vec.length()
	var dir: Vector2 = delta_vec.normalized() if dist > 0.001 else Vector2.from_angle(aim_angle)
	var clamped_dist: float = clampf(dist, 24.0, STEALTH_DISTRACT_MAX_DIST_PX)
	var landing_pos: Vector2 = global_position + dir * clamped_dist
	var blocked_by_wall: bool = false

	var world_2d: World2D = get_world_2d()
	if world_2d != null and FloorLayerManager != null:
		var wall_mask: int = FloorLayerManager.get_high_walls_bit(get_floor_level())
		if wall_mask != 0:
			var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, landing_pos, wall_mask)
			query.collide_with_bodies = true
			query.collide_with_areas = false
			query.exclude = [get_rid()]
			var hit: Dictionary = world_2d.direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				var hit_pos: Vector2 = hit["position"] as Vector2
				var hit_norm: Vector2 = hit["normal"] as Vector2
				landing_pos = hit_pos + hit_norm * 6.0
				blocked_by_wall = true

	_distract_cooldown_timer = STEALTH_DISTRACT_COOLDOWN_SEC
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_method("emit_noise"):
		bus.call("emit_noise", landing_pos, get_floor_level(), STEALTH_DISTRACT_NOISE_RADIUS_PX, self)
	var arena: TestArena = _find_arena()
	if arena != null:
		arena.spawn_noise_ripple(landing_pos, get_floor_level(), STEALTH_DISTRACT_NOISE_RADIUS_PX)
		arena.spawn_floating_callout(landing_pos, get_floor_level(), 0.0, "*стук*", Color("#FFEAA7"))
	return {
		"success": true,
		"pos": landing_pos,
		"radius": STEALTH_DISTRACT_NOISE_RADIUS_PX,
		"blocked_by_wall": blocked_by_wall,
	}


func _execute_clinch_hold() -> void:
	var target: CombatActor = find_clinch_target(CLINCH_RANGE_PX)
	if target == null:
		start_attack(_resolve_input_aim_point(), PenetrationResolver.AttackType.BLUNT)
		return
	var throw_dir: Vector2 = Vector2.from_angle(aim_angle)
	if Input.is_action_pressed(&"move_down"):
		perform_clinch_sweep(target)
	else:
		perform_clinch_throw(target, throw_dir)


func can_accept_weapon() -> bool:
	if has_both_arms_severed():
		return false
	if equipped_weapon == null or equipped_weapon.is_unarmed:
		return true
	for slot_wpn: WeaponData in weapon_slots:
		if slot_wpn == null:
			return true
	return false


func disarm_active_weapon(spawn_on_floor: bool = true, reason: StringName = &"disarm") -> WeaponData:
	var dropped: WeaponData = super.disarm_active_weapon(spawn_on_floor, reason)
	if dropped != null:
		for i: int in range(weapon_slots.size()):
			if weapon_slots[i] == dropped:
				weapon_slots[i] = null
	return dropped


func disarm_weapon_into_target(lodged_weapon: WeaponData) -> bool:
	var ok: bool = super.disarm_weapon_into_target(lodged_weapon)
	if ok:
		for i: int in range(weapon_slots.size()):
			if weapon_slots[i] == lodged_weapon:
				weapon_slots[i] = null
	return ok


func receive_recovered_weapon(weapon: WeaponData) -> bool:
	if weapon == null or weapon.is_unarmed:
		return false
	if has_both_arms_severed():
		var arena_no_arms: TestArena = _find_arena()
		if arena_no_arms != null:
			arena_no_arms.spawn_dropped_weapon(weapon, global_position, get_floor_level())
		return false
	if active_weapon_index >= 0 and active_weapon_index < weapon_slots.size() and weapon_slots[active_weapon_index] == null:
		weapon_slots[active_weapon_index] = weapon
		equip_weapon_instance(weapon)
		return true
	for i: int in range(weapon_slots.size()):
		if weapon_slots[i] == null:
			weapon_slots[i] = weapon
			if equipped_weapon == null or equipped_weapon.is_unarmed:
				active_weapon_index = i
				equip_weapon_instance(weapon)
			return true
	# All slots are full -> place safely on the arena floor instead of deleting into the void!
	var arena: TestArena = _find_arena()
	if arena != null:
		arena.spawn_dropped_weapon(weapon, global_position, get_floor_level())
	return false


func revive_and_heal_all() -> void:
	for i: int in range(_initial_weapon_templates.size()):
		if i < weapon_slots.size():
			if weapon_slots[i] == null:
				weapon_slots[i] = _initial_weapon_templates[i].create_runtime_copy()
			else:
				weapon_slots[i].edge_sharpness = weapon_slots[i].max_edge_sharpness
				weapon_slots[i].durability = weapon_slots[i].max_durability
		else:
			weapon_slots.append(_initial_weapon_templates[i].create_runtime_copy())
	super.revive_and_heal_all()
	land_from_flight(false, "")
	_drift_velocity = Vector2.ZERO
	_distract_cooldown_timer = 0.0
	if active_weapon_index >= 0 and active_weapon_index < weapon_slots.size() and weapon_slots[active_weapon_index] != null:
		equip_weapon_instance(weapon_slots[active_weapon_index])


func select_weapon_slot(index: int) -> bool:
	if index < 0 or index >= weapon_slots.size():
		return false
	if has_both_arms_severed():
		return false
	active_weapon_index = index
	equip_weapon_instance(weapon_slots[index])
	var active_wpn: WeaponData = get_active_weapon()
	print("[Player] Equipped %s (pen=%.1f, len=%.1f, reach=%.1f)" % [
		active_wpn.display_name,
		active_wpn.base_penetration,
		active_wpn.blade_length,
		active_wpn.vertical_reach,
	])
	return true


## Dynamic camera zoom per GDD Section 12.7:
## zoom = base_zoom / clamp(1.0 + (size_mult - 1.0) * 0.35 + height_z * 0.12, 1.0, 2.5)
func compute_target_camera_zoom() -> Vector2:
	var z_val: float = get_height_z()
	var denom: float = clampf(1.0 + (actor_size_mult - 1.0) * 0.35 + z_val * 0.12, 1.0, 2.5)
	return BASE_CAMERA_ZOOM / denom


func _update_dynamic_camera(raw_delta: float) -> void:
	if camera == null:
		return
	var target_zoom: Vector2 = compute_target_camera_zoom()
	camera.zoom = camera.zoom.lerp(target_zoom, clampf(raw_delta * CAMERA_ZOOM_LERP_SPEED, 0.0, 1.0))

	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - raw_delta)
		_shake_phase += raw_delta * 55.0
		var decay: float = _shake_timer / maxf(0.01, _shake_duration)
		var mag: float = _shake_intensity * decay
		camera.offset = Vector2(sin(_shake_phase) * mag, cos(_shake_phase * 1.37) * mag * 0.85)
	elif camera.offset.length_squared() > 0.001:
		camera.offset = Vector2.ZERO


func trigger_camera_shake(intensity_px: float, duration_sec: float = 0.16) -> void:
	if intensity_px <= 0.0 or duration_sec <= 0.0:
		return
	_shake_intensity = maxf(_shake_intensity, clampf(intensity_px, 0.5, 14.0))
	_shake_duration = maxf(_shake_duration, clampf(duration_sec, 0.05, 0.45))
	_shake_timer = maxf(_shake_timer, clampf(duration_sec, 0.05, 0.45))
	if camera != null:
		camera.offset = Vector2(_shake_intensity, 0.0)


func get_active_camera_shake_offset() -> Vector2:
	return camera.offset if camera != null else Vector2.ZERO


func _update_weak_point_highlight() -> void:
	if stat_sheet == null or not is_inside_tree():
		return
	var highlight: bool = stat_sheet.can_auto_highlight_weak_points() or EventBus.debug_highlight_weak_points
	var radius: float = WeaponRaySweeper.get_effective_precision_radius_px(stat_sheet, current_attack_type, half_swording)
	for n: Node in get_tree().get_nodes_in_group(&"hitbox_zones"):
		if n is HitboxZone:
			var hz: HitboxZone = n as HitboxZone
			if hz.owner_actor != self and (hz.show_weak_points != highlight or not is_equal_approx(hz.weak_point_draw_radius, radius)):
				hz.set_weak_points_visible(highlight, radius)


func trigger_screen_flash(color: Color, duration: float = 0.15) -> void:
	if flash_rect == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	flash_rect.color = color
	if is_inside_tree():
		_flash_tween = create_tween()
		_flash_tween.tween_property(flash_rect, "color:a", 0.0, maxf(0.05, duration))
