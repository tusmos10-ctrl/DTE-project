extends Node

# ── This script goes on an AutoLoad node called "GameTimer" ───────────────────
# Project > Project Settings > Autoload > add game_timer.gd as "GameTimer"

var elapsed       : float = 0.0   # total game time in seconds

# Spawn interval: starts at 6s, drops to 1.2s over 3 minutes
var spawn_interval: float = 6.0
var min_interval  : float = 1.2
var ramp_duration : float = 180.0  # seconds until fully ramped

var spawn_timer   : float = 0.0
var enemy_scene   : PackedScene = null
var enemy_path    : String = "res://flying_enemy.tscn"  # ← set this to your scene path

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Try to load enemy scene
	if ResourceLoader.exists(enemy_path):
		enemy_scene = load(enemy_path)
		print("[GameTimer] Enemy scene loaded: ", enemy_path)
	else:
		push_warning("[GameTimer] Enemy scene not found at: ", enemy_path, " — set enemy_path to your .tscn")

func _process(delta: float) -> void:
	elapsed      += delta
	spawn_timer  += delta

	# Lerp spawn interval from 6s down to 1.2s over ramp_duration
	var t : float = minf(elapsed / ramp_duration, 1.0)
	spawn_interval = lerp(6.0, min_interval, t)

	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_spawn_enemy()
		print("[GameTimer] Spawned enemy. elapsed=", int(elapsed), "s  interval=", snappedf(spawn_interval, 0.1), "s")

func _spawn_enemy() -> void:
	if enemy_scene == null:
		return

	# Find the player to spawn near
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player : Node2D = players[0] as Node2D

	var pos := _offscreen_pos(player.global_position)
	var e   := enemy_scene.instantiate()

	# Pass game time so the enemy scales with it
	if "game_time" in e:
		e.game_time = elapsed

	get_tree().root.get_child(0).add_child(e)
	e.global_position = pos

func _offscreen_pos(center: Vector2) -> Vector2:
	var hw  : float = 618.0
	var hh  : float = 383.0
	var cam_center := center + Vector2(0.0, -45.565)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var edge := rng.randi() % 4
	match edge:
		0: return cam_center + Vector2(rng.randf_range(-hw, hw), -hh - rng.randf_range(20, 100))
		1: return cam_center + Vector2(rng.randf_range(-hw, hw),  hh + rng.randf_range(20, 100))
		2: return cam_center + Vector2(-hw - rng.randf_range(20, 100), rng.randf_range(-hh, hh))
		_: return cam_center + Vector2( hw + rng.randf_range(20, 100), rng.randf_range(-hh, hh))
