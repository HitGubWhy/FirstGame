class_name DebugHUD
extends CanvasLayer
## Stage 0 v0.2 Debug HUD & Cheat Panel (GDD Sections 14.1 #6, 14.2, 14.5).
## Runs strictly on raw system delta (independent of SimulationClock time dilation)
## and listens exclusively to EventBus without coupling UI code into PlayerController.
## Every interactive control uses focus_mode = FOCUS_NONE so Space never triggers buttons,
## and passive containers pass non-button clicks through so combat input is never blocked.

const FONT_SIZE_HEADER: int = 8
const FONT_SIZE_BODY: int = 7
const FONT_SIZE_TINY: int = 7

const COLOR_PANEL_BG: Color = Color(0.06, 0.07, 0.09, 0.84)
const COLOR_PANEL_BORDER: Color = Color(0.28, 0.32, 0.40, 0.90)

const COLOR_ZONE_HEALTHY: Color = Color("#2ECC71")
const COLOR_ZONE_LIGHT: Color = Color("#F1C40F")
const COLOR_ZONE_SEVERE: Color = Color("#E67E22")
const COLOR_ZONE_CRITICAL: Color = Color("#E74C3C")
const COLOR_ZONE_DESTROYED: Color = Color("#8E1616")
const COLOR_ZONE_SEVERED: Color = Color("#2D161E")

const SLIDER_STATS: Array[int] = [
	StatSheet.Stat.STR,
	StatSheet.Stat.CTRL,
	StatSheet.Stat.SPD,
	StatSheet.Stat.AGI,
	StatSheet.Stat.CON,
	StatSheet.Stat.STA,
	StatSheet.Stat.TP,
	StatSheet.Stat.INT,
	StatSheet.Stat.MP_CAP,
	StatSheet.Stat.M_CTRL,
	StatSheet.Stat.SOUL,
	StatSheet.Stat.REG,
]

# Telemetry labels (top-left)
var telemetry_panel: PanelContainer = null
var lbl_tempo: Label = null
var lbl_clock: Label = null
var lbl_calendar: Label = null
var lbl_space: Label = null
var lbl_resources: Label = null
var lbl_weapon: Label = null
var lbl_pen_header: Label = null
var lbl_pen_values: Label = null
var lbl_pen_depth: Label = null
var lbl_clash_log: Label = null
var lbl_event_log: Label = null

# Anatomy panel (bottom-left: Player + Last Attacked Target)
var anatomy_panel: PanelContainer = null
var player_zone_rects: Dictionary[StringName, ColorRect] = {}
var target_zone_rects: Dictionary[StringName, ColorRect] = {}
var lbl_player_title: Label = null
var lbl_player_blood: Label = null
var lbl_player_shock: Label = null
var lbl_player_res: Label = null
var lbl_player_organs: Label = null
var lbl_player_layers: Label = null
var lbl_player_limbs: Label = null
var lbl_player_wounds: Label = null
var lbl_target_title: Label = null
var lbl_target_blood: Label = null
var lbl_target_shock: Label = null
var lbl_target_res: Label = null
var lbl_target_organs: Label = null
var lbl_target_layers: Label = null
var lbl_target_limbs: Label = null
var lbl_target_wounds: Label = null

# Toggleable Debug / Cheat Panel (right side, F1) & Full Game Combat HUD (F2)
var debug_panel: PanelContainer = null
var game_hud_root: Control = null
var mini_hud_panel: PanelContainer = null
var game_hud_top_right: PanelContainer = null
var game_hud_weapon_panel: PanelContainer = null
var lbl_mini_hud: Label = null
var bar_game_blood: ProgressBar = null
var lbl_game_blood: Label = null
var bar_game_shock: ProgressBar = null
var lbl_game_shock: Label = null
var bar_game_sta: ProgressBar = null
var lbl_game_sta: Label = null
var bar_game_mp: ProgressBar = null
var lbl_game_mp: Label = null
var _bar_game_mp_fill_style: StyleBoxFlat = null
var bar_game_poise: ProgressBar = null
var lbl_game_poise: Label = null
var lbl_game_calories: Label = null
var lbl_game_stealth: Label = null
var lbl_game_tempo: Label = null
var lbl_game_calendar: Label = null
var btn_game_hint_debug: Button = null
var btn_game_hint_hud: Button = null
var btn_game_hint_menu: Button = null
var game_slot_labels: Array[Label] = []
var lbl_game_weapon_name: Label = null
var bar_game_durability: ProgressBar = null
var lbl_game_durability: Label = null
var bar_game_sharpness: ProgressBar = null
var lbl_game_sharpness: Label = null
var game_stance_badges: Dictionary[String, Label] = {}
var compact_hud_mode: bool = false
var btn_toggle_compact_hud: Button = null
var btn_race_preset: Button = null
var btn_awaken_mana: Button = null
var btn_toggle_wings: Button = null
var btn_flight_mode_pref: Button = null
var btn_preset_10: Button = null
var btn_preset_100: Button = null
var btn_preset_250: Button = null
var btn_preset_500: Button = null
var btn_preset_int300: Button = null
var btn_toggle_perception: Button = null
var slider_perception: HSlider = null
var stat_sliders: Dictionary[int, HSlider] = {}
var stat_slider_labels: Dictionary[int, Label] = {}
var chk_anti_regen: CheckBox = null
var chk_weak_points: CheckBox = null
var chk_enemy_ai: CheckBox = null
var btn_apply_anti_regen: Button = null
var btn_hide_debug: Button = null
var btn_heal_player: Button = null
var btn_refill_resources: Button = null
var btn_bandage_all: Button = null
var btn_splint_all: Button = null
var btn_respawn_dummies: Button = null
var btn_skip_day: Button = null
var btn_skip_blood_moon: Button = null

# Knockout (KO) Overlay (without soft-locks during traumatic or hemorrhagic shock)
var ko_overlay: Control = null
var ko_panel: PanelContainer = null
var lbl_ko_title: Label = null
var lbl_ko_reason: Label = null
var btn_ko_recover: Button = null
var btn_ko_reset_arena: Button = null

# Death / Defeat Overlay (quick respawn Space / R)
var death_overlay: Control = null
var death_panel: PanelContainer = null
var lbl_death_title: Label = null
var lbl_death_cause: Label = null
var btn_respawn_player: Button = null
var btn_reset_arena_death: Button = null
var _last_player_death_cause: String = ""
var _last_player_death_zone: StringName = &""

# Pause Menu Overlay (Esc, dedicated CanvasLayer on layer 65, safe in headless & test_runner)
var pause_layer: CanvasLayer = null
var pause_overlay: Control = null
var pause_panel: PanelContainer = null
var btn_pause_resume: Button = null
var btn_pause_fullscreen: Button = null
var btn_pause_hud_mode: Button = null
var chk_pause_mute: CheckBox = null
var slider_pause_volume: HSlider = null
var lbl_pause_volume: Label = null
var lbl_pause_controls: Label = null
var btn_pause_reset_arena: Button = null
var is_pause_menu_open: bool = false
var _paused_tree_by_menu: bool = false
var _updating_pause_audio: bool = false

var last_attacked_target: CombatActor = null
var _last_outcome_data: Dictionary = {}
var _last_pen_data: Dictionary = {}
var _last_clash_data: Dictionary = {}
var _last_special_event_text: String = "--"
var _last_seen_flight_feedback: String = ""
var _updating_sliders: bool = false
var _ui_built: bool = false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_event_bus()
	_sync_controls_from_player()
	_sync_pause_audio_controls()
	_refresh_all_views()


func _exit_tree() -> void:
	if _paused_tree_by_menu and is_inside_tree():
		get_tree().paused = false
		_paused_tree_by_menu = false
	if EventBus == null:
		return
	if EventBus.penetration_resolved.is_connected(_on_penetration_resolved):
		EventBus.penetration_resolved.disconnect(_on_penetration_resolved)
	if EventBus.combat_outcome_logged.is_connected(_on_combat_outcome_logged):
		EventBus.combat_outcome_logged.disconnect(_on_combat_outcome_logged)
	if EventBus.blade_clashed.is_connected(_on_blade_clashed):
		EventBus.blade_clashed.disconnect(_on_blade_clashed)
	if EventBus.wall_slammed.is_connected(_on_wall_slammed):
		EventBus.wall_slammed.disconnect(_on_wall_slammed)
	if EventBus.limb_severed.is_connected(_on_limb_severed):
		EventBus.limb_severed.disconnect(_on_limb_severed)
	if EventBus.limb_regrown.is_connected(_on_limb_regrown):
		EventBus.limb_regrown.disconnect(_on_limb_regrown)
	if EventBus.weapon_lodged.is_connected(_on_weapon_lodged):
		EventBus.weapon_lodged.disconnect(_on_weapon_lodged)
	if EventBus.anti_regen_applied.is_connected(_on_anti_regen_applied):
		EventBus.anti_regen_applied.disconnect(_on_anti_regen_applied)
	if EventBus.debug_anti_regen_attacks_changed.is_connected(_on_debug_anti_regen_changed):
		EventBus.debug_anti_regen_attacks_changed.disconnect(_on_debug_anti_regen_changed)
	if EventBus.entity_died.is_connected(_on_entity_died):
		EventBus.entity_died.disconnect(_on_entity_died)


func _process(_delta: float) -> void:
	# Strictly runs on raw system delta without SimulationClock throttling
	_refresh_all_views()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_menu") and not _is_test_runner_scene():
		toggle_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo and ke.alt_pressed and (ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER or ke.physical_keycode == KEY_ENTER):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
	if is_pause_menu_open:
		if event.is_action_pressed(&"toggle_compact_hud"):
			toggle_compact_hud()
			get_viewport().set_input_as_handled()
		return
	var player: PlayerController = _find_player()
	if (death_overlay != null and death_overlay.visible) or (player != null and not player.is_alive()):
		if event.is_action_pressed(&"sidestep_dash") or event.is_action_pressed(&"aura_and_burst"):
			respawn_player_from_death()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"toggle_compact_hud"):
		toggle_compact_hud()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"toggle_debug_hud"):
		toggle_debug_panel()
		get_viewport().set_input_as_handled()


func _is_test_runner_scene() -> bool:
	if not is_inside_tree():
		return false
	var cur: Node = get_tree().current_scene
	if cur != null and cur.scene_file_path.ends_with("test_runner.tscn"):
		return true
	return false


func toggle_pause_menu() -> bool:
	return set_pause_menu_open(not is_pause_menu_open)


func set_pause_menu_open(open: bool) -> bool:
	is_pause_menu_open = open
	if pause_overlay != null:
		pause_overlay.visible = open
	if open:
		_sync_pause_audio_controls()
	# Only pause SceneTree in interactive non-headless play outside test_runner.tscn (never touches Engine.time_scale!)
	if is_inside_tree() and DisplayServer.get_name() != "headless" and not _is_test_runner_scene():
		get_tree().paused = open
		_paused_tree_by_menu = open
	else:
		_paused_tree_by_menu = false
	_refresh_all_views()
	return is_pause_menu_open


func set_audio_muted(muted_val: bool) -> bool:
	var arena: TestArena = _find_arena()
	if arena != null and arena.audio_manager != null:
		arena.audio_manager.muted = muted_val
	if chk_pause_mute != null and chk_pause_mute.button_pressed != muted_val:
		_updating_pause_audio = true
		chk_pause_mute.set_pressed_no_signal(muted_val)
		_updating_pause_audio = false
	return muted_val


func set_audio_volume_db(vol_db: float) -> float:
	var clamped: float = clampf(vol_db, -24.0, 0.0)
	var arena: TestArena = _find_arena()
	if arena != null and arena.audio_manager != null:
		arena.audio_manager.master_volume_db = clamped
	if slider_pause_volume != null and not is_equal_approx(slider_pause_volume.value, clamped):
		_updating_pause_audio = true
		slider_pause_volume.value = clamped
		_updating_pause_audio = false
	if lbl_pause_volume != null:
		lbl_pause_volume.text = "Громкость: %.0f дБ" % clamped
	return clamped


func _sync_pause_audio_controls() -> void:
	var arena: TestArena = _find_arena()
	var is_muted: bool = false
	var vol_db: float = -6.0
	if arena != null and arena.audio_manager != null:
		is_muted = arena.audio_manager.muted
		vol_db = arena.audio_manager.master_volume_db
	_updating_pause_audio = true
	if chk_pause_mute != null:
		chk_pause_mute.set_pressed_no_signal(is_muted)
	if slider_pause_volume != null:
		slider_pause_volume.value = clampf(vol_db, -24.0, 0.0)
	if lbl_pause_volume != null:
		lbl_pause_volume.text = "Громкость: %.0f дБ" % clampf(vol_db, -24.0, 0.0)
	_updating_pause_audio = false


## Toggles Fullscreen <-> Windowed (F11 / Alt+Enter). Strictly a safe no-op in --headless runs.
## Never modifies Engine.time_scale (strictly remains 1.0 per GDD Section 2.3).
func toggle_fullscreen() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var cur_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var screen_idx: int = DisplayServer.window_get_current_screen()
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen_idx)
		var target_size: Vector2i = Vector2i(1920, 1080)
		if usable.size.x > 0 and usable.size.y > 0:
			target_size = Vector2i(mini(target_size.x, usable.size.x), mini(target_size.y, usable.size.y))
		DisplayServer.window_set_size(target_size)
		if usable.size.x > 0 and usable.size.y > 0:
			var centered_pos: Vector2i = usable.position + Vector2i(
				floori(float(usable.size.x - target_size.x) * 0.5),
				floori(float(usable.size.y - target_size.y) * 0.5)
			)
			DisplayServer.window_set_position(centered_pos)
		return false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	return true


