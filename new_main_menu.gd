extends Control

@export var background: Sprite2D
@export var extra_sprite: Sprite2D
@export var play_button: Button
@export var quit_button: Button
@export var music_player: AudioStreamPlayer
@export var main_menu_name: Label
@export var button_background: Sprite2D

@export var parallax_strength: float = 30.0
@export var pulse_strength: float = 0.12
@export var beat_sensitivity: float = 5.0
@export var background_vertical_offset: float = 120.0  # positive = lower, negative = higher

var spectrum: AudioEffectSpectrumAnalyzerInstance
var bg_base_position: Vector2
var bg_base_scale: Vector2 = Vector2.ONE
var extra_base_position: Vector2
var button_base_scales: Array[Vector2] = []
var label_base_scale: Vector2
var button_bg_base_scale: Vector2
var smoothed_energy := 0.0

func _ready():
	print("=== MainMenu _ready() started ===")

	var bus_index = AudioServer.get_bus_index("Music")
	print("Music bus index: ", bus_index)

	if bus_index >= 0:
		spectrum = AudioServer.get_bus_effect_instance(bus_index, 0)
		print("Spectrum analyzer found: ", spectrum != null)
	else:
		push_warning("Music bus not found! Check the bus name matches exactly.")

	print("Background assigned: ", background != null)
	print("Extra sprite assigned: ", extra_sprite != null)
	print("Play button assigned: ", play_button != null)
	print("Quit button assigned: ", quit_button != null)
	print("Music player assigned: ", music_player != null)
	print("Main menu name assigned: ", main_menu_name != null)
	print("Button background assigned: ", button_background != null)

	# Fit background to cover the full viewport, regardless of source image size
	_fit_background_to_viewport()

	if background:
		bg_base_position = background.position
	if extra_sprite:
		extra_base_position = extra_sprite.position

	for btn in [play_button, quit_button]:
		if btn:
			btn.pivot_offset = btn.size / 2
			button_base_scales.append(btn.scale)
		else:
			button_base_scales.append(Vector2.ONE)

	if main_menu_name:
		main_menu_name.pivot_offset = main_menu_name.size / 2
		label_base_scale = main_menu_name.scale

	if button_background:
		button_bg_base_scale = button_background.scale

	if music_player:
		print("Music player stream assigned: ", music_player.stream != null)
		if not music_player.playing:
			music_player.play()
		print("Is music playing now: ", music_player.playing)

	print("=== MainMenu _ready() finished ===")

func _fit_background_to_viewport():
	if not background or not background.texture:
		return
	if not background.centered:
		push_warning("Background sprite 'Centered' property is off — turn it on in the Inspector for correct fitting.")

	var viewport_size = get_viewport_rect().size
	var texture_size = background.texture.get_size()
	var scale_x = viewport_size.x / texture_size.x
	var scale_y = viewport_size.y / texture_size.y
	# use max, plus a small margin, so the image fully COVERS the screen with no gaps
	var scale_factor = max(scale_x, scale_y) * 1.05
	bg_base_scale = Vector2(scale_factor, scale_factor)
	background.scale = bg_base_scale

	# position relative to MainMenu's own top-left, not assuming MainMenu is at (0,0)
	background.position = viewport_size / 2 - global_position + position
	background.position.y += background_vertical_offset

func _process(delta):
	_update_parallax(delta)
	_update_beat_pulse(delta)

func _update_parallax(delta):
	var viewport_size = get_viewport_rect().size
	var mouse_pos = get_viewport().get_mouse_position()
	var offset = (mouse_pos - viewport_size / 2.0) / (viewport_size / 2.0)

	if background:
		var target = bg_base_position + offset * parallax_strength
		background.position = background.position.lerp(target, delta * 5.0)

	if extra_sprite:
		var target2 = extra_base_position + offset * (parallax_strength * 1.5)
		extra_sprite.position = extra_sprite.position.lerp(target2, delta * 5.0)

	# main_menu_name and button_background intentionally excluded — no parallax movement

func _update_beat_pulse(delta):
	if not spectrum:
		return

	var magnitude = spectrum.get_magnitude_for_frequency_range(50.0, 200.0).length()
	var energy = clamp(magnitude * beat_sensitivity, 0.0, 1.0)
	smoothed_energy = max(energy, smoothed_energy - delta * 2.0)

	var scale_amount = 1.0 + smoothed_energy * pulse_strength

	var buttons = [play_button, quit_button]
	for i in buttons.size():
		if buttons[i]:
			buttons[i].scale = button_base_scales[i] * scale_amount

	if background:
		background.scale = bg_base_scale * scale_amount
	if extra_sprite:
		extra_sprite.scale = Vector2.ONE * scale_amount
	if main_menu_name:
		main_menu_name.scale = label_base_scale * scale_amount
	if button_background:
		button_background.scale = button_bg_base_scale * scale_amount
