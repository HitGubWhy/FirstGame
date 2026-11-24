extends Node
## WorldCalendar Autoload (GDD Sections 10.1, 10.2, 10.3, 12.1).
## Runs on raw frame delta independently of SimulationClock's combat time dilation.
## Scale: 1 game hour = 2 real minutes (120 real sec), 30 days/month, 360 days/year.
## Blood Moon: 30th day of every month. World Stage: 0..24 (steps every 15 days).

const REAL_SECONDS_PER_GAME_HOUR: float = 120.0
const GAME_MINUTES_PER_REAL_SECOND: float = 0.5
const MINUTES_PER_HOUR: int = 60
const HOURS_PER_DAY: int = 24
const MINUTES_PER_DAY: int = 1440
const DAYS_PER_MONTH: int = 30
const MONTHS_PER_YEAR: int = 12
const DAYS_PER_YEAR: int = 360
const DAYS_PER_WORLD_STAGE: int = 15
const MAX_WORLD_STAGE: int = 24
const BLOOD_MOON_DAY: int = 30

const DAY_START_HOUR: int = 6
const NIGHT_START_HOUR: int = 20

const MIN_TIME_ACCELERATION: float = 15.0
const MAX_TIME_ACCELERATION: float = 60.0

const INTERRUPT_HOSTILE: String = "hostile_detected"
const INTERRUPT_DAMAGE: String = "damage_taken"
const INTERRUPT_CRITICAL_STATUS: String = "critical_physiology"
const INTERRUPT_BLOOD_MOON: String = "blood_moon_started"
const INTERRUPT_MANUAL: String = "manual"

var total_minutes: float = 0.0
var time_acceleration: float = 1.0
var paused: bool = false
var last_interrupt_reason: String = ""

var _last_hour_index: int = 0
var _last_elapsed_days: int = 0
var _last_world_stage: int = 0
var _last_blood_moon: bool = false


func _ready() -> void:
	_sync_tracking_state()


func _process(delta: float) -> void:
	if paused or delta <= 0.0:
		return
	advance_real_seconds(delta)


func reset_calendar(start_hour: int = 0) -> void:
	total_minutes = float(maxi(0, start_hour) * MINUTES_PER_HOUR)
	time_acceleration = 1.0
	last_interrupt_reason = ""
	_sync_tracking_state()


func _sync_tracking_state() -> void:
	_last_hour_index = floori(total_minutes / float(MINUTES_PER_HOUR))
	_last_elapsed_days = get_elapsed_days()
	_last_world_stage = get_world_stage()
	_last_blood_moon = is_blood_moon()


# ---------------------------------------------------------------------------
# Time Queries
# ---------------------------------------------------------------------------

func get_elapsed_days() -> int:
	return floori(total_minutes / float(MINUTES_PER_DAY))


## 1-based global day counter (Day 1 .. Day 360 in Year 1; Day 361+ is Conquered World).
func get_total_day() -> int:
	return get_elapsed_days() + 1


## 1-based day within current month (1..30).
func get_day_of_month() -> int:
	return (get_elapsed_days() % DAYS_PER_MONTH) + 1


## 1-based month within current year (1..12).
func get_month() -> int:
	var total_months: int = floori(float(get_elapsed_days()) / float(DAYS_PER_MONTH))
	return (total_months % MONTHS_PER_YEAR) + 1


## 1-based year counter.
func get_year() -> int:
	return floori(float(get_elapsed_days()) / float(DAYS_PER_YEAR)) + 1


func get_hour() -> int:
	var total_hours: int = floori(total_minutes / float(MINUTES_PER_HOUR))
	return total_hours % HOURS_PER_DAY


func get_minute() -> int:
	return floori(total_minutes) % MINUTES_PER_HOUR


func is_daytime() -> bool:
	var h: int = get_hour()
	return h >= DAY_START_HOUR and h < NIGHT_START_HOUR


func is_night() -> bool:
	return not is_daytime()


func is_blood_moon() -> bool:
	return get_day_of_month() == BLOOD_MOON_DAY


func get_world_stage() -> int:
	var raw_stage: int = floori(float(get_elapsed_days()) / float(DAYS_PER_WORLD_STAGE))
	return clampi(raw_stage, 0, MAX_WORLD_STAGE)


func is_world_conquered() -> bool:
	return get_world_stage() >= MAX_WORLD_STAGE


func get_mana_training_mult() -> float:
	return 2.0 if is_blood_moon() else 1.0