func toggle_debug_panel() -> bool:
	if debug_panel == null:
		return false
	if compact_hud_mode:
		set_compact_hud_mode(false)
		debug_panel.visible = true
		return true
	debug_panel.visible = not debug_panel.visible
	return debug_panel.visible


func toggle_compact_hud() -> bool:
	return set_compact_hud_mode(not compact_hud_mode)


func set_compact_hud_mode(enabled: bool) -> bool:
	compact_hud_mode = enabled
	if telemetry_panel != null:
		telemetry_panel.visible = not compact_hud_mode
	if anatomy_panel != null:
		anatomy_panel.visible = not compact_hud_mode
	if debug_panel != null:
		debug_panel.visible = not compact_hud_mode
	if game_hud_root != null:
		game_hud_root.visible = compact_hud_mode
	if mini_hud_panel != null:
		mini_hud_panel.visible = compact_hud_mode
	_refresh_all_views()
	return compact_hud_mode


# ---------------------------------------------------------------------------
# EventBus Subscribers (Zero Spaghetti in PlayerController)
# ---------------------------------------------------------------------------

func _connect_event_bus() -> void:
	if EventBus == null:
		return
	if not EventBus.penetration_resolved.is_connected(_on_penetration_resolved):
		EventBus.penetration_resolved.connect(_on_penetration_resolved)
	if not EventBus.combat_outcome_logged.is_connected(_on_combat_outcome_logged):
		EventBus.combat_outcome_logged.connect(_on_combat_outcome_logged)
	if not EventBus.blade_clashed.is_connected(_on_blade_clashed):
		EventBus.blade_clashed.connect(_on_blade_clashed)
	if not EventBus.wall_slammed.is_connected(_on_wall_slammed):
		EventBus.wall_slammed.connect(_on_wall_slammed)
	if not EventBus.limb_severed.is_connected(_on_limb_severed):
		EventBus.limb_severed.connect(_on_limb_severed)
	if not EventBus.limb_regrown.is_connected(_on_limb_regrown):
		EventBus.limb_regrown.connect(_on_limb_regrown)
	if not EventBus.weapon_lodged.is_connected(_on_weapon_lodged):
		EventBus.weapon_lodged.connect(_on_weapon_lodged)
	if not EventBus.anti_regen_applied.is_connected(_on_anti_regen_applied):
		EventBus.anti_regen_applied.connect(_on_anti_regen_applied)
	if not EventBus.debug_anti_regen_attacks_changed.is_connected(_on_debug_anti_regen_changed):
		EventBus.debug_anti_regen_attacks_changed.connect(_on_debug_anti_regen_changed)
	if not EventBus.entity_died.is_connected(_on_entity_died):
		EventBus.entity_died.connect(_on_entity_died)
	if not EventBus.last_penetration_log.is_empty():
		_last_pen_data = EventBus.last_penetration_log.duplicate(true)
	if not EventBus.last_combat_outcome.is_empty():
		_last_outcome_data = EventBus.last_combat_outcome.duplicate()
	if not EventBus.last_blade_clash.is_empty():
		_last_clash_data = EventBus.last_blade_clash.duplicate(true)


func _on_penetration_resolved(log_data: Dictionary) -> void:
	_last_pen_data = log_data.duplicate(true)


func _on_combat_outcome_logged(outcome_data: Dictionary) -> void:
	_last_outcome_data = outcome_data.duplicate()
	var res_dict: Variant = outcome_data.get("resolution", {})
	if res_dict is Dictionary and not (res_dict as Dictionary).is_empty():
		_last_pen_data = (res_dict as Dictionary).duplicate(true)

	var attacker: Variant = outcome_data.get("attacker", null)
	var target: Variant = outcome_data.get("target", null)
	if attacker is Node and (attacker as Node).is_in_group(&"player") and target is CombatActor:
		last_attacked_target = target as CombatActor
	elif target is Node and (target as Node).is_in_group(&"player") and attacker is CombatActor:
		if last_attacked_target == null or not is_instance_valid(last_attacked_target):
			last_attacked_target = attacker as CombatActor


func _on_blade_clashed(clash_data: Dictionary) -> void:
	_last_clash_data = clash_data.duplicate(true)


func _on_wall_slammed(entity: Node, cell: Vector2i, impulse: float, wall_broken: bool) -> void:
	var ename: String = _entity_name(entity)
	_last_special_event_text = "WallSlam: %s @(%d,%d) imp=%.0f%s" % [
		ename,
		cell.x,
		cell.y,
		impulse,
		" WALL BROKEN!" if wall_broken else "",
	]
	if entity is CombatActor and not entity.is_in_group(&"player"):
		last_attacked_target = entity as CombatActor


func _on_limb_severed(entity: Node, zone: StringName, _attacker: Node) -> void:
	var ename: String = _entity_name(entity)
	_last_special_event_text = "Dismember: %s [%s] SEVERED!" % [ename, String(zone)]
	if entity is CombatActor and not entity.is_in_group(&"player"):
		last_attacked_target = entity as CombatActor


func _on_limb_regrown(entity: Node, zone: StringName) -> void:
	var ename: String = _entity_name(entity)
	_last_special_event_text = "REG Regrown: %s [%s] INTACT" % [ename, String(zone)]


func _on_weapon_lodged(entity: Node, zone: StringName, weapon: WeaponData, _attacker: Node) -> void:
	var ename: String = _entity_name(entity)
	var wname: String = weapon.display_name if weapon != null else "Blade"
	_last_special_event_text = "LodgedWeapon: %s [%s] <- %s" % [ename, String(zone), wname]


func _on_anti_regen_applied(entity: Node, zone: StringName, duration_sec: float) -> void:
	var ename: String = _entity_name(entity)
	var ztag: String = String(zone) if zone != &"" else "GLOBAL"
	_last_special_event_text = "Anti-Regen: %s [%s] %.1fs" % [ename, ztag, duration_sec]
	if entity is CombatActor and not entity.is_in_group(&"player"):
		last_attacked_target = entity as CombatActor


func _on_debug_anti_regen_changed(enabled: bool) -> void:
	if chk_anti_regen != null and chk_anti_regen.button_pressed != enabled:
		chk_anti_regen.set_pressed_no_signal(enabled)


func _on_entity_died(entity: Node, cause: String, zone: StringName) -> void:
	if entity != null and entity.is_in_group(&"player"):
		_last_player_death_cause = cause
		_last_player_death_zone = zone
		_update_death_overlay(entity as PlayerController)


static func _entity_name(entity: Node) -> String:
	if entity is CombatActor:
		return (entity as CombatActor).actor_display_name
	return String(entity.name) if entity != null else "?"


# ---------------------------------------------------------------------------
# UI Construction (Compact Layout Tuned for 640x360 Virtual Viewport)
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	var root_ctrl: Control = Control.new()
	root_ctrl.name = "HUDRoot"
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.focus_mode = Control.FOCUS_NONE
	add_child(root_ctrl)

	_build_telemetry_panel(root_ctrl)
	_build_anatomy_panel(root_ctrl)
	_build_mini_hud_panel(root_ctrl)
	_build_debug_panel(root_ctrl)
	_build_ko_overlay(root_ctrl)
	_build_death_overlay(root_ctrl)
	_build_pause_menu()


func _make_progress_bar(fill_color: Color, max_val: float = 100.0, width_px: float = 84.0, height_px: float = 5.0) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = max_val
	bar.value = max_val
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width_px, height_px)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.focus_mode = Control.FOCUS_NONE

	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.14, 0.18, 0.92)
	bg.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("background", bg)

	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _build_mini_hud_panel(parent: Control) -> void:
	game_hud_root = Control.new()
	game_hud_root.name = "GameHUDRoot"
	game_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_hud_root.visible = false
	game_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_hud_root.focus_mode = Control.FOCUS_NONE
	parent.add_child(game_hud_root)

	# 1. Top-Left Vitals Panel (preserves public field name `mini_hud_panel`)
	mini_hud_panel = PanelContainer.new()
	mini_hud_panel.name = "MiniHUDPanel"
	mini_hud_panel.anchor_left = 0.0
	mini_hud_panel.anchor_right = 0.0
	mini_hud_panel.anchor_top = 0.0
	mini_hud_panel.anchor_bottom = 0.0
	mini_hud_panel.offset_left = 4.0
	mini_hud_panel.offset_right = 190.0
	mini_hud_panel.offset_top = 4.0
	mini_hud_panel.offset_bottom = 86.0
	mini_hud_panel.visible = false
	mini_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_hud_panel.focus_mode = Control.FOCUS_NONE
	mini_hud_panel.add_theme_stylebox_override("panel", _make_panel_style())
	game_hud_root.add_child(mini_hud_panel)

	var vitals_box: VBoxContainer = VBoxContainer.new()
	vitals_box.add_theme_constant_override("separation", 2)
	vitals_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals_box.focus_mode = Control.FOCUS_NONE
	mini_hud_panel.add_child(vitals_box)

	var bld_row: HBoxContainer = _make_hud_bar_row("Кровь", Color("#E74C3C"))
	bar_game_blood = bld_row.get_node("Bar") as ProgressBar
	lbl_game_blood = bld_row.get_node("Val") as Label
	vitals_box.add_child(bld_row)

	var shk_row: HBoxContainer = _make_hud_bar_row("Шок", Color("#F39C12"))
	bar_game_shock = shk_row.get_node("Bar") as ProgressBar
	bar_game_shock.value = 0.0
	lbl_game_shock = shk_row.get_node("Val") as Label
	vitals_box.add_child(shk_row)

	var sta_row: HBoxContainer = _make_hud_bar_row("STA", Color("#2ECC71"))
	bar_game_sta = sta_row.get_node("Bar") as ProgressBar
	lbl_game_sta = sta_row.get_node("Val") as Label
	vitals_box.add_child(sta_row)

	var mp_row: HBoxContainer = _make_hud_bar_row("MP", Color("#5C6773"))
	bar_game_mp = mp_row.get_node("Bar") as ProgressBar
	_bar_game_mp_fill_style = bar_game_mp.get_theme_stylebox("fill") as StyleBoxFlat
	lbl_game_mp = mp_row.get_node("Val") as Label
	vitals_box.add_child(mp_row)

	var poise_row: HBoxContainer = _make_hud_bar_row("Баланс", Color("#EBCB8B"))
	bar_game_poise = poise_row.get_node("Bar") as ProgressBar
	lbl_game_poise = poise_row.get_node("Val") as Label
	vitals_box.add_child(poise_row)

	var footer_row: HBoxContainer = HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 4)
	footer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_row.focus_mode = Control.FOCUS_NONE
	vitals_box.add_child(footer_row)

	lbl_game_calories = _make_label("Кал: 1000/1000", FONT_SIZE_TINY, Color("#C3D1DF"))
	footer_row.add_child(lbl_game_calories)

	lbl_mini_hud = _make_label("PEACEFUL | Bld:100% Shk:0%", FONT_SIZE_TINY, Color("#8899AA"))
	lbl_mini_hud.clip_text = true
	lbl_mini_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(lbl_mini_hud)

	lbl_game_stealth = _make_label("STEALTH: HIDDEN", FONT_SIZE_HEADER, Color("#2ECC71"))
	lbl_game_stealth.visible = false
	vitals_box.add_child(lbl_game_stealth)

	# 2. Top-Right Tempo, Calendar & Hint Chips Panel
	game_hud_top_right = PanelContainer.new()
	game_hud_top_right.name = "GameHUDTopRight"
	game_hud_top_right.anchor_left = 1.0
	game_hud_top_right.anchor_right = 1.0
	game_hud_top_right.anchor_top = 0.0
	game_hud_top_right.anchor_bottom = 0.0
	game_hud_top_right.offset_left = -216.0
	game_hud_top_right.offset_right = -4.0
	game_hud_top_right.offset_top = 4.0
	game_hud_top_right.offset_bottom = 44.0
	game_hud_top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_hud_top_right.focus_mode = Control.FOCUS_NONE
	game_hud_top_right.add_theme_stylebox_override("panel", _make_panel_style())
	game_hud_root.add_child(game_hud_top_right)

	var tr_vbox: VBoxContainer = VBoxContainer.new()
	tr_vbox.add_theme_constant_override("separation", 2)
	tr_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr_vbox.focus_mode = Control.FOCUS_NONE
	game_hud_top_right.add_child(tr_vbox)

	var tr_top: HBoxContainer = HBoxContainer.new()
	tr_top.add_theme_constant_override("separation", 6)
	tr_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr_top.focus_mode = Control.FOCUS_NONE
	tr_vbox.add_child(tr_top)

	lbl_game_tempo = _make_label("PEACEFUL 1.0x", FONT_SIZE_HEADER, Color("#88C0D0"))
	lbl_game_tempo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_top.add_child(lbl_game_tempo)

	lbl_game_calendar = _make_label("Д01 08:00", FONT_SIZE_BODY, Color("#EBCB8B"))
	lbl_game_calendar.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr_top.add_child(lbl_game_calendar)

	var chips_row: HBoxContainer = HBoxContainer.new()
	chips_row.add_theme_constant_override("separation", 3)
	chips_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips_row.focus_mode = Control.FOCUS_NONE
	tr_vbox.add_child(chips_row)

	btn_game_hint_debug = _make_button("[F1: Debug]", FONT_SIZE_TINY)
	btn_game_hint_debug.custom_minimum_size = Vector2(0.0, 14.0)
	btn_game_hint_debug.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_game_hint_debug.pressed.connect(func() -> void: toggle_debug_panel())
	chips_row.add_child(btn_game_hint_debug)

	btn_game_hint_hud = _make_button("[F2: Режим HUD]", FONT_SIZE_TINY)
	btn_game_hint_hud.custom_minimum_size = Vector2(0.0, 14.0)
	btn_game_hint_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_game_hint_hud.pressed.connect(func() -> void: toggle_compact_hud())
	chips_row.add_child(btn_game_hint_hud)

	btn_game_hint_menu = _make_button("[Esc: Меню]", FONT_SIZE_TINY)
	btn_game_hint_menu.custom_minimum_size = Vector2(0.0, 14.0)
	btn_game_hint_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_game_hint_menu.pressed.connect(func() -> void: toggle_pause_menu())
	chips_row.add_child(btn_game_hint_menu)

	# 3. Bottom-Left Active Weapon, Durability/Sharpness & Stance Badges Panel
	game_hud_weapon_panel = PanelContainer.new()
	game_hud_weapon_panel.name = "GameHUDWeaponPanel"
	game_hud_weapon_panel.anchor_left = 0.0
	game_hud_weapon_panel.anchor_right = 0.0
	game_hud_weapon_panel.anchor_top = 1.0
	game_hud_weapon_panel.anchor_bottom = 1.0
	game_hud_weapon_panel.offset_left = 4.0
	game_hud_weapon_panel.offset_right = 246.0
	game_hud_weapon_panel.offset_top = -56.0
	game_hud_weapon_panel.offset_bottom = -4.0
	game_hud_weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_hud_weapon_panel.focus_mode = Control.FOCUS_NONE
	game_hud_weapon_panel.add_theme_stylebox_override("panel", _make_panel_style())
	game_hud_root.add_child(game_hud_weapon_panel)

	var wpn_vbox: VBoxContainer = VBoxContainer.new()
	wpn_vbox.add_theme_constant_override("separation", 2)
	wpn_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn_vbox.focus_mode = Control.FOCUS_NONE
	game_hud_weapon_panel.add_child(wpn_vbox)

	var slot_row: HBoxContainer = HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 4)
	slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_row.focus_mode = Control.FOCUS_NONE
	wpn_vbox.add_child(slot_row)

	game_slot_labels.clear()
	for slot_idx: int in range(3):
		var s_lbl: Label = _make_label("[%d]" % (slot_idx + 1), FONT_SIZE_HEADER, Color("#6C7A89"))
		slot_row.add_child(s_lbl)
		game_slot_labels.append(s_lbl)

	lbl_game_weapon_name = _make_label("Short Dagger", FONT_SIZE_HEADER, Color("#ECEFF4"))
	lbl_game_weapon_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_row.add_child(lbl_game_weapon_name)

	var dur_row: HBoxContainer = HBoxContainer.new()
	dur_row.add_theme_constant_override("separation", 4)
	dur_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dur_row.focus_mode = Control.FOCUS_NONE
	wpn_vbox.add_child(dur_row)

	lbl_game_durability = _make_label("Прочн:100%", FONT_SIZE_TINY, Color("#D8DEE9"))
	bar_game_durability = _make_progress_bar(Color("#88C0D0"), 100.0, 52.0, 4.0)
	lbl_game_sharpness = _make_label("Остр:100%", FONT_SIZE_TINY, Color("#D8DEE9"))
	bar_game_sharpness = _make_progress_bar(Color("#EBCB8B"), 100.0, 52.0, 4.0)
	dur_row.add_child(lbl_game_durability)
	dur_row.add_child(bar_game_durability)
	dur_row.add_child(lbl_game_sharpness)
	dur_row.add_child(bar_game_sharpness)

	var stance_row: HBoxContainer = HBoxContainer.new()
	stance_row.add_theme_constant_override("separation", 4)
	stance_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stance_row.focus_mode = Control.FOCUS_NONE
	wpn_vbox.add_child(stance_row)

	game_stance_badges.clear()
	var badge_specs: Array[Array] = [
		["CROUCH", Color("#2ECC71")],
		["HALF-SWORD", Color("#74B9FF")],
		["HARDENING", Color("#A8E6CF")],
		["AURA", Color("#A29BFE")],
		["MANA FLY", Color("#4FD8FF")],
		["WING FLY", Color("#FFEAA7")],
		["BLOCK", Color("#FFEAA7")],
		["COUNTER!", Color("#00D2D3")],
		["DEAD ZONE", Color("#FF7F11")],
	]
	for spec: Array in badge_specs:
		var b_key: String = String(spec[0])
		var b_col: Color = spec[1] as Color
		var b_lbl: Label = _make_label("[%s]" % b_key, FONT_SIZE_TINY, b_col)
		b_lbl.visible = false
		stance_row.add_child(b_lbl)
		game_stance_badges[b_key] = b_lbl


