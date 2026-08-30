extends Node
# PlayerDiagnostic.gd
# Attach this as a child of your CharacterBody2D (the player node).
# Run the game, stand on the ground, press A or D.
# Read the Output panel — it will tell you exactly what is wrong.

var _player : CharacterBody2D = null
var _timer  : float = 0.0
var _frames : int   = 0

func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	if _player == null:
		push_error("PlayerDiagnostic must be a child of CharacterBody2D!")
		return
	print("=== PLAYER DIAGNOSTIC RUNNING ===")
	print("Stand on the ground and press A or D.")
	print("---------------------------------")

func _physics_process(delta: float) -> void:
	if _player == null:
		return

	_timer  += delta
	_frames += 1

	# Print a report every 0.5 seconds so output isn't flooded
	if _timer < 0.5:
		return
	_timer = 0.0

	var on_floor   := _player.is_on_floor()
	var vel        := _player.velocity
	var key_a      := Input.is_key_pressed(KEY_A)
	var key_d      := Input.is_key_pressed(KEY_D)
	var key_left   := Input.is_key_pressed(KEY_LEFT)
	var key_right  := Input.is_key_pressed(KEY_RIGHT)
	var any_move   := key_a or key_d or key_left or key_right

	print("--- Frame %d ---" % _frames)
	print("  on_floor   : %s" % on_floor)
	print("  velocity   : (%.1f, %.1f)" % [vel.x, vel.y])
	print("  KEY_A      : %s   KEY_D : %s" % [key_a, key_d])
	print("  KEY_LEFT   : %s   KEY_RIGHT : %s" % [key_left, key_right])
	print("  any_move   : %s" % any_move)

	# --- DIAGNOSE ---

	if on_floor and any_move and abs(vel.x) < 5.0:
		print("  !! STUCK: on floor, key held, but velocity.x is nearly 0.")
		print("     Most likely causes:")
		print("     1. Something else is zeroing velocity.x after player.gd sets it.")
		print("     2. A collision shape is blocking horizontal movement.")
		print("     3. Another script on this node is overwriting velocity.")
		print("     4. process_mode is wrong and physics runs at wrong time.")
		_print_children(_player, 0)

	if not on_floor and abs(vel.y) < 1.0 and abs(vel.x) < 1.0:
		print("  !! FROZEN: not on floor but velocity is nearly zero.")
		print("     Could be frozen by Engine.time_scale = 0 or paused.")
		print("     time_scale = %.2f" % Engine.time_scale)

	if on_floor and vel.y > 50.0:
		print("  !! velocity.y is large and positive on floor (%.1f)." % vel.y)
		print("     move_and_slide may not be cancelling it — check Up Direction.")
		print("     Player up_direction = %s" % _player.up_direction)

	if not on_floor and any_move:
		print("  (in air — movement only applies when on floor in this test)")

	# Check for scripts on siblings that might interfere
	if _frames == 1:
		print("  -- Node children of player: --")
		_print_children(_player, 0)
		print("  -- Player script: %s" % _player.get_script())
		print("  -- up_direction : %s" % _player.up_direction)
		print("  -- floor_stop_on_slope: %s" % _player.floor_stop_on_slope)
		print("  -- floor_snap_length  : %.2f" % _player.floor_snap_length)
		print("  -- motion_mode: %s" % _player.motion_mode)

func _print_children(node: Node, depth: int) -> void:
	var indent := "    ".repeat(depth + 1)
	for c in node.get_children():
		var script_name := ""
		if c.get_script():
			script_name = " [script: %s]" % c.get_script().resource_path
		print("%s- %s (%s)%s" % [indent, c.name, c.get_class(), script_name])
		if depth < 2:
			_print_children(c, depth + 1)
