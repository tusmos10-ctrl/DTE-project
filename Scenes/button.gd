extends Node

@export var button: Button
@export_file("*.tscn") var target_scene_path: String = ""

@export_group("Flash")
@export var flash_color: Color = Color(4.0, 4.0, 4.0)
@export var flash_in_time: float = 0.05
@export var flash_hold_time: float = 0.03
@export var flash_out_time: float = 0.12

@export_group("Sweep (optional light streak)")
@export var use_sweep: bool = true
@export var sweep_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var sweep_width_ratio: float = 0.35
@export var sweep_time: float = 0.22

@export_group("Camera Shake (optional)")
@export var camera: Camera2D = null
@export var shake_strength: float = 12.0
@export var shake_duration: float = 0.18

var _flash: ColorRect = null
var _sweep: ColorRect = null
var _cam_base_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	if button:
		button.pressed.connect(_on_pressed)
	else:
		push_warning("No Button assigned in the Inspector! Drag your button node into the 'Button' slot.")

func _on_pressed() -> void:
	print("Button pressed. target_scene_path = '", target_scene_path, "'")
	if target_scene_path == "":
		push_warning("No target_scene_path set!")
		return

	_start_flash()
	if use_sweep:
		_start_sweep()
	if camera:
		_start_shake()

func _start_flash() -> void:
	_flash = ColorRect.new()
	_flash.color = flash_color
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	get_tree().root.add_child(_flash)
	_flash.z_index = 4096

	_flash.anchor_left = 0.0
	_flash.anchor_top = 0.0
	_flash.anchor_right = 1.0
	_flash.anchor_bottom = 1.0
	_flash.offset_left = 0.0
	_flash.offset_top = 0.0
	_flash.offset_right = 0.0
	_flash.offset_bottom = 0.0

	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 1.0, flash_in_time)
	tween.tween_interval(flash_hold_time)
	tween.tween_property(_flash, "modulate:a", 0.0, flash_out_time)
	tween.tween_callback(_on_flash_complete)

func _start_sweep() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var sweep_width := viewport_size.x * sweep_width_ratio

	_sweep = ColorRect.new()
	_sweep.color = sweep_color
	_sweep.size = Vector2(sweep_width, viewport_size.y * 1.5)
	_sweep.rotation_degrees = 20.0
	_sweep.position = Vector2(-sweep_width, -viewport_size.y * 0.25)
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(_sweep)
	_sweep.z_index = 4097

	var target_x := viewport_size.x + sweep_width
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_sweep, "position:x", target_x, sweep_time)
	tween.tween_callback(_on_sweep_complete)

func _start_shake() -> void:
	_cam_base_offset = camera.offset
	var tween := create_tween()
	var steps := 6
	for i in range(steps):
		var t := float(i) / float(steps)
		var strength := shake_strength * (1.0 - t)
		var rand_offset := Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)
		tween.tween_property(camera, "offset", _cam_base_offset + rand_offset, shake_duration / steps)
	tween.tween_property(camera, "offset", _cam_base_offset, shake_duration / steps)

func _on_sweep_complete() -> void:
	if is_instance_valid(_sweep):
		_sweep.queue_free()

func _on_flash_complete() -> void:
	get_tree().change_scene_to_file(target_scene_path)
	if is_instance_valid(_flash):
		_flash.queue_free()
