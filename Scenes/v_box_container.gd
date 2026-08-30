extends VBoxContainer

@export var play_button: Button
@export var quit_button: Button

@export_file("*.tscn") var next_scene_path: String = "res://Scenes/main.tscn"

@export var use_fade_transition: bool = true
@export var fade_duration: float = 0.5

var is_transitioning := false

func _ready():
	print("Engine.time_scale at menu _ready(): ", Engine.time_scale)
	if play_button:
		play_button.pressed.connect(_on_play_pressed)
	else:
		push_warning("Play button not assigned in Inspector!")
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	else:
		push_warning("Quit button not assigned in Inspector!")

func _on_play_pressed():
	print("--- Play pressed --- next_scene_path: '", next_scene_path, "'")
	if is_transitioning:
		return
	if next_scene_path == "res://Scenes/main.tscn":
		push_warning("next_scene_path is empty! Set it in the Inspector on the VBoxContainer.")
		return
	if not ResourceLoader.exists(next_scene_path):
		push_error("ResourceLoader cannot find: " + next_scene_path)
		return
	is_transitioning = true
	if use_fade_transition:
		await _fade_out_and_change_scene()
	else:
		_do_scene_change()

func _on_quit_pressed():
	print("--- Quit pressed ---")
	get_tree().quit()

func _do_scene_change():
	print("Calling change_scene_to_file with: ", next_scene_path)
	var err: Error = get_tree().change_scene_to_file(next_scene_path)
	if err != OK:
		push_error("change_scene_to_file failed with error code: " + str(err))
	else:
		print("change_scene_to_file returned OK")

func _fade_out_and_change_scene():
	print("Fade starting. Engine.time_scale = ", Engine.time_scale)
	var fade_rect := ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(fade_rect)
	fade_rect.z_index = 4096
	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, fade_duration)
	await tween.finished
	print("Fade tween finished")
	_do_scene_change()
	fade_rect.queue_free()