func _make_hud_bar_row(caption: String, fill_color: Color) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.focus_mode = Control.FOCUS_NONE

	var cap: Label = _make_label(caption, FONT_SIZE_TINY, Color("#D8DEE9"))
	cap.custom_minimum_size = Vector2(34.0, 0.0)
	row.add_child(cap)

	var bar: ProgressBar = _make_progress_bar(fill_color, 100.0, 82.0, 5.0)
	bar.name = "Bar"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)

	var val_lbl: Label = _make_label("100%", FONT_SIZE_TINY, Color("#ECEFF4"))
	val_lbl.name = "Val"
	val_lbl.custom_minimum_size = Vector2(48.0, 0.0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)
	return row


func _build_ko_overlay(parent: Control) -> void:
	ko_overlay = Control.new()
	ko_overlay.name = "KOOverlay"
	ko_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ko_overlay.visible = false
	ko_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ko_overlay.focus_mode = Control.FOCUS_NONE
	parent.add_child(ko_overlay)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "KOBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.10, 0.06, 0.02, 0.56)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.focus_mode = Control.FOCUS_NONE
	ko_overlay.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.name = "KOCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.focus_mode = Control.FOCUS_NONE
	ko_overlay.add_child(center)

	ko_panel = PanelContainer.new()
	ko_panel.name = "KOPanel"
	ko_panel.custom_minimum_size = Vector2(268.0, 92.0)
	ko_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ko_panel.focus_mode = Control.FOCUS_NONE
	var kstyle: StyleBoxFlat = _make_panel_style()
	kstyle.bg_color = Color(0.11, 0.07, 0.03, 0.94)
	kstyle.border_color = Color("#F39C12")
	kstyle.set_border_width_all(2)
	kstyle.content_margin_left = 10.0
	kstyle.content_margin_right = 10.0
	kstyle.content_margin_top = 8.0
	kstyle.content_margin_bottom = 8.0
	ko_panel.add_theme_stylebox_override("panel", kstyle)
	center.add_child(ko_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.focus_mode = Control.FOCUS_NONE
	ko_panel.add_child(vbox)

	lbl_ko_title = _make_label("БЕЗ СОЗНАНИЯ (KO)", 11, Color("#FFD166"))
	lbl_ko_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_ko_title)

	lbl_ko_reason = _make_label("Болевой шок — восстановление...", FONT_SIZE_HEADER, Color("#FFF3D6"))
	lbl_ko_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_ko_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl_ko_reason)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(btn_row)

	btn_ko_recover = _make_button("Воскреснуть / Сброс KO", FONT_SIZE_BODY)
	btn_ko_recover.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_ko_recover.pressed.connect(func() -> void: recover_player_from_ko())
	btn_row.add_child(btn_ko_recover)

	btn_ko_reset_arena = _make_button("Сбросить арену", FONT_SIZE_BODY)
	btn_ko_reset_arena.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_ko_reset_arena.pressed.connect(func() -> void: reset_arena_from_death())
	btn_row.add_child(btn_ko_reset_arena)


