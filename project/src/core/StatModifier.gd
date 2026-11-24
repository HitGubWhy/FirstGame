class_name StatModifier
extends RefCounted
## Immutable/configurable modifier registered inside StatSheet's 4-layer pipeline (GDD 12.3).
##
## Layers:
##   BASE       - Layer 1: additions to base value (practice, allocated points, innate bonuses)
##   FLAT_ADD   - Layer 2: flat additions (External Circulation, flat buffs/penalties)
##   MULTIPLIER - Layer 3: multiplicative factors (e.g. 0.8 for -20%, 1.25 for +25%)
##   OVERRIDE   - Layer 4: hard constraints (SET_VALUE, CAP_MAX, CAP_MIN)

enum Layer {
	BASE = 0,
	FLAT_ADD = 1,
	MULTIPLIER = 2,
	OVERRIDE = 3,
}

enum OverrideMode {
	NONE = 0,
	SET_VALUE = 1,
	CAP_MAX = 2,
	CAP_MIN = 3,
}

var id: StringName = &""
var stat: int = 0
var layer: Layer = Layer.FLAT_ADD
var override_mode: OverrideMode = OverrideMode.NONE
var value: float = 0.0
var priority: int = 0
var source: StringName = &""
var tags: Array[StringName] = []


func _init(
	p_id: StringName = &"",
	p_stat: int = 0,
	p_layer: Layer = Layer.FLAT_ADD,
	p_value: float = 0.0,
	p_priority: int = 0,
	p_source: StringName = &"",
	p_override_mode: OverrideMode = OverrideMode.NONE,
	p_tags: Array[StringName] = []
) -> void:
	id = p_id
	stat = p_stat
	layer = p_layer
	value = p_value
	priority = p_priority
	source = p_source
	override_mode = p_override_mode
	tags = p_tags.duplicate()


static func create_base(
	p_id: StringName,
	p_stat: int,
	p_value: float,
	p_source: StringName = &"",
	p_priority: int = 0,
	p_tags: Array[StringName] = []
) -> StatModifier:
	return StatModifier.new(p_id, p_stat, Layer.BASE, p_value, p_priority, p_source, OverrideMode.NONE, p_tags)


static func create_flat(
	p_id: StringName,
	p_stat: int,
	p_value: float,
	p_source: StringName = &"",
	p_priority: int = 0,
	p_tags: Array[StringName] = []
) -> StatModifier:
	return StatModifier.new(p_id, p_stat, Layer.FLAT_ADD, p_value, p_priority, p_source, OverrideMode.NONE, p_tags)


static func create_multiplier(
	p_id: StringName,
	p_stat: int,
	p_factor: float,
	p_source: StringName = &"",
	p_priority: int = 0,
	p_tags: Array[StringName] = []
) -> StatModifier:
	return StatModifier.new(p_id, p_stat, Layer.MULTIPLIER, p_factor, p_priority, p_source, OverrideMode.NONE, p_tags)


static func create_override(
	p_id: StringName,
	p_stat: int,
	p_value: float,
	p_source: StringName = &"",
	p_priority: int = 0,
	p_tags: Array[StringName] = []
) -> StatModifier:
	return StatModifier.new(p_id, p_stat, Layer.OVERRIDE, p_value, p_priority, p_source, OverrideMode.SET_VALUE, p_tags)


static func create_cap_max(
	p_id: StringName,
	p_stat: int,
	p_max_value: float,
	p_source: StringName = &"",
	p_priority: int = 0,
	p_tags: Array[StringName] = []
) -> StatModifier:
	return StatModifier.new(p_id, p_stat, Layer.OVERRIDE, p_max_value, p_priority, p_source, OverrideMode.CAP_MAX, p_tags)


static func create_cap_min(
	p_id: StringName,
	p_stat: int,
	p_min_value: float,
	p_source: StringName = &"",
	p_priority: int = 0,
	p_tags: Array[StringName] = []
) -> StatModifier:
	return StatModifier.new(p_id, p_stat, Layer.OVERRIDE, p_min_value, p_priority, p_source, OverrideMode.CAP_MIN, p_tags)


func has_any_tag(check_tags: Array[StringName]) -> bool:
	for t: StringName in tags:
		if check_tags.has(t):
			return true
	return false