func get_date_dict() -> Dictionary:
	return {
		"year": get_year(),
		"month": get_month(),
		"day_of_month": get_day_of_month(),
		"total_day": get_total_day(),
		"hour": get_hour(),
		"minute": get_minute(),
		"world_stage": get_world_stage(),
		"is_blood_moon": is_blood_moon(),
		"is_night": is_night(),
	}


# ---------------------------------------------------------------------------
# Time Acceleration & Interruption (GDD Section 10.1)
# ---------------------------------------------------------------------------

func start_time_acceleration(multiplier: float) -> float:
	time_acceleration = clampf(multiplier, MIN_TIME_ACCELERATION, MAX_TIME_ACCELERATION)
	return time_acceleration


func is_accelerating() -> bool:
	return time_acceleration > 1.0


func interrupt_acceleration(reason: String = INTERRUPT_MANUAL) -> bool:
	if not is_accelerating():
		return false
	time_acceleration = 1.0
	last_interrupt_reason = reason
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("time_acceleration_interrupted", reason)
	return true


# ---------------------------------------------------------------------------
# Advancing & Fast-Forwarding Time
# ---------------------------------------------------------------------------

func advance_real_seconds(real_seconds: float, stop_on_blood_moon: bool = false) -> float:
	if real_seconds <= 0.0:
		return 0.0
	var game_minutes: float = real_seconds * GAME_MINUTES_PER_REAL_SECOND * time_acceleration
	return advance_game_minutes(game_minutes, stop_on_blood_moon)


func fast_forward_hours(hours: float, stop_on_blood_moon: bool = true) -> float:
	if hours <= 0.0:
		return 0.0
	return advance_game_minutes(hours * float(MINUTES_PER_HOUR), stop_on_blood_moon) / float(MINUTES_PER_HOUR)


func fast_forward_days(days: float, stop_on_blood_moon: bool = true) -> float:
	if days <= 0.0:
		return 0.0
	return advance_game_minutes(days * float(MINUTES_PER_DAY), stop_on_blood_moon) / float(MINUTES_PER_DAY)


func advance_game_minutes(minutes: float, stop_on_blood_moon: bool = false) -> float:
	if minutes <= 0.0:
		return 0.0
	var remaining: float = minutes
	var consumed: float = 0.0

	while remaining > 1e-6:
		var current_hour_index: int = floori(total_minutes / float(MINUTES_PER_HOUR))
		var next_hour_boundary: float = float(current_hour_index + 1) * float(MINUTES_PER_HOUR)
		var dist_to_next_hour: float = next_hour_boundary - total_minutes
		if dist_to_next_hour <= 1e-6:
			dist_to_next_hour = float(MINUTES_PER_HOUR)
			next_hour_boundary = total_minutes + dist_to_next_hour

		var step: float = minf(remaining, dist_to_next_hour)
		total_minutes += step
		if absf(total_minutes - next_hour_boundary) <= 1e-5:
			total_minutes = next_hour_boundary
		remaining -= step
		consumed += step

		var blood_moon_triggered: bool = _check_and_emit_transitions()
		if blood_moon_triggered and stop_on_blood_moon:
			break

	return consumed


func _check_and_emit_transitions() -> bool:
	var bus: Node = _get_event_bus()
	var blood_moon_started: bool = false

	var current_hour_index: int = floori(total_minutes / float(MINUTES_PER_HOUR))
	if current_hour_index != _last_hour_index:
		_last_hour_index = current_hour_index
		if bus != null:
			bus.emit_signal("hour_changed", get_hour())

	var current_elapsed_days: int = get_elapsed_days()
	if current_elapsed_days != _last_elapsed_days:
		_last_elapsed_days = current_elapsed_days
		if bus != null:
			bus.emit_signal("day_passed", get_total_day())

		var current_stage: int = get_world_stage()
		if current_stage != _last_world_stage:
			_last_world_stage = current_stage
			if bus != null:
				bus.emit_signal("world_stage_changed", current_stage)

		var now_blood_moon: bool = is_blood_moon()
		if now_blood_moon != _last_blood_moon:
			_last_blood_moon = now_blood_moon
			if bus != null:
				bus.emit_signal("blood_moon_changed", now_blood_moon)
			if now_blood_moon:
				blood_moon_started = true
				# GDD 10.1 Rule 4: Blood Moon automatically interrupts active time acceleration
				interrupt_acceleration(INTERRUPT_BLOOD_MOON)

	return blood_moon_started


func _get_event_bus() -> Node:
	var root: Node = get_tree().root if is_inside_tree() else null
	if root != null:
		return root.get_node_or_null("EventBus")
	return null