func _build_pause_menu() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.name = "PauseLayer"
	pause_layer.layer = 65
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)

	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.visible = false
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.focus_mode = Control.FOCUS_NONE
	pause_layer.add_child(pause_overlay)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "PauseBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.04, 0.07, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.focus_mode = Control.FOCUS_NONE
	pause_overlay.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.name = "PauseCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.focus_mode = Control.FOCUS_NONE
	pause_overlay.add_child(center)

	pause_panel = PanelContainer.new()
	pause_panel.name = "PausePanel"
	pause_panel.custom_minimum_size = Vector2(310.0, 210.0)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_panel.focus_mode = Control.FOCUS_NONE
	var pstyle: StyleBoxFlat = _make_panel_style()
	pstyle.bg_color = Color(0.07, 0.08, 0.12, 0.96)
	pstyle.border_color = Color("#88C0D0")
	pstyle.set_border_width_all(2)
	pstyle.content_margin_left = 10.0
	pstyle.content_margin_right = 10.0
	pstyle.content_margin_top = 8.0
	pstyle.content_margin_bottom = 8.0
	pause_panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(pause_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.focus_mode = Control.FOCUS_NONE
	pause_panel.add_child(vbox)

	var title_lbl: Label = _make_label("ПАУЗА", 11, Color("#88C0D0"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var top_btns: HBoxContainer = HBoxContainer.new()
	top_btns.add_theme_constant_override("separation", 4)
	top_btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_btns.focus_mode = Control.FOCUS_NONE
	vbox.add_child(top_btns)

	btn_pause_resume = _make_button("Продолжить [Esc]", FONT_SIZE_BODY)
	btn_pause_resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_pause_resume.pressed.connect(func() -> void: set_pause_menu_open(false))
	top_btns.add_child(btn_pause_resume)

	btn_pause_fullscreen = _make_button("Полный экран [F11]", FONT_SIZE_BODY)
	btn_pause_fullscreen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_pause_fullscreen.pressed.connect(func() -> void: toggle_fullscreen())
	top_btns.add_child(btn_pause_fullscreen)

	var mode_row: HBoxContainer = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	mode_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(mode_row)

	btn_pause_hud_mode = _make_button("Режим HUD: Отладка [F2]", FONT_SIZE_BODY)
	btn_pause_hud_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_pause_hud_mode.pressed.connect(func() -> void: toggle_compact_hud())
	mode_row.add_child(btn_pause_hud_mode)

	btn_pause_reset_arena = _make_button("Сброс арены", FONT_SIZE_BODY)
	btn_pause_reset_arena.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_pause_reset_arena.pressed.connect(func() -> void:
		reset_arena_from_death()
		set_pause_menu_open(false)
	)
	mode_row.add_child(btn_pause_reset_arena)

	# Audio controls synced with ProceduralAudioManager
	var audio_row: HBoxContainer = HBoxContainer.new()
	audio_row.add_theme_constant_override("separation", 6)
	audio_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(audio_row)

	chk_pause_mute = _make_checkbox("Звук: Mute", FONT_SIZE_BODY)
	chk_pause_mute.toggled.connect(func(on: bool) -> void:
		if not _updating_pause_audio:
			set_audio_muted(on)
	)
	audio_row.add_child(chk_pause_mute)

	lbl_pause_volume = _make_label("Громкость: -6 дБ", FONT_SIZE_TINY, Color("#D8DEE9"))
	lbl_pause_volume.custom_minimum_size = Vector2(74.0, 0.0)
	audio_row.add_child(lbl_pause_volume)

	slider_pause_volume = HSlider.new()
	slider_pause_volume.min_value = -24.0
	slider_pause_volume.max_value = 0.0
	slider_pause_volume.step = 1.0
	slider_pause_volume.value = -6.0
	slider_pause_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_pause_volume.focus_mode = Control.FOCUS_NONE
	slider_pause_volume.mouse_filter = Control.MOUSE_FILTER_STOP
	slider_pause_volume.value_changed.connect(func(v: float) -> void:
		if not _updating_pause_audio:
			set_audio_volume_db(v)
	)
	audio_row.add_child(slider_pause_volume)

	var sep: HSeparator = HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.focus_mode = Control.FOCUS_NONE
	vbox.add_child(sep)

	var ctrl_hdr: Label = _make_label("Управление v0.2:", FONT_SIZE_HEADER, Color("#EBCB8B"))
	vbox.add_child(ctrl_hdr)

	lbl_pause_controls = _make_label(
		"WASD — движение | Space — сайдстеп / рывок / тихий перекат | Ctrl — присед (стелс) | T — отвлечь шумом\n"
		+ "ЛКМ — рубящий | Shift+ЛКМ / V — колющий | ПКМ — отбив / блок | Q — клинч / оглушение (в приседе сзади) | C — финт\n"
		+ "Tab — полумеч | H — укрепление | R — Аура / Вспышка | 1/2/3 — оружие | F — полёт\n"
		+ "E / Удерж. E (Shift+E) — вырвать клинок / подобрать / лестница | G — темп | P — восприятие | Z/X — скорость\n"
		+ "F1 — Debug-панель | F2 — Игровой/Debug HUD | F11 / Alt+Enter — полный экран | Esc — пауза",
		FONT_SIZE_TINY,
		Color("#C8D4E3")
	)
	lbl_pause_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl_pause_controls)


func _build_death_overlay(parent: Control) -> void:
	death_overlay = Control.new()
	death_overlay.name = "DeathOverlay"
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.visible = false
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.focus_mode = Control.FOCUS_NONE
	parent.add_child(death_overlay)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.08, 0.02, 0.03, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.focus_mode = Control.FOCUS_NONE
	death_overlay.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.name = "DeathCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.focus_mode = Control.FOCUS_NONE
	death_overlay.add_child(center)

	death_panel = PanelContainer.new()
	death_panel.name = "DeathPanel"
	death_panel.custom_minimum_size = Vector2(248.0, 88.0)
	death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_panel.focus_mode = Control.FOCUS_NONE
	var dstyle: StyleBoxFlat = _make_panel_style()
	dstyle.bg_color = Color(0.10, 0.04, 0.05, 0.94)
	dstyle.border_color = Color("#E74C3C")
	dstyle.set_border_width_all(2)
	dstyle.content_margin_left = 10.0
	dstyle.content_margin_right = 10.0
	dstyle.content_margin_top = 8.0
	dstyle.content_margin_bottom = 8.0
	death_panel.add_theme_stylebox_override("panel", dstyle)
	center.add_child(death_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.focus_mode = Control.FOCUS_NONE
	death_panel.add_child(vbox)

	lbl_death_title = _make_label("ВЫ ПОГИБЛИ", 12, Color("#FF6B6B"))
	lbl_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_death_title)

	lbl_death_cause = _make_label("Причина: --", FONT_SIZE_HEADER, Color("#F8D7DA"))
	lbl_death_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_death_cause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl_death_cause)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(btn_row)

	btn_respawn_player = _make_button("Воскреснуть [Space / R]", FONT_SIZE_BODY)
	btn_respawn_player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_respawn_player.pressed.connect(func() -> void: respawn_player_from_death())
	btn_row.add_child(btn_respawn_player)

	btn_reset_arena_death = _make_button("Сбросить арену", FONT_SIZE_BODY)
	btn_reset_arena_death.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_reset_arena_death.pressed.connect(func() -> void: reset_arena_from_death())
	btn_row.add_child(btn_reset_arena_death)


func _make_panel_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL_BG
	sb.border_color = COLOR_PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	return sb


func _make_label(text: String = "", font_size: int = FONT_SIZE_BODY, color: Color = Color("#E5E9F0")) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.focus_mode = Control.FOCUS_NONE
	return lbl


func _make_button(text: String, font_size: int = FONT_SIZE_BODY) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.custom_minimum_size = Vector2(0.0, 16.0)
	return btn


func _make_checkbox(text: String, font_size: int = FONT_SIZE_TINY) -> CheckBox:
	var chk: CheckBox = CheckBox.new()
	chk.text = text
	chk.add_theme_font_size_override("font_size", font_size)
	chk.focus_mode = Control.FOCUS_NONE
	chk.mouse_filter = Control.MOUSE_FILTER_STOP
	return chk


func _build_telemetry_panel(parent: Control) -> void:
	telemetry_panel = PanelContainer.new()
	telemetry_panel.name = "TelemetryPanel"
	telemetry_panel.position = Vector2(4.0, 4.0)
	telemetry_panel.size = Vector2(252.0, 128.0)
	telemetry_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	telemetry_panel.focus_mode = Control.FOCUS_NONE
	telemetry_panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(telemetry_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.focus_mode = Control.FOCUS_NONE
	telemetry_panel.add_child(vbox)

	lbl_tempo = _make_label("Tempo: PEACEFUL 1.0x | Aggro: 0 | AI: --", FONT_SIZE_HEADER, Color("#88C0D0"))
	lbl_clock = _make_label("WTS: 1.000x | act_dt: -- | spd_reg: 1.00 | perc: 1.00", FONT_SIZE_BODY, Color("#A3D9E8"))
	lbl_calendar = _make_label("Calendar: ...", FONT_SIZE_BODY, Color("#EBCB8B"))
	lbl_space = _make_label("Floor: 0 | height_z: 0.00 | Race: Human | REG: 10", FONT_SIZE_BODY, Color("#D8DEE9"))
	lbl_resources = _make_label("STA: -- | MP: -- | Cal: -- | AR: OFF", FONT_SIZE_BODY, Color("#A3BE8C"))
	lbl_weapon = _make_label("Wpn: -- | Stance: --", FONT_SIZE_BODY, Color("#ECEFF4"))

	var sep: HSeparator = HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.focus_mode = Control.FOCUS_NONE

	lbl_pen_header = _make_label("PenetrationResolver: (no strikes yet)", FONT_SIZE_BODY, Color("#D08770"))
	lbl_pen_values = _make_label("Pen: -- | Bar: -- | Armor: --", FONT_SIZE_BODY, Color("#D8DEE9"))
	lbl_pen_depth = _make_label("Depth: -- | Blunt: --", FONT_SIZE_BODY, Color("#D8DEE9"))
	lbl_clash_log = _make_label("Clash: --", FONT_SIZE_BODY, Color("#FFE875"))
	lbl_event_log = _make_label("Event: --", FONT_SIZE_BODY, Color("#FF9E80"))

	for ctrl: Control in [
		lbl_tempo,
		lbl_clock,
		lbl_calendar,
		lbl_space,
		lbl_resources,
		lbl_weapon,
		sep,
		lbl_pen_header,
		lbl_pen_values,
		lbl_pen_depth,
		lbl_clash_log,
		lbl_event_log,
	]:
		vbox.add_child(ctrl)


func _build_anatomy_panel(parent: Control) -> void:
	anatomy_panel = PanelContainer.new()
	anatomy_panel.name = "AnatomyPanel"
	anatomy_panel.anchor_left = 0.0
	anatomy_panel.anchor_right = 0.0
	anatomy_panel.anchor_top = 1.0
	anatomy_panel.anchor_bottom = 1.0
	anatomy_panel.offset_left = 4.0
	anatomy_panel.offset_right = 266.0
	anatomy_panel.offset_top = -164.0
	anatomy_panel.offset_bottom = -4.0
	anatomy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anatomy_panel.focus_mode = Control.FOCUS_NONE
	anatomy_panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(anatomy_panel)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.focus_mode = Control.FOCUS_NONE
	anatomy_panel.add_child(hbox)

	var p_col: VBoxContainer = _build_single_anatomy_column("PLAYER", player_zone_rects, true)
	p_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(p_col)

	var vsep: VSeparator = VSeparator.new()
	vsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vsep.focus_mode = Control.FOCUS_NONE
	hbox.add_child(vsep)

	var t_col: VBoxContainer = _build_single_anatomy_column("TARGET: None", target_zone_rects, false)
	t_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(t_col)


func _build_single_anatomy_column(
	title_text: String,
	zone_rect_map: Dictionary[StringName, ColorRect],
	is_player_col: bool
) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.focus_mode = Control.FOCUS_NONE

	var title_lbl: Label = _make_label(title_text, FONT_SIZE_HEADER, Color("#88C0D0") if is_player_col else Color("#BF616A"))
	col.add_child(title_lbl)
	if is_player_col:
		lbl_player_title = title_lbl
	else:
		lbl_target_title = title_lbl

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.focus_mode = Control.FOCUS_NONE
	col.add_child(top_row)

	# Mini body diagram (46 x 58 px)
	var diagram: Control = Control.new()
	diagram.custom_minimum_size = Vector2(46.0, 58.0)
	diagram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diagram.focus_mode = Control.FOCUS_NONE
	top_row.add_child(diagram)

	var layout: Dictionary[StringName, Rect2] = {
		AnatomyComponent.ZONE_HEAD: Rect2(17.0, 1.0, 12.0, 11.0),
		AnatomyComponent.ZONE_NECK: Rect2(20.0, 13.0, 6.0, 4.0),
		AnatomyComponent.ZONE_CHEST: Rect2(14.0, 18.0, 18.0, 13.0),
		AnatomyComponent.ZONE_STOMACH: Rect2(15.0, 32.0, 16.0, 9.0),
		AnatomyComponent.ZONE_LEFT_ARM: Rect2(5.0, 18.0, 8.0, 20.0),
		AnatomyComponent.ZONE_RIGHT_ARM: Rect2(33.0, 18.0, 8.0, 20.0),
		AnatomyComponent.ZONE_LEFT_LEG: Rect2(14.0, 42.0, 8.0, 15.0),
		AnatomyComponent.ZONE_RIGHT_LEG: Rect2(24.0, 42.0, 8.0, 15.0),
	}
	for zone_key: StringName in layout.keys():
		var r: Rect2 = layout[zone_key]
		var rect_node: ColorRect = ColorRect.new()
		rect_node.name = "Zone_%s" % String(zone_key)
		rect_node.position = r.position
		rect_node.size = r.size
		rect_node.color = COLOR_ZONE_HEALTHY
		rect_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect_node.focus_mode = Control.FOCUS_NONE
		diagram.add_child(rect_node)
		zone_rect_map[zone_key] = rect_node

	# Blood / shock / resources / organs beside diagram
	var stats_box: VBoxContainer = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 1)
	stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_box.focus_mode = Control.FOCUS_NONE
	top_row.add_child(stats_box)

	var l_blood: Label = _make_label("Blood: --", FONT_SIZE_TINY)
	var l_shock: Label = _make_label("Shock: --", FONT_SIZE_TINY)
	var l_res: Label = _make_label("STA:-- MP:-- Cal:--", FONT_SIZE_TINY, Color("#A3BE8C"))
	var l_organs: Label = _make_label("Org H:-- N:-- C:--", FONT_SIZE_TINY, Color("#D8DEE9"))
	var l_layers: Label = _make_label("4L Sk:-- Ms:-- Bn:-- Or:--", FONT_SIZE_TINY, Color("#88C0D0"))
	stats_box.add_child(l_blood)
	stats_box.add_child(l_shock)
	stats_box.add_child(l_res)
	stats_box.add_child(l_organs)
	stats_box.add_child(l_layers)

	var l_limbs: Label = _make_label("Limbs: --", FONT_SIZE_TINY, Color("#D08770"))
	l_limbs.clip_text = true
	col.add_child(l_limbs)

	var l_wounds: Label = _make_label("Wounds: none", FONT_SIZE_TINY, Color("#EBCB8B"))
	l_wounds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l_wounds.custom_minimum_size = Vector2(0.0, 56.0)
	l_wounds.clip_text = true
	col.add_child(l_wounds)

	if is_player_col:
		lbl_player_blood = l_blood
		lbl_player_shock = l_shock
		lbl_player_res = l_res
		lbl_player_organs = l_organs
		lbl_player_layers = l_layers
		lbl_player_limbs = l_limbs
		lbl_player_wounds = l_wounds
	else:
		lbl_target_blood = l_blood
		lbl_target_shock = l_shock
		lbl_target_res = l_res
		lbl_target_organs = l_organs
		lbl_target_layers = l_layers
		lbl_target_limbs = l_limbs
		lbl_target_wounds = l_wounds

	return col


func _build_debug_panel(parent: Control) -> void:
	debug_panel = PanelContainer.new()
	debug_panel.name = "DebugPanel"
	debug_panel.anchor_left = 1.0
	debug_panel.anchor_right = 1.0
	debug_panel.anchor_top = 0.0
	debug_panel.anchor_bottom = 1.0
	debug_panel.offset_left = -188.0
	debug_panel.offset_right = -4.0
	debug_panel.offset_top = 4.0
	debug_panel.offset_bottom = -4.0
	# Non-button panel background passes clicks through so combat input is never blocked!
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_panel.focus_mode = Control.FOCUS_NONE
	debug_panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(debug_panel)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.focus_mode = Control.FOCUS_NONE
	debug_panel.add_child(scroll)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.focus_mode = Control.FOCUS_NONE
	scroll.add_child(vbox)

	var hdr_row: HBoxContainer = HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 2)
	hdr_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(hdr_row)

	var hdr: Label = _make_label("DEBUG [F1]", FONT_SIZE_HEADER, Color("#88C0D0"))
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.add_child(hdr)

	btn_toggle_compact_hud = _make_button("Мини[F2]", FONT_SIZE_TINY)
	btn_toggle_compact_hud.tooltip_text = "Свернуть панели до компактного мини-HUD (F2)"
	btn_toggle_compact_hud.custom_minimum_size = Vector2(42.0, 14.0)
	btn_toggle_compact_hud.pressed.connect(func() -> void: toggle_compact_hud())
	hdr_row.add_child(btn_toggle_compact_hud)

	btn_hide_debug = _make_button("Скрыть", FONT_SIZE_TINY)
	btn_hide_debug.custom_minimum_size = Vector2(36.0, 14.0)
	btn_hide_debug.pressed.connect(func() -> void: toggle_debug_panel())
	hdr_row.add_child(btn_hide_debug)

	# Race Preset Switcher (Human REG<=12 vs Troll REG<=65, CON<=45)
	btn_race_preset = _make_button("Раса: Человек (REG<=12)", FONT_SIZE_BODY)
	btn_race_preset.pressed.connect(func() -> void: toggle_race_preset())
	vbox.add_child(btn_race_preset)

	# Awaken / Sleep Mana toggle button
	btn_awaken_mana = _make_button("Пробудить ману (Лимит 22)", FONT_SIZE_BODY)
	btn_awaken_mana.pressed.connect(func() -> void: toggle_player_mana_awakening())
	vbox.add_child(btn_awaken_mana)

	# Flight controls: Wings ON/OFF + Preferred FlightMode (Auto / Mana / Wings)
	var flight_row: HBoxContainer = HBoxContainer.new()
	flight_row.add_theme_constant_override("separation", 2)
	flight_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(flight_row)

	btn_toggle_wings = _make_button("Крылья: ВЫКЛ", FONT_SIZE_TINY)
	btn_toggle_wings.tooltip_text = "Включить/отключить анатомическую зону крыльев (ZONE_WINGS) для полёта на крыльях"
	btn_toggle_wings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_toggle_wings.pressed.connect(func() -> void: toggle_player_wings())
	flight_row.add_child(btn_toggle_wings)

	btn_flight_mode_pref = _make_button("Полёт: Авто", FONT_SIZE_TINY)
	btn_flight_mode_pref.tooltip_text = "Переключить предпочтительный тип полёта по клавише F (Авто / Мана / Крылья)"
	btn_flight_mode_pref.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_flight_mode_pref.pressed.connect(func() -> void: cycle_player_flight_preference())
	flight_row.add_child(btn_flight_mode_pref)

	# Quick Stat Presets: 10 / 100 / 250 / 500 + INT=300
	var preset_row: HBoxContainer = HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 2)
	preset_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preset_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(preset_row)

	btn_preset_10 = _make_button("10", FONT_SIZE_TINY)
	btn_preset_10.tooltip_text = "Человек (10, мана спит)"
	btn_preset_10.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_preset_10.pressed.connect(func() -> void: apply_stat_preset(10.0))

	btn_preset_100 = _make_button("100", FONT_SIZE_TINY)
	btn_preset_100.tooltip_text = "Мастер (100)"
	btn_preset_100.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_preset_100.pressed.connect(func() -> void: apply_stat_preset(100.0))

	btn_preset_250 = _make_button("250", FONT_SIZE_TINY)
	btn_preset_250.tooltip_text = "Бедствие (250)"
	btn_preset_250.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_preset_250.pressed.connect(func() -> void: apply_stat_preset(250.0))

	btn_preset_500 = _make_button("500", FONT_SIZE_TINY)
	btn_preset_500.tooltip_text = "Полубог (500)"
	btn_preset_500.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_preset_500.pressed.connect(func() -> void: apply_stat_preset(500.0))

	btn_preset_int300 = _make_button("INT300", FONT_SIZE_TINY)
	btn_preset_int300.tooltip_text = "INT=300 (подсветка 1-px уязвимостей и телеграфов)"
	btn_preset_int300.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_preset_int300.pressed.connect(func() -> void: apply_int_300_preset())

	for b: Button in [btn_preset_10, btn_preset_100, btn_preset_250, btn_preset_500, btn_preset_int300]:
		preset_row.add_child(b)

	# Perception Regulator toggle [P] + continuous slider (0.0 .. 1.0)
	var perc_row: HBoxContainer = HBoxContainer.new()
	perc_row.add_theme_constant_override("separation", 3)
	perc_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	perc_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(perc_row)

	btn_toggle_perception = _make_button("Воспр[P]:1.0", FONT_SIZE_TINY)
	btn_toggle_perception.tooltip_text = "Переключить SimulationClock.perception_regulator (0.0 <-> 1.0, клавиша P)"
	btn_toggle_perception.custom_minimum_size = Vector2(68.0, 15.0)
	btn_toggle_perception.pressed.connect(func() -> void: toggle_perception_regulator())
	perc_row.add_child(btn_toggle_perception)

	slider_perception = HSlider.new()
	slider_perception.min_value = 0.0
	slider_perception.max_value = 1.0
	slider_perception.step = 0.05
	slider_perception.value = SimulationClock.perception_regulator if SimulationClock != null else 1.0
	slider_perception.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_perception.focus_mode = Control.FOCUS_NONE
	slider_perception.mouse_filter = Control.MOUSE_FILTER_STOP
	slider_perception.value_changed.connect(func(v: float) -> void:
		if not _updating_sliders:
			set_perception_regulator(v)
	)
	perc_row.add_child(slider_perception)

	# Individual Stat Sliders for ALL 12 Core Stats (GDD 3.2)
	for stat_id: int in SLIDER_STATS:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.focus_mode = Control.FOCUS_NONE
		vbox.add_child(row)

		var stat_lbl: Label = _make_label("%s:10(10)" % String(StatSheet.get_stat_name(stat_id)), FONT_SIZE_TINY)
		stat_lbl.custom_minimum_size = Vector2(68.0, 0.0)
		row.add_child(stat_lbl)
		stat_slider_labels[stat_id] = stat_lbl

		var is_mana_stat: bool = (stat_id == StatSheet.Stat.M_CTRL or stat_id == StatSheet.Stat.MP_CAP)
		var slider: HSlider = HSlider.new()
		slider.min_value = 0.0 if is_mana_stat else 1.0
		slider.max_value = 500.0
		slider.step = 1.0
		slider.value = 0.0 if is_mana_stat else 10.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_NONE
		slider.mouse_filter = Control.MOUSE_FILTER_STOP
		var captured_stat: int = stat_id
		slider.value_changed.connect(func(v: float) -> void:
			if not _updating_sliders:
				set_player_base_stat(captured_stat, v)
		)
		row.add_child(slider)
		stat_sliders[stat_id] = slider

	# Anti-Regen Attack Toggle, Weak-point Highlight & Enemy AI CheckBoxes
	chk_anti_regen = _make_checkbox("Атаки Anti-Regen (огонь/Аура)")
	chk_anti_regen.button_pressed = EventBus.debug_anti_regen_attacks if EventBus != null else false
	chk_anti_regen.toggled.connect(func(on: bool) -> void: set_anti_regen_attacks(on))
	vbox.add_child(chk_anti_regen)

	chk_weak_points = _make_checkbox("Подсветка уязвимостей (1-px)")
	chk_weak_points.button_pressed = EventBus.debug_highlight_weak_points if EventBus != null else false
	chk_weak_points.toggled.connect(func(on: bool) -> void: set_weak_points_highlight(on))
	vbox.add_child(chk_weak_points)

	chk_enemy_ai = _make_checkbox("ИИ врагов (вкл/выкл)")
	chk_enemy_ai.button_pressed = true
	chk_enemy_ai.toggled.connect(func(on: bool) -> void: set_enemies_ai_enabled(on))
	vbox.add_child(chk_enemy_ai)

	# First Aid & Resources Row (STA/MP/Calories, Bandage, Splint)
	var aid_row: HBoxContainer = HBoxContainer.new()
	aid_row.add_theme_constant_override("separation", 2)
	aid_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aid_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(aid_row)

	btn_refill_resources = _make_button("STA/MP/Cal", FONT_SIZE_TINY)
	btn_refill_resources.tooltip_text = "Восполнить выносливость, ману и калории игрока"
	btn_refill_resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_refill_resources.pressed.connect(func() -> void: refill_player_resources_and_calories())

	btn_bandage_all = _make_button("Перевязка", FONT_SIZE_TINY)
	btn_bandage_all.tooltip_text = "Перевязать все кровоточащие раны игрока (bandage_zone)"
	btn_bandage_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bandage_all.pressed.connect(func() -> void: bandage_player_wounds())

	btn_splint_all = _make_button("Шина", FONT_SIZE_TINY)
	btn_splint_all.tooltip_text = "Наложить шину на все переломы игрока (splint_zone)"
	btn_splint_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_splint_all.pressed.connect(func() -> void: splint_player_fractures())

	aid_row.add_child(btn_refill_resources)
	aid_row.add_child(btn_bandage_all)
	aid_row.add_child(btn_splint_all)

	# Test Anti-Regen Strike & Heal All buttons
	var util_row1: HBoxContainer = HBoxContainer.new()
	util_row1.add_theme_constant_override("separation", 3)
	util_row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	util_row1.focus_mode = Control.FOCUS_NONE
	vbox.add_child(util_row1)

	btn_apply_anti_regen = _make_button("Ожог Anti-Regen", FONT_SIZE_TINY)
	btn_apply_anti_regen.tooltip_text = "Наложить тестовый ожог Anti-Regen (12с) на цель"
	btn_apply_anti_regen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_apply_anti_regen.pressed.connect(func() -> void: apply_test_anti_regen_to_target())

	btn_heal_player = _make_button("Исцелить всё", FONT_SIZE_TINY)
	btn_heal_player.tooltip_text = "Полное лечение игрока и восстановление конечностей"
	btn_heal_player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_heal_player.pressed.connect(func() -> void: heal_player_all())

	util_row1.add_child(btn_apply_anti_regen)
	util_row1.add_child(btn_heal_player)

	# Respawn Enemies / Reset Arena button
	btn_respawn_dummies = _make_button("Сбросить врагов / респавн арены", FONT_SIZE_TINY)
	btn_respawn_dummies.pressed.connect(func() -> void: respawn_dummies())
	vbox.add_child(btn_respawn_dummies)

	# Calendar Fast-Forward buttons (+1 day / Skip to Blood Moon day 30)
	var cal_row: HBoxContainer = HBoxContainer.new()
	cal_row.add_theme_constant_override("separation", 3)
	cal_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cal_row.focus_mode = Control.FOCUS_NONE
	vbox.add_child(cal_row)

	btn_skip_day = _make_button("+1 сутки", FONT_SIZE_TINY)
	btn_skip_day.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_skip_day.pressed.connect(func() -> void: advance_one_day())

	btn_skip_blood_moon = _make_button("Кров. Луна (Д30)", FONT_SIZE_TINY)
	btn_skip_blood_moon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_skip_blood_moon.pressed.connect(func() -> void: skip_to_blood_moon())

	cal_row.add_child(btn_skip_day)
	cal_row.add_child(btn_skip_blood_moon)

	var sep2: HSeparator = HSeparator.new()
	sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep2.focus_mode = Control.FOCUS_NONE
	vbox.add_child(sep2)

	var controls_lbl: Label = _make_label(
		"WASD | LMB Slash | Shift+LMB/V Thrust | Q Shove/Sweep/Throw/Blunt\nRMB Deflect/Block | Space Sidestep/Dash | H Harden | Tab HalfSwd | C Feint\nG Tempo | P Perc | R Aura/Burst | 1/2/3 Wpn | F Fly | E/Shift+E Int | Z/X Spd | F1/F2 HUD | F11 Fullscr",
		FONT_SIZE_TINY,
		Color("#9AA5B8")
	)
	controls_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(controls_lbl)


# ---------------------------------------------------------------------------
# Public Cheat / Debug Actions
# ---------------------------------------------------------------------------

func toggle_race_preset() -> StatSheet.RacePreset:
	var player: PlayerController = _find_player()
	if player == null or player.stat_sheet == null:
		return StatSheet.RacePreset.HUMAN
	var next_preset: StatSheet.RacePreset = (
		StatSheet.RacePreset.TROLL
		if player.stat_sheet.race_preset == StatSheet.RacePreset.HUMAN
		else StatSheet.RacePreset.HUMAN
	)
	set_player_race_preset(next_preset)
	return next_preset


func set_player_race_preset(preset: StatSheet.RacePreset) -> void:
	var player: PlayerController = _find_player()
	if player == null or player.stat_sheet == null:
		return
	player.stat_sheet.apply_race_preset(preset, false)
	_sync_controls_from_player()
	_refresh_all_views()


func toggle_player_mana_awakening() -> bool:
	var player: PlayerController = _find_player()
	if player == null or player.stat_sheet == null:
		return false
	var next_state: bool = not player.stat_sheet.mana_awakened
	player.stat_sheet.set_mana_awakened(next_state, 10.0, 10.0)
	if next_state:
		player.refill_resources()
	else:
		player.set_aura_active(false)
		player.current_mp = 0.0
	_sync_controls_from_player()
	_refresh_all_views()
	return next_state


func toggle_player_wings() -> bool:
	var player: PlayerController = _find_player()
	if player == null:
		return false
	return set_player_wings(not player.has_wings)


func set_player_wings(enabled: bool) -> bool:
	var player: PlayerController = _find_player()
	if player == null:
		return false
	var res: bool = player.set_has_wings(enabled)
	_last_special_event_text = "Крылья: %s" % ("ВКЛ" if res else "ВЫКЛ")
	_refresh_all_views()
	return res


func cycle_player_flight_preference() -> VerticalityComponent.PreferredFlightMode:
	var player: PlayerController = _find_player()
	if player == null:
		return VerticalityComponent.PreferredFlightMode.AUTO
	var next_pref: int = (int(player.get_preferred_flight_mode()) + 1) % 3
	return set_player_flight_preference(next_pref as VerticalityComponent.PreferredFlightMode)


func set_player_flight_preference(pref: VerticalityComponent.PreferredFlightMode) -> VerticalityComponent.PreferredFlightMode:
	var player: PlayerController = _find_player()
	if player == null:
		return VerticalityComponent.PreferredFlightMode.AUTO
	player.set_preferred_flight_mode(pref)
	_last_special_event_text = "Полёт [F]: %s" % VerticalityComponent.get_preferred_flight_mode_name(pref)
	_refresh_all_views()
	return pref


func apply_stat_preset(preset_value: float) -> void:
	var player: PlayerController = _find_player()
	if player == null or player.stat_sheet == null:
		return
	var clamped: float = clampf(preset_value, 1.0, 500.0)
	if clamped <= StatSheet.HUMAN_REFERENCE:
		# Reset cleanly back to baseline unawakened Human (GDD 14.4)
		player.set_aura_active(false)
		player.stat_sheet.set_mana_awakened(false)
		player.stat_sheet.set_all_base_stats(clamped, false)
		player.stat_sheet.set_base_stat(StatSheet.Stat.MP_CAP, 0.0)
		player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 0.0)
		player.current_mp = 0.0
	else:
		# Presets above human racial cap (100/250/500) awaken mana so Master/Disaster/Demigod stats are active
		if clamped > StatSheet.DEFAULT_HUMAN_RACIAL_CAP and not player.stat_sheet.mana_awakened:
			player.stat_sheet.awaken_mana(clamped, clamped)
		player.stat_sheet.set_all_base_stats(clamped, player.stat_sheet.mana_awakened)
	player.refill_resources()
	player.refresh_weapon_visual()
	_sync_controls_from_player()
	_refresh_all_views()


## Quick preset for testing INT >= 300 auto weak-point highlighting & INT + TP Intention Reading.
func apply_int_300_preset() -> void:
	var player: PlayerController = _find_player()
	if player == null or player.stat_sheet == null:
		return
	if not player.stat_sheet.mana_awakened:
		player.stat_sheet.awaken_mana(30.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.INT, 300.0)
	if player.stat_sheet.get_base_stat(StatSheet.Stat.TP) < 50.0:
		player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 50.0)
	player.refill_resources()
	_sync_controls_from_player()
	_refresh_all_views()


func set_player_base_stat(stat_id: int, value: float) -> void:
	var player: PlayerController = _find_player()
	if player == null or player.stat_sheet == null:
		return
	player.stat_sheet.set_base_stat(stat_id, value)
	if stat_id == StatSheet.Stat.M_CTRL and player.stat_sheet.mana_awakened:
		player.refresh_weapon_visual()
	if stat_id == StatSheet.Stat.STA:
		player.current_stamina = minf(player.current_stamina, player.stat_sheet.get_max_stamina())
	if stat_id == StatSheet.Stat.MP_CAP:
		player.current_mp = minf(player.current_mp, player.stat_sheet.get_max_mp())
	if stat_id == StatSheet.Stat.CON:
		player.max_poise = 50.0 + player.stat_sheet.get_stat(StatSheet.Stat.CON) * 2.0
		player.current_poise = minf(player.current_poise, player.max_poise)
	_refresh_all_views()


func toggle_perception_regulator() -> float:
	if SimulationClock == null:
		return 1.0
	var new_val: float = SimulationClock.toggle_perception_regulator()
	_refresh_all_views()
	return new_val


func set_perception_regulator(value: float) -> float:
	if SimulationClock == null:
		return 1.0
	SimulationClock.perception_regulator = clampf(value, SimulationClock.MIN_PERCEPTION_REGULATOR, SimulationClock.MAX_PERCEPTION_REGULATOR)
	_refresh_all_views()
	return SimulationClock.perception_regulator


func refill_player_resources_and_calories() -> bool:
	var player: PlayerController = _find_player()
	if player == null:
		return false
	player.refill_resources()
	if player.anatomy != null:
		player.anatomy.calories = player.anatomy.max_calories
	_last_special_event_text = "Refilled STA/MP/Calories"
	_refresh_all_views()
	return true


func bandage_player_wounds() -> int:
	var player: PlayerController = _find_player()
	if player == null or player.anatomy == null:
		return 0
	var total: int = 0
	for z: StringName in player.anatomy.get_zone_names():
		total += player.anatomy.bandage_zone(z)
	_last_special_event_text = "Bandaged %d bleeding wound(s)" % total
	_refresh_all_views()
	return total


func splint_player_fractures() -> int:
	var player: PlayerController = _find_player()
	if player == null or player.anatomy == null:
		return 0
	var total: int = 0
	for z: StringName in player.anatomy.get_zone_names():
		total += player.anatomy.splint_zone(z)
	_last_special_event_text = "Splinted %d fracture(s)" % total
	_refresh_all_views()
	return total


func recover_player_from_ko() -> void:
	heal_player_all()


func respawn_player_from_death() -> void:
	_last_player_death_cause = ""
	_last_player_death_zone = &""
	heal_player_all()


func reset_arena_from_death() -> void:
	_last_player_death_cause = ""
	_last_player_death_zone = &""
	heal_player_all()
	respawn_dummies()


func set_anti_regen_attacks(enabled: bool) -> void:
	if EventBus != null:
		EventBus.set_debug_anti_regen_attacks(enabled)
	if chk_anti_regen != null and chk_anti_regen.button_pressed != enabled:
		chk_anti_regen.set_pressed_no_signal(enabled)
	_refresh_all_views()


## Applies a test Anti-Regen burn directly to the current target (or Troll Berserker / nearest enemy).
func apply_test_anti_regen_to_target(duration_sec: float = 12.0) -> bool:
	var target: CombatActor = _resolve_debug_target()
	if target == null or target.anatomy == null:
		return false
	target.anatomy.apply_burn_anti_regen(AnatomyComponent.ZONE_CHEST, duration_sec)
	target.anatomy.apply_anti_regen(&"", duration_sec, true)
	last_attacked_target = target
	_refresh_all_views()
	return true


func set_weak_points_highlight(enabled: bool) -> void:
	if EventBus != null:
		EventBus.set_debug_highlight_weak_points(enabled)
	if chk_weak_points != null and chk_weak_points.button_pressed != enabled:
		chk_weak_points.set_pressed_no_signal(enabled)


func set_enemies_ai_enabled(enabled: bool) -> void:
	var arena: TestArena = _find_arena()
	if arena != null:
		arena.set_all_enemies_ai_enabled(enabled)
	if chk_enemy_ai != null and chk_enemy_ai.button_pressed != enabled:
		chk_enemy_ai.set_pressed_no_signal(enabled)


func heal_player_all() -> void:
	var player: PlayerController = _find_player()
	if player == null:
		return
	player.revive_and_heal_all()
	var arena: TestArena = _find_arena()
	if arena != null:
		arena.reset_all_enemy_aggro(2.5)
	_refresh_all_views()


func respawn_dummies() -> void:
	var arena: TestArena = _find_arena()
	if arena == null:
		return
	last_attacked_target = null
	_last_outcome_data = {}
	_last_pen_data = {}
	_last_clash_data = {}
	_last_special_event_text = "Arena & enemies reset"
	if arena.has_method("reset_arena_and_respawn"):
		arena.reset_arena_and_respawn()
	else:
		arena.respawn_test_dummies()
	_refresh_all_views()


func advance_one_day() -> void:
	if WorldCalendar != null:
		WorldCalendar.fast_forward_days(1.0, false)
	_refresh_all_views()


func skip_to_blood_moon() -> void:
	if WorldCalendar == null:
		return
	var cur_dom: int = WorldCalendar.get_day_of_month()
	var days_to_skip: int = (WorldCalendar.BLOOD_MOON_DAY - cur_dom) if cur_dom < WorldCalendar.BLOOD_MOON_DAY else WorldCalendar.DAYS_PER_MONTH
	WorldCalendar.fast_forward_days(float(days_to_skip), false)
	_refresh_all_views()


# ---------------------------------------------------------------------------
# Live Telemetry & Anatomy Refresh
# ---------------------------------------------------------------------------

func _sync_controls_from_player() -> void:
	var player: PlayerController = _find_player()
	if player == null or player.stat_sheet == null:
		return
	_updating_sliders = true
	if slider_perception != null and SimulationClock != null:
		slider_perception.value = SimulationClock.perception_regulator
	for stat_id: int in SLIDER_STATS:
		if stat_sliders.has(stat_id):
			stat_sliders[stat_id].value = player.stat_sheet.get_base_stat(stat_id)
	_updating_sliders = false


func _refresh_all_views() -> void:
	var player: PlayerController = _find_player()
	_refresh_telemetry(player)
	_refresh_anatomy_column(
		player,
		player_zone_rects,
		lbl_player_title,
		lbl_player_blood,
		lbl_player_shock,
		lbl_player_res,
		lbl_player_organs,
		lbl_player_layers,
		lbl_player_limbs,
		lbl_player_wounds,
		true
	)
	var valid_target: CombatActor = last_attacked_target if (last_attacked_target != null and is_instance_valid(last_attacked_target)) else null
	_refresh_anatomy_column(
		valid_target,
		target_zone_rects,
		lbl_target_title,
		lbl_target_blood,
		lbl_target_shock,
		lbl_target_res,
		lbl_target_organs,
		lbl_target_layers,
		lbl_target_limbs,
		lbl_target_wounds,
		false
	)
	_refresh_debug_panel_labels(player)
	_refresh_mini_hud(player)
	_update_ko_overlay(player)
	_update_death_overlay(player)
	if btn_pause_hud_mode != null:
		btn_pause_hud_mode.text = "Режим HUD: Игровой [F2]" if compact_hud_mode else "Режим HUD: Отладка [F2]"


func _refresh_mini_hud(player: PlayerController) -> void:
	var is_overdrive: bool = SimulationClock.is_combat_overdrive()
	var tempo_s: String = "OVERDRIVE" if is_overdrive else "PEACEFUL"

	if lbl_game_tempo != null:
		lbl_game_tempo.text = "COMBAT OVERDRIVE" if is_overdrive else "PEACEFUL 1.0x"
		lbl_game_tempo.add_theme_color_override("font_color", Color("#FF7675") if is_overdrive else Color("#88C0D0"))
	if lbl_game_calendar != null and WorldCalendar != null:
		var moon_badge: String = " | КРОВ. ЛУНА!" if WorldCalendar.is_blood_moon() else (" | НОЧЬ" if WorldCalendar.is_night() else "")
		lbl_game_calendar.text = "Д%02d %02d:%02d%s" % [
			WorldCalendar.get_day_of_month(),
			WorldCalendar.get_hour(),
			WorldCalendar.get_minute(),
			moon_badge,
		]
		lbl_game_calendar.add_theme_color_override(
			"font_color",
			Color("#FF5555") if WorldCalendar.is_blood_moon() else (Color("#A29BFE") if WorldCalendar.is_night() else Color("#EBCB8B"))
		)

	if player == null or player.anatomy == null or player.stat_sheet == null:
		if lbl_mini_hud != null:
			lbl_mini_hud.text = "%s | [F1:Dbg F2:Full]" % tempo_s
		return

	var bld_pct: float = player.anatomy.get_blood_ratio() * 100.0
	var shock_pct: float = clampf(player.anatomy.shock_level, 0.0, 100.0)
	var max_sta: float = maxf(1.0, player.stat_sheet.get_max_stamina())
	var max_mp: float = player.stat_sheet.get_max_mp()
	var mp_awake: bool = player.stat_sheet.mana_awakened
	var max_poise: float = maxf(1.0, player.max_poise)

	if bar_game_blood != null:
		bar_game_blood.max_value = 100.0
		bar_game_blood.value = clampf(bld_pct, 0.0, 100.0)
	if lbl_game_blood != null:
		lbl_game_blood.text = "%.0f%%" % bld_pct

	if bar_game_shock != null:
		bar_game_shock.max_value = 100.0
		bar_game_shock.value = shock_pct
	if lbl_game_shock != null:
		lbl_game_shock.text = "%.0f%%" % shock_pct

	if bar_game_sta != null:
		bar_game_sta.max_value = max_sta
		bar_game_sta.value = clampf(player.current_stamina, 0.0, max_sta)
	if lbl_game_sta != null:
		lbl_game_sta.text = "%.0f/%.0f" % [player.current_stamina, max_sta]

	if bar_game_mp != null:
		bar_game_mp.max_value = maxf(1.0, max_mp)
		bar_game_mp.value = clampf(player.current_mp, 0.0, maxf(1.0, max_mp)) if mp_awake else 0.0
	if _bar_game_mp_fill_style != null:
		_bar_game_mp_fill_style.bg_color = Color("#4EA8DE") if mp_awake else Color("#5C6773")
	if lbl_game_mp != null:
		lbl_game_mp.text = ("%.0f/%.0f" % [player.current_mp, max_mp]) if mp_awake else "Спит"
		lbl_game_mp.add_theme_color_override("font_color", Color("#A9D6FF") if mp_awake else Color("#7F8C8D"))

	if bar_game_poise != null:
		bar_game_poise.max_value = max_poise
		bar_game_poise.value = clampf(player.current_poise, 0.0, max_poise)
	if lbl_game_poise != null:
		lbl_game_poise.text = "%.0f/%.0f" % [player.current_poise, max_poise]

	if lbl_game_calories != null:
		lbl_game_calories.text = "Кал:%.0f/%.0f" % [player.anatomy.calories, player.anatomy.max_calories]

	var active_wpn: WeaponData = player.get_active_weapon()
	var wname: String = active_wpn.display_name if active_wpn != null else "Unarmed"
	if lbl_mini_hud != null:
		lbl_mini_hud.text = "%s | %s" % [tempo_s, wname]

	# Weapon slots & weapon condition bars
	for i: int in range(game_slot_labels.size()):
		var slbl: Label = game_slot_labels[i]
		var has_wpn: bool = i < player.weapon_slots.size() and player.weapon_slots[i] != null
		var is_cur: bool = (i == player.active_weapon_index)
		slbl.text = "[%d]" % (i + 1)
		if is_cur:
			slbl.add_theme_color_override("font_color", Color("#FFD166"))
		elif has_wpn:
			slbl.add_theme_color_override("font_color", Color("#A8B8C8"))
		else:
			slbl.add_theme_color_override("font_color", Color("#49535E"))

	if lbl_game_weapon_name != null:
		lbl_game_weapon_name.text = wname

	var dur_pct: float = (active_wpn.durability / maxf(1.0, active_wpn.max_durability) * 100.0) if (active_wpn != null and not active_wpn.is_unarmed) else 100.0
	var sharp_pct: float = (active_wpn.get_sharpness_ratio() * 100.0) if (active_wpn != null and not active_wpn.is_unarmed) else 100.0
	if bar_game_durability != null:
		bar_game_durability.value = clampf(dur_pct, 0.0, 100.0)
	if lbl_game_durability != null:
		lbl_game_durability.text = "Прочн:%.0f%%" % dur_pct
	if bar_game_sharpness != null:
		bar_game_sharpness.value = clampf(sharp_pct, 0.0, 100.0)
	if lbl_game_sharpness != null:
		lbl_game_sharpness.text = "Остр:%.0f%%" % sharp_pct

	# Stance & warning badges
	var arena: TestArena = _find_arena()
	var in_dead_zone: bool = false
	if arena != null and arena.combat_reticle != null:
		in_dead_zone = bool(arena.combat_reticle.last_state.get("in_dead_zone", false))
	var fmode: VerticalityComponent.FlightMode = player.get_flight_mode()
	var badge_states: Dictionary[String, bool] = {
		"CROUCH": player.is_crouching,
		"HALF-SWORD": player.half_swording,
		"HARDENING": player.is_hardening_active(),
		"AURA": player.aura_active,
		"MANA FLY": player.is_flying() and fmode == VerticalityComponent.FlightMode.MANA_FLIGHT,
		"WING FLY": player.is_flying() and fmode == VerticalityComponent.FlightMode.WING_FLIGHT,
		"BLOCK": player.is_blocking or player.parry_window_timer > 0.0,
		"COUNTER!": player.counter_window_timer > 0.0,
		"DEAD ZONE": in_dead_zone,
	}
	for b_key: String in game_stance_badges.keys():
		game_stance_badges[b_key].visible = bool(badge_states.get(b_key, false))

	var stealth_st: Dictionary = compute_player_stealth_status(player, arena)
	if lbl_game_stealth != null:
		lbl_game_stealth.visible = bool(stealth_st.get("visible", false))
		if lbl_game_stealth.visible:
			lbl_game_stealth.text = String(stealth_st.get("text", "STEALTH: HIDDEN"))
			lbl_game_stealth.add_theme_color_override("font_color", stealth_st.get("color", Color("#2ECC71")) as Color)


func compute_player_stealth_status(player: PlayerController, arena: TestArena = null) -> Dictionary:
	var result: Dictionary = {
		"visible": false,
		"state": &"NONE",
		"text": "",
		"color": Color("#2ECC71"),
		"in_cover": false,
		"max_suspicion": 0.0,
	}
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return result
	var resolved_arena: TestArena = arena if arena != null else _find_arena()
	var in_cover: bool = resolved_arena != null and resolved_arena.is_entity_in_stealth_cover(player)
	result["in_cover"] = in_cover

	var any_combat: bool = false
	var any_caution: bool = false
	var max_susp: float = 0.0
	if is_inside_tree():
		for n: Node in get_tree().get_nodes_in_group(&"enemies"):
			if not (n is EnemyDummy):
				continue
			var enemy: EnemyDummy = n as EnemyDummy
			if not enemy.is_alive() or (enemy.anatomy != null and enemy.anatomy.is_unconscious):
				continue
			max_susp = maxf(max_susp, enemy.suspicion_level)
			if enemy.ai_state == EnemyDummy.AIState.COMBAT:
				any_combat = true
			elif enemy.ai_state == EnemyDummy.AIState.SEARCH or enemy.suspicion_level >= 0.05:
				any_caution = true
	result["max_suspicion"] = max_susp

	var show_stealth: bool = player.is_crouching or in_cover or any_caution
	if not show_stealth:
		return result

	result["visible"] = true
	if any_combat:
		result["state"] = &"DETECTED"
		result["text"] = "STEALTH: DETECTED"
		result["color"] = Color("#FF5252")
	elif any_caution:
		result["state"] = &"CAUTION"
		result["text"] = "STEALTH: CAUTION (%d%%)" % int(round(max_susp * 100.0)) if max_susp >= 0.05 else "STEALTH: CAUTION"
		result["color"] = Color("#F1C40F")
	else:
		result["state"] = &"HIDDEN"
		result["text"] = "STEALTH: HIDDEN [ТЕНЬ]" if in_cover else "STEALTH: HIDDEN"
		result["color"] = Color("#2ECC71")
	return result


func _update_ko_overlay(player: PlayerController) -> void:
	if ko_overlay == null:
		return
	var is_ko_now: bool = (
		player != null
		and player.is_alive()
		and player.anatomy != null
		and player.anatomy.is_unconscious
	)
	ko_overlay.visible = is_ko_now
	if not is_ko_now or lbl_ko_reason == null:
		return
	var reason: String = player.anatomy.knockout_reason
	if reason == "hemorrhagic_shock" or player.anatomy.knockout_timer < 0.0:
		var bld_pct: float = player.anatomy.get_blood_ratio() * 100.0
		lbl_ko_reason.text = "Критическая кровопотеря (кровь %.0f%%) — автовыход невозможен!" % bld_pct
		lbl_ko_reason.add_theme_color_override("font_color", Color("#FF7675"))
	else:
		lbl_ko_reason.text = "Болевой шок (%.0f%%) — восстановление через %.1f с" % [
			player.anatomy.shock_level,
			maxf(0.0, player.anatomy.knockout_timer),
		]
		lbl_ko_reason.add_theme_color_override("font_color", Color("#FFF3D6"))


func _update_death_overlay(player: PlayerController) -> void:
	if death_overlay == null:
		return
	var is_dead_now: bool = (player != null and not player.is_alive())
	death_overlay.visible = is_dead_now
	if not is_dead_now:
		return
	var cause_str: String = _last_player_death_cause if _last_player_death_cause != "" else "fatal_trauma"
	var zone_str: String = String(_last_player_death_zone) if _last_player_death_zone != &"" else "Body"
	if lbl_death_cause != null:
		lbl_death_cause.text = "Причина: %s [%s]" % [cause_str, zone_str]


func _refresh_telemetry(player: PlayerController) -> void:
	if lbl_clock == null:
		return

	# TempoMode, active aggro count & nearby enemy AI states (PATROL / COMBAT / SEARCH)
	var is_overdrive: bool = SimulationClock.is_combat_overdrive()
	var tempo_str: String = "COMBAT_OVERDRIVE" if is_overdrive else "PEACEFUL 1.0x"
	var aggro_count: int = SimulationClock.active_aggro_ids.size()
	var ai_summary: String = _build_enemy_ai_summary()
	lbl_tempo.text = "Tempo: %s | Aggro: %d | AI: %s" % [tempo_str, aggro_count, ai_summary]
	lbl_tempo.add_theme_color_override("font_color", Color("#FF7675") if is_overdrive else Color("#88C0D0"))

	# SimulationClock telemetry
	lbl_clock.text = "WTS: %.3fx | act_dt: %.4fs | spd_reg: %.2f | perc: %.2f" % [
		SimulationClock.get_world_time_scale(),
		SimulationClock.player_action_delta,
		SimulationClock.speed_regulator,
		SimulationClock.perception_regulator,
	]

	# WorldCalendar telemetry
	var moon_str: String = "BLOOD MOON!" if WorldCalendar.is_blood_moon() else ("Night" if WorldCalendar.is_night() else "Day")
	lbl_calendar.text = "Y%d M%d D%02d %02d:%02d | Stage: %d/24 | %s" % [
		WorldCalendar.get_year(),
		WorldCalendar.get_month(),
		WorldCalendar.get_day_of_month(),
		WorldCalendar.get_hour(),
		WorldCalendar.get_minute(),
		WorldCalendar.get_world_stage(),
		moon_str,
	]
	lbl_calendar.add_theme_color_override("font_color", Color("#FF5555") if WorldCalendar.is_blood_moon() else Color("#EBCB8B"))

	if player != null and player.stat_sheet != null:
		if not player.last_flight_feedback.is_empty() and player.last_flight_feedback != _last_seen_flight_feedback:
			_last_seen_flight_feedback = player.last_flight_feedback
			_last_special_event_text = player.last_flight_feedback
		var race_name: String = String(StatSheet.get_race_preset_name(player.stat_sheet.race_preset))
		var fly_tag: String = VerticalityComponent.get_flight_mode_name(player.get_flight_mode())
		lbl_space.text = "Flr:%d z:%.2f [%s] | %s REG:%.0f INT:%.0f | Skin:%.0f Circ:+%d" % [
			player.get_floor_level(),
			player.get_height_z(),
			fly_tag,
			race_name,
			player.stat_sheet.get_stat(StatSheet.Stat.REG),
			player.stat_sheet.get_stat(StatSheet.Stat.INT),
			player.stat_sheet.get_mana_skin_density(),
			int(player.stat_sheet.get_circulation_stat_bonus()),
		]
		var cal_cur: float = player.anatomy.calories if player.anatomy != null else 0.0
		var cal_max: float = player.anatomy.max_calories if player.anatomy != null else 1000.0
		var p_ar: bool = player.anatomy != null and player.anatomy.is_anti_regen_active()
		lbl_resources.text = "STA:%.0f/%.0f MP:%.0f/%.0f Cal:%.0f/%.0f | AR:%s" % [
			player.current_stamina,
			player.stat_sheet.get_max_stamina(),
			player.current_mp,
			player.stat_sheet.get_max_mp(),
			cal_cur,
			cal_max,
			"ON!" if p_ar else "OFF",
		]
		var active_wpn: WeaponData = player.get_active_weapon()
		var wpn_name: String = active_wpn.display_name if active_wpn != null else "Unarmed (Fists)"
		var sharp_pct: float = active_wpn.get_sharpness_ratio() * 100.0 if active_wpn != null else 100.0
		var dur_val: float = active_wpn.durability if active_wpn != null else 0.0
		var ctrl_warn: String = " !CTRL" if player.stat_sheet.has_control_deficit() else ""
		var cnt_tag: String = " CNT!" if player.counter_window_timer > 0.0 else ""
		var ar_atk_on: bool = EventBus != null and EventBus.debug_anti_regen_attacks
		lbl_weapon.text = "%s (%.0f%% d%.0f) | HS:%s Hrd:%s Aura:%s AR:%s%s%s" % [
			wpn_name,
			sharp_pct,
			dur_val,
			"ON" if player.half_swording else "OFF",
			"ON" if player.is_hardening_active() else "OFF",
			"ON" if player.aura_active else "OFF",
			"ON" if ar_atk_on else "OFF",
			ctrl_warn,
			cnt_tag,
		]
	else:
		lbl_space.text = "Flr:-- z:-- | Race:--"
		lbl_resources.text = "STA:-- MP:-- Cal:-- | AR:OFF"
		lbl_weapon.text = "Wpn:-- | HS:OFF Hrd:OFF Aura:OFF"

	# PenetrationResolver & Combat Outcome log
	if not _last_outcome_data.is_empty():
		var atk_name: String = String(_last_outcome_data.get("attacker_name", "?"))
		var tgt_name: String = String(_last_outcome_data.get("target_name", "?"))
		var zone_str: String = String(_last_outcome_data.get("zone", "?"))
		var raw_outcome: String = String(_last_outcome_data.get("outcome", ""))
		if raw_outcome == "out_of_vertical_reach":
			lbl_pen_header.add_theme_color_override("font_color", Color("#FF7979"))
			lbl_pen_header.text = "%s->%s: OUT OF VERTICAL REACH (Press F!)" % [atk_name, tgt_name]
			lbl_pen_values.text = "Altitude z=%.1f vs target z=%.1f | reach=%.1f" % [
				float(_last_outcome_data.get("attacker_height_z", 0.0)),
				float(_last_outcome_data.get("target_height_z", 0.0)),
				float(_last_outcome_data.get("vertical_reach", 0.0)),
			]
			lbl_pen_depth.text = "Hint: Press F to toggle Flight (z=1.5)!"
		else:
			lbl_pen_header.add_theme_color_override("font_color", Color("#D08770"))
			var outcome_str: String = raw_outcome.to_upper()
			var wp_str: String = "WP" if bool(_last_outcome_data.get("is_weak_point", false)) else "BODY"
			lbl_pen_header.text = "%s->%s [%s|%s]: %s" % [atk_name, tgt_name, zone_str, wp_str, outcome_str]
			_refresh_penetration_numbers()
	elif not _last_pen_data.is_empty():
		lbl_pen_header.add_theme_color_override("font_color", Color("#D08770"))
		var wp_str: String = "WP" if bool(_last_pen_data.get("is_weak_point", false)) else "BODY"
		lbl_pen_header.text = "Penetration [%s]: %s" % [wp_str, "PENETRATED" if bool(_last_pen_data.get("penetrated", false)) else "STOPPED"]
		_refresh_penetration_numbers()
	else:
		lbl_pen_header.add_theme_color_override("font_color", Color("#D08770"))
		lbl_pen_header.text = "PenetrationResolver: (no strikes yet)"
		lbl_pen_values.text = "Pen: -- vs Bar: -- (Armor: --)"
		lbl_pen_depth.text = "Depth: -- | Blunt: --"

	# Blade Clash log
	if not _last_clash_data.is_empty():
		var win_i: int = int(_last_clash_data.get("winner", 0))
		var win_s: String = "DRAW" if win_i == 0 else ("A WIN" if win_i == 1 else "B WIN")
		var brk_s: String = ""
		if bool(_last_clash_data.get("weapon_a_broken", false)):
			brk_s += " A:BRK"
		if bool(_last_clash_data.get("weapon_b_broken", false)):
			brk_s += " B:BRK"
		lbl_clash_log.text = "Clash: %s (STR %.0f/%.0f) Dur -%.0f/-%.0f Cnt:%.2fs%s" % [
			win_s,
			float(_last_clash_data.get("str_score_a", 0.0)),
			float(_last_clash_data.get("str_score_b", 0.0)),
			float(_last_clash_data.get("weapon_a_durability_loss", 0.0)),
			float(_last_clash_data.get("weapon_b_durability_loss", 0.0)),
			float(_last_clash_data.get("counter_window_sec", 0.0)),
			brk_s,
		]
	else:
		lbl_clash_log.text = "Clash: --"

	# Special Events log (Wall Slam / Dismemberment / LodgedWeapon / Anti-Regen)
	lbl_event_log.text = "Event: %s" % _last_special_event_text


func _refresh_penetration_numbers() -> void:
	if not _last_pen_data.is_empty():
		var dz_tag: String = " DZ!" if bool(_last_pen_data.get("in_dead_zone", false)) else ""
		var burst_tag: String = " BURST!" if bool(_last_pen_data.get("aura_burst", false)) else ""
		lbl_pen_values.text = "Pen: %.1f vs Bar: %.1f (Arm:%.1f)%s%s" % [
			float(_last_pen_data.get("penetration", 0.0)),
			float(_last_pen_data.get("barrier_depth", 0.0)),
			float(_last_pen_data.get("armor_barrier", 0.0)),
			dz_tag,
			burst_tag,
		]
		lbl_pen_depth.text = "Depth: %.1f | Blunt: %.1f | Aura: %s" % [
			float(_last_pen_data.get("effective_depth", 0.0)),
			float(_last_pen_data.get("blunt_impulse", 0.0)),
			"ON" if bool(_last_pen_data.get("aura_active", false)) else "OFF",
		]
	else:
		lbl_pen_values.text = "Pen: -- vs Bar: -- (Armor: --)"
		lbl_pen_depth.text = "Depth: -- | Blunt: --"


func _build_enemy_ai_summary() -> String:
	if not is_inside_tree():
		return "--"
	var parts: PackedStringArray = PackedStringArray()
	for n: Node in get_tree().get_nodes_in_group(&"enemies"):
		if n is EnemyDummy and is_instance_valid(n):
			var e: EnemyDummy = n as EnemyDummy
			var tag: String = "R1"
			if e.preset == EnemyDummy.EnemyPreset.TROLL_BERSERKER:
				tag = "Tr"
			elif e.preset == EnemyDummy.EnemyPreset.RANK_6_GUARD:
				tag = "R6"
			var st: String = "DEAD"
			if e.is_alive():
				match e.ai_state:
					EnemyDummy.AIState.PATROL:
						st = "PATROL"
					EnemyDummy.AIState.COMBAT:
						st = "COMBAT"
					EnemyDummy.AIState.SEARCH:
						st = "SEARCH"
			parts.append("%s:%s" % [tag, st])
	return " ".join(parts) if not parts.is_empty() else "none"


func _refresh_anatomy_column(
	actor: CombatActor,
	zone_rect_map: Dictionary[StringName, ColorRect],
	title_lbl: Label,
	blood_lbl: Label,
	shock_lbl: Label,
	res_lbl: Label,
	organs_lbl: Label,
	layers_lbl: Label,
	limbs_lbl: Label,
	wounds_lbl: Label,
	is_player_col: bool
) -> void:
	if blood_lbl == null:
		return
	if actor == null or actor.anatomy == null:
		if title_lbl != null:
			title_lbl.text = "PLAYER" if is_player_col else "TARGET: None"
		for rect_node: ColorRect in zone_rect_map.values():
			rect_node.color = Color(0.25, 0.28, 0.33, 0.8)
		blood_lbl.text = "Blood: --"
		shock_lbl.text = "Shock: --"
		res_lbl.text = "STA:-- MP:-- Cal:--"
		organs_lbl.text = "Org H:-- N:-- C:--"
		layers_lbl.text = "4L Sk:-- Ms:-- Bn:-- Or:--"
		limbs_lbl.text = "Limbs: --"
		wounds_lbl.text = "Wounds: --"
		return

	var anat: AnatomyComponent = actor.anatomy
	var reg_val: float = actor.stat_sheet.get_stat(StatSheet.Stat.REG) if actor.stat_sheet != null else 10.0
	if title_lbl != null:
		if is_player_col:
			var rname: String = String(StatSheet.get_race_preset_name(actor.stat_sheet.race_preset)) if actor.stat_sheet != null else "Human"
			title_lbl.text = "PLAYER [%s REG:%.0f]" % [rname, reg_val]
		else:
			title_lbl.text = "TARGET: %s [REG:%.0f]" % [actor.actor_display_name, reg_val]

	for zone_key: StringName in zone_rect_map.keys():
		zone_rect_map[zone_key].color = get_zone_color(anat, zone_key)

	var blood_pct: float = anat.get_blood_ratio() * 100.0
	blood_lbl.text = "Blood:%.0f/%.0f (%.0f%%)" % [anat.blood_volume, anat.max_blood_volume, blood_pct]
	var loss_ratio: float = anat.get_blood_loss_ratio()
	if anat.is_dead or loss_ratio >= AnatomyComponent.BLOOD_LOSS_DEATH_RATIO:
		blood_lbl.add_theme_color_override("font_color", COLOR_ZONE_CRITICAL)
	elif loss_ratio > AnatomyComponent.BLOOD_LOSS_KO_RATIO:
		blood_lbl.add_theme_color_override("font_color", COLOR_ZONE_SEVERE)
	elif loss_ratio > AnatomyComponent.BLOOD_LOSS_SEVERE_RATIO:
		blood_lbl.add_theme_color_override("font_color", COLOR_ZONE_LIGHT)
	else:
		blood_lbl.add_theme_color_override("font_color", Color("#E5E9F0"))

	var status_tag: String = "DEAD" if anat.is_dead else ("KO!" if anat.is_unconscious else "OK")
	var ar_active: bool = anat.is_anti_regen_active()
	shock_lbl.text = "Shock:%.0f%% [%s]%s" % [anat.shock_level, status_tag, " AR!" if ar_active else ""]
	shock_lbl.add_theme_color_override("font_color", Color("#FF7675") if ar_active else Color("#E5E9F0"))

	res_lbl.text = "STA:%.0f MP:%.0f Cal:%.0f" % [actor.current_stamina, actor.current_mp, anat.calories]

	organs_lbl.text = "Org H:%.0f N:%.0f C:%.0f" % [
		anat.get_organ_integrity(AnatomyComponent.ZONE_HEAD),
		anat.get_organ_integrity(AnatomyComponent.ZONE_NECK),
		anat.get_organ_integrity(AnatomyComponent.ZONE_CHEST),
	]

	# Minimum integrity across the 4 anatomical tissue layers (Skin / Muscle-Tendon / Bone / Vessels-Organs)
	var min_skin: float = 100.0
	var min_muscle: float = 100.0
	var min_bone: float = 100.0
	var min_vessel_org: float = 100.0
	var limb_issues: PackedStringArray = PackedStringArray()
	for z: StringName in anat.get_zone_names():
		var part: AnatomyComponent.BodyPart = anat.get_body_part(z)
		if part == null:
			continue
		min_skin = minf(min_skin, part.skin_integrity)
		min_muscle = minf(min_muscle, part.muscle_tendon_integrity)
		min_bone = minf(min_bone, part.bone_integrity)
		min_vessel_org = minf(min_vessel_org, part.vessels_organ_integrity)
		if part.limb_status == AnatomyComponent.LimbStatus.SEVERED:
			limb_issues.append("%s:SEVERED(%.0f%%)" % [_short_zone(z), part.regrowth_progress])
		elif part.limb_status == AnatomyComponent.LimbStatus.CRIPPLED:
			limb_issues.append("%s:CRIPPLED" % _short_zone(z))

	layers_lbl.text = "4L Sk:%.0f Ms:%.0f Bn:%.0f Or:%.0f" % [min_skin, min_muscle, min_bone, min_vessel_org]
	limbs_lbl.text = "Limbs: %s" % ("INTACT" if limb_issues.is_empty() else " ".join(limb_issues))
	limbs_lbl.add_theme_color_override("font_color", COLOR_ZONE_HEALTHY if limb_issues.is_empty() else COLOR_ZONE_CRITICAL)

	# Build detailed wound / arterial / LodgedWeapon / Anti-Regen lines
	var lines: PackedStringArray = PackedStringArray()
	if ar_active:
		lines.append("[ANTI-REGEN ACTIVE]")
	for z: StringName in anat.get_zone_names():
		var lodged: Array[WeaponData] = anat.get_lodged_weapons(z)
		for lw: WeaponData in lodged:
			lines.append("[LODGED %s]: %s" % [_short_zone(z), lw.display_name])
	var wounds: Array[WoundResource] = anat.get_all_wounds()
	var remaining_slots: int = maxi(1, 4 - lines.size())
	var max_show: int = mini(wounds.size(), remaining_slots)
	for i: int in range(max_show):
		var w: WoundResource = wounds[i]
		var bleed: float = w.get_effective_bleed_rate()
		var art_tag: String = "[ART!] " if (w.is_arterial and bleed > 0.0) else ""
		var w_ar_tag: String = " [AR]" if w.is_anti_regen_active() else ""
		var bnd_tag: String = " [BND]" if w.is_bandaged else ""
		var spl_tag: String = " [SPL]" if w.is_splinted else ""
		if w.wound_type == WoundResource.WoundType.FRACTURE:
			lines.append("- %s: FRACTURE%s%s" % [_short_zone(w.body_zone), spl_tag, w_ar_tag])
		elif bleed > 0.0:
			lines.append("- %s%s: %s (%.1fml/s)%s%s" % [art_tag, _short_zone(w.body_zone), w.display_name, bleed, bnd_tag, w_ar_tag])
		else:
			lines.append("- %s: %s%s%s" % [_short_zone(w.body_zone), w.display_name, bnd_tag, w_ar_tag])
	if wounds.size() > max_show:
		lines.append("+%d more..." % (wounds.size() - max_show))
	wounds_lbl.text = "Wounds: none" if lines.is_empty() else "\n".join(lines)


static func _short_zone(zone: StringName) -> String:
	match zone:
		AnatomyComponent.ZONE_LEFT_ARM:
			return "LArm"
		AnatomyComponent.ZONE_RIGHT_ARM:
			return "RArm"
		AnatomyComponent.ZONE_LEFT_LEG:
			return "LLeg"
		AnatomyComponent.ZONE_RIGHT_LEG:
			return "RLeg"
		AnatomyComponent.ZONE_STOMACH:
			return "Stom"
		_:
			return String(zone)


func _refresh_debug_panel_labels(player: PlayerController) -> void:
	if btn_awaken_mana == null:
		return
	if player == null or player.stat_sheet == null:
		return

	if btn_race_preset != null:
		if player.stat_sheet.race_preset == StatSheet.RacePreset.TROLL:
			btn_race_preset.text = "Раса: Тролль (REG<=65, CON<=45)"
		else:
			btn_race_preset.text = "Раса: Человек (REG<=12)"

	if player.stat_sheet.mana_awakened:
		btn_awaken_mana.text = "Усыпить ману (Активна)"
	else:
		var cap_hint: String = "Лимит 65 REG" if player.stat_sheet.race_preset == StatSheet.RacePreset.TROLL else "Лимит 22"
		btn_awaken_mana.text = "Пробудить ману (%s)" % cap_hint

	if btn_toggle_wings != null:
		btn_toggle_wings.text = "Крылья: %s" % ("ВКЛ" if player.has_wings else "ВЫКЛ")
	if btn_flight_mode_pref != null:
		btn_flight_mode_pref.text = "Полёт: %s" % VerticalityComponent.get_preferred_flight_mode_name(player.get_preferred_flight_mode())

	if btn_toggle_perception != null and SimulationClock != null:
		btn_toggle_perception.text = "Воспр[P]:%.2f" % SimulationClock.perception_regulator
	if slider_perception != null and SimulationClock != null and not slider_perception.has_focus():
		if not is_equal_approx(slider_perception.value, SimulationClock.perception_regulator):
			_updating_sliders = true
			slider_perception.value = SimulationClock.perception_regulator
			_updating_sliders = false

	for stat_id: int in SLIDER_STATS:
		var base_v: float = player.stat_sheet.get_base_stat(stat_id)
		var eff_v: float = player.stat_sheet.get_stat(stat_id)
		if stat_slider_labels.has(stat_id):
			stat_slider_labels[stat_id].text = "%s:%.0f(%.0f)" % [
				String(StatSheet.get_stat_name(stat_id)),
				base_v,
				eff_v,
			]
		if stat_sliders.has(stat_id) and not stat_sliders[stat_id].has_focus():
			if not is_equal_approx(stat_sliders[stat_id].value, base_v):
				_updating_sliders = true
				stat_sliders[stat_id].value = base_v
				_updating_sliders = false


static func get_zone_color(anat: AnatomyComponent, zone: StringName) -> Color:
	if anat == null or not anat.has_zone(zone):
		return Color(0.3, 0.3, 0.3, 1.0)
	var limb_st: AnatomyComponent.LimbStatus = anat.get_limb_status(zone)
	if limb_st == AnatomyComponent.LimbStatus.SEVERED:
		return COLOR_ZONE_SEVERED
	if AnatomyComponent.VITAL_ZONES.has(zone):
		var integrity: float = anat.get_organ_integrity(zone)
		if integrity <= 0.0:
			return COLOR_ZONE_DESTROYED
		if integrity < 50.0:
			return COLOR_ZONE_CRITICAL
		if integrity < 100.0:
			return COLOR_ZONE_SEVERE

	if anat.has_arterial_bleeding(zone) or anat.has_lodged_weapon(zone):
		return COLOR_ZONE_CRITICAL
	if limb_st == AnatomyComponent.LimbStatus.CRIPPLED:
		return COLOR_ZONE_SEVERE

	var wounds: Array[WoundResource] = anat.get_wounds(zone)
	if wounds.is_empty():
		return COLOR_ZONE_HEALTHY

	var has_fracture_or_deep: bool = anat.has_fracture(zone)
	var total_bleed: float = 0.0
	for w: WoundResource in wounds:
		total_bleed += w.get_effective_bleed_rate()
		if w.wound_type == WoundResource.WoundType.DEEP_WOUND or w.wound_type == WoundResource.WoundType.FRACTURE:
			has_fracture_or_deep = true

	if total_bleed >= 6.0 or (has_fracture_or_deep and total_bleed > 0.0):
		return COLOR_ZONE_CRITICAL
	if has_fracture_or_deep or total_bleed >= 2.0:
		return COLOR_ZONE_SEVERE
	return COLOR_ZONE_LIGHT


func _resolve_debug_target() -> CombatActor:
	if last_attacked_target != null and is_instance_valid(last_attacked_target) and last_attacked_target.is_alive():
		return last_attacked_target
	if not is_inside_tree():
		return null
	var fallback: CombatActor = null
	for n: Node in get_tree().get_nodes_in_group(&"enemies"):
		if n is EnemyDummy and is_instance_valid(n) and (n as EnemyDummy).is_alive():
			var e: EnemyDummy = n as EnemyDummy
			if e.preset == EnemyDummy.EnemyPreset.TROLL_BERSERKER:
				return e
			if fallback == null:
				fallback = e
	return fallback


func _find_player() -> PlayerController:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"player"):
		if n is PlayerController:
			return n as PlayerController
	return null


func _find_arena() -> TestArena:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"test_arena"):
		if n is TestArena:
			return n as TestArena
	return null
