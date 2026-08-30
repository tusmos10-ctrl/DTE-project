extends CharacterBody2D
# player.gd
# A/D or Left/Right = move | Space = jump | Q = dash toward mouse | E = fire/release hook
#
# SOUND SETUP — assign AudioStreamPlayer nodes in the Inspector:
#   @export var sfx_jump, sfx_dash, sfx_hook_fire, sfx_hook_hit,
#               sfx_hook_miss, sfx_kill, sfx_land, sfx_die
#   Each should be an AudioStreamPlayer child of this node with your chosen stream set.
#
# FACING — the sprite flips horizontally to face the cursor at all times.
#   When the cursor crosses from one side to the other, scale.x tweens from 1 to -1
#   so the character smoothly rotates/flips rather than snapping.

# -----------------------------------------------------------------------
# EXPORTS — TUNING
# -----------------------------------------------------------------------

@export_group("Movement")
@export var walk_speed         : float = 200.0
@export var gravity            : float = 1200.0
@export var max_fall_speed     : float = 900.0
@export var jump_force         : float = -550.0
@export var coyote_secs        : float = 0.10
@export var jump_buffer_secs   : float = 0.10

@export_group("Dash")
@export var dash_speed         : float = 750.0
@export var dash_duration      : float = 0.16
@export var dash_cooldown      : float = 0.40
@export var dash_hit_radius    : float = 55.0

@export_group("Hook")
@export var hook_speed         : float   = 1400.0
@export var hook_pull_force    : float   = 950.0
@export var hook_max_range     : float   = 520.0
@export var hook_hit_radius    : float   = 50.0
@export var hook_arrive_dist   : float   = 42.0
@export var hook_miss_duration : float   = 0.60
# Rope wobble — higher = more alive-feeling rope while flying
@export var rope_wobble_freq   : float   = 16.0   # wave cycles per second
@export var rope_wobble_amp    : float   = 42.0   # max sideways displacement px
@export var rope_whip_decay    : float   = 4.0    # how fast wobble dies after attach
# How many segments the rope bezier uses
@export var rope_segments      : int     = 32

@export_group("Feel")
@export var kill_freeze_secs   : float   = 0.05
@export var kill_slowmo_secs   : float   = 1.20
@export var kill_slowmo_scale  : float   = 0.15
@export var kill_bounce        : Vector2 = Vector2(860.0, -560.0)
# How fast the sprite flips when cursor crosses sides (lower = slower cinematic flip)
@export var flip_tween_speed   : float   = 0.10

@export_group("Sounds")
@export var sfx_jump      : AudioStreamPlayer = null
@export var sfx_land      : AudioStreamPlayer = null
@export var sfx_dash      : AudioStreamPlayer = null
@export var sfx_hook_fire : AudioStreamPlayer = null
@export var sfx_hook_hit  : AudioStreamPlayer = null
@export var sfx_hook_miss : AudioStreamPlayer = null
@export var sfx_kill      : AudioStreamPlayer = null
@export var sfx_die       : AudioStreamPlayer = null

# -----------------------------------------------------------------------
# STATE
# -----------------------------------------------------------------------

var alive         : bool  = true

# timers
var _coyote       : float = 0.0
var _jump_buf     : float = 0.0
var _dash_cd      : float = 0.0
var _dash_timer   : float = 0.0
var _miss_timer   : float = 0.0
var _rope_time    : float = 0.0   # accumulates for rope wobble animation
var _rope_whip    : float = 0.0   # whip energy: 1 on fire, decays to 0

# floor tracking
var _was_on_floor : bool  = false

# dash
var _dashing      : bool    = false
var _dash_dir     : Vector2 = Vector2.RIGHT
var _dash_killed  : bool    = false

# hook
enum HS { IDLE, FLYING, ATTACHED, MISS_REWIND }
var _hstate       : HS      = HS.IDLE
var _hpos         : Vector2 = Vector2.ZERO
var _hdir         : Vector2 = Vector2.ZERO
var _htraveled    : float   = 0.0
var _htarget      : Node2D  = null
var _rewind_from  : Vector2 = Vector2.ZERO

# slowmo
var _in_slowmo    : bool  = false

# facing / flip
var _facing_right : bool  = true   # true = cursor is to the right of player
var _flip_tween   : Tween = null

# cached nodes
var _spr          : AnimatedSprite2D = null
var _rope         : Line2D           = null
var _flash_tween  : Tween            = null

# -----------------------------------------------------------------------
# READY
# -----------------------------------------------------------------------

func _ready() -> void:
	add_to_group("player")
	process_mode = Node.PROCESS_MODE_ALWAYS

	for c in get_children():
		if c is AnimatedSprite2D:
			_spr = c
			break

	# Rope built in code — no scene dependency
	_rope = Line2D.new()
	_rope.width          = 3.5
	_rope.default_color  = Color(1.0, 0.85, 0.1)
	_rope.joint_mode     = Line2D.LINE_JOINT_ROUND
	_rope.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_rope.end_cap_mode   = Line2D.LINE_CAP_ROUND
	_rope.visible        = false
	add_child(_rope)

# -----------------------------------------------------------------------
# INPUT  — just-pressed only; held keys polled in physics
# -----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not alive or _hstate == HS.MISS_REWIND:
		return
	if not event is InputEventKey:
		return
	var k := event as InputEventKey
	if k.pressed and not k.is_echo():
		match k.keycode:
			KEY_SPACE: _jump_buf = jump_buffer_secs
			KEY_Q:     _try_dash()
			KEY_E:     _fire_hook()
	if not k.pressed and k.keycode == KEY_E:
		_release_hook()

# -----------------------------------------------------------------------
# PHYSICS
# -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		return

	_coyote   = maxf(_coyote   - delta, 0.0)
	_jump_buf = maxf(_jump_buf - delta, 0.0)
	_dash_cd  = maxf(_dash_cd  - delta, 0.0)
	_rope_time += delta

	# coyote window
	if _was_on_floor and not is_on_floor() and velocity.y >= 0.0:
		_coyote = coyote_secs

	# land sound
	if not _was_on_floor and is_on_floor():
		_play(sfx_land)

	_was_on_floor = is_on_floor()

	# limp/rewind — stripped physics path, no input
	if _hstate == HS.MISS_REWIND:
		_do_miss_rewind(delta)
		_draw_rope()
		_update_facing()
		move_and_slide()
		return

	# ---- GRAVITY ----
	# Always add gravity. move_and_slide cancels it when on floor.
	# We never zero velocity.y manually — that was causing the stuck-on-ground bug.
	if not _dashing:
		velocity.y += gravity * delta
		velocity.y  = minf(velocity.y, max_fall_speed)

	# ---- JUMP ----
	if _jump_buf > 0.0:
		if is_on_floor() or _coyote > 0.0:
			velocity.y = jump_force
			_coyote    = 0.0
			_jump_buf  = 0.0
			_play(sfx_jump)
		elif is_on_wall():
			var wn    := get_wall_normal()
			velocity.x = wn.x * 300.0
			velocity.y = jump_force * 0.85
			_jump_buf  = 0.0
			_play(sfx_jump)

	# ---- HORIZONTAL MOVEMENT ----
	var ml := Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A)
	var mr := Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)

	if _dashing:
		velocity = _dash_dir * dash_speed
	elif mr and not ml:
		velocity.x = walk_speed
	elif ml and not mr:
		velocity.x = -walk_speed
	else:
		var brake := 1600.0 if is_on_floor() else 180.0
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)

	# ---- DASH TICK ----
	if _dashing:
		_dash_timer -= delta
		_scan_dash_hit()
		if _dash_timer <= 0.0:
			_dashing = false
			if not _dash_killed:
				_dash_cd = dash_cooldown
			_dash_killed = false

	# ---- HOOK FLIGHT ----
	if _hstate == HS.FLYING:
		_hpos      += _hdir * hook_speed * delta
		_htraveled += hook_speed * delta
		_scan_hook_hit()
		if _htraveled >= hook_max_range:
			_start_miss_rewind()

	# ---- HOOK PULL ----
	if _hstate == HS.ATTACHED:
		if not is_instance_valid(_htarget):
			_release_hook()
		else:
			var to   := _htarget.global_position - global_position
			var dist := to.length()
			if dist < hook_arrive_dist:
				velocity = to.normalized() * 260.0
				_release_hook()
			else:
				velocity = velocity.lerp(to.normalized() * hook_pull_force, 10.0 * delta)

	_draw_rope()
	_update_facing()
	move_and_slide()

# -----------------------------------------------------------------------
# FACING — smooth horizontal flip toward cursor
# -----------------------------------------------------------------------

func _update_facing() -> void:
	var mouse_x   := get_global_mouse_position().x
	var player_x  := global_position.x
	var cursor_right := mouse_x >= player_x

	# Only trigger a flip tween when the cursor actually crosses sides
	if cursor_right != _facing_right:
		_facing_right = cursor_right
		_do_flip()

func _do_flip() -> void:
	# Kill any in-progress flip so they don't fight
	if _flip_tween and _flip_tween.is_valid():
		_flip_tween.kill()

	# Tween scale.x: 1 = facing right, -1 = facing left
	# This gives the horizontal-rotation illusion you asked for
	var target_scale_x := 1.0 if _facing_right else -1.0

	if _spr:
		_flip_tween = create_tween()
		_flip_tween.set_ease(Tween.EASE_IN_OUT)
		_flip_tween.set_trans(Tween.TRANS_SINE)
		_flip_tween.tween_property(_spr, "scale:x", target_scale_x, flip_tween_speed)
	else:
		# No sprite — flip the whole node
		_flip_tween = create_tween()
		_flip_tween.set_ease(Tween.EASE_IN_OUT)
		_flip_tween.set_trans(Tween.TRANS_SINE)
		_flip_tween.tween_property(self, "scale:x", target_scale_x, flip_tween_speed)

# -----------------------------------------------------------------------
# DASH
# -----------------------------------------------------------------------

func _try_dash() -> void:
	if _dashing or _dash_cd > 0.0:
		return
	var raw    := get_global_mouse_position() - global_position
	_dash_dir   = raw.normalized() if raw.length_squared() > 1.0 else Vector2(1.0 if _facing_right else -1.0, 0.0)
	_dashing    = true
	_dash_timer = dash_duration
	_dash_killed = false
	velocity    = Vector2.ZERO
	if _in_slowmo:
		_end_slowmo()
	_release_hook()
	_flash(Color(6.0, 6.0, 6.0))
	_play(sfx_dash)

func _scan_dash_hit() -> void:
	for n in get_tree().get_nodes_in_group("enemy"):
		if not n is Node2D or not is_instance_valid(n):
			continue
		if global_position.distance_to((n as Node2D).global_position) < dash_hit_radius:
			_kill_enemy(n as Node2D)
			return

func _kill_enemy(enemy: Node2D) -> void:
	_dashing     = false
	_dash_timer  = 0.0
	_dash_killed = true
	velocity = Vector2(-_dash_dir.x * kill_bounce.x, kill_bounce.y)
	_flash(Color(9.0, 9.0, 9.0))
	_burst(enemy.global_position, Color.BLACK, 45)
	_burst(enemy.global_position, Color.WHITE, 18)
	_play(sfx_kill)
	if enemy.has_method("explode_and_respawn"):
		enemy.explode_and_respawn()
	elif is_instance_valid(enemy):
		enemy.queue_free()
	if not _in_slowmo:
		_begin_slowmo()

# -----------------------------------------------------------------------
# SLOWMO
# -----------------------------------------------------------------------

func _begin_slowmo() -> void:
	_in_slowmo        = true
	Engine.time_scale = 0.0
	get_tree().create_timer(kill_freeze_secs, true, false, true).timeout.connect(func() -> void:
		if not _in_slowmo: return
		Engine.time_scale = kill_slowmo_scale
		get_tree().create_timer(kill_slowmo_secs, true, false, true).timeout.connect(func() -> void:
			_end_slowmo()
		)
	)

func _end_slowmo() -> void:
	_in_slowmo        = false
	Engine.time_scale = 1.0

# -----------------------------------------------------------------------
# HOOK
# -----------------------------------------------------------------------

func _fire_hook() -> void:
	if _hstate == HS.MISS_REWIND:
		return
	if _hstate != HS.IDLE:
		_release_hook()
	var raw := get_global_mouse_position() - global_position
	if raw.length_squared() < 1.0:
		return
	_hdir      = raw.normalized()
	_hpos      = global_position
	_htraveled = 0.0
	_hstate    = HS.FLYING
	_htarget   = null
	_rope_whip = 1.0   # full whip energy on launch
	_play(sfx_hook_fire)

func _release_hook() -> void:
	_hstate     = HS.IDLE
	_htarget    = null
	_hpos       = Vector2.ZERO
	_htraveled  = 0.0
	_miss_timer = 0.0

func _scan_hook_hit() -> void:
	for n in get_tree().get_nodes_in_group("enemy"):
		if not n is Node2D or not is_instance_valid(n):
			continue
		var e := n as Node2D
		if _hpos.distance_to(e.global_position) < hook_hit_radius:
			_hstate  = HS.ATTACHED
			_htarget = e
			_hpos    = e.global_position
			_rope_whip = 1.0   # snap of attachment adds a burst of whip
			_play(sfx_hook_hit)
			return

# -----------------------------------------------------------------------
# HOOK MISS — limp rewind
# -----------------------------------------------------------------------

func _start_miss_rewind() -> void:
	_hstate      = HS.MISS_REWIND
	_miss_timer  = hook_miss_duration
	_rewind_from = _hpos
	# violent stumble -- knock velocity sideways opposite to the missed direction
	velocity.x   = -_hdir.x * 180.0
	velocity.y   = -220.0             # sharp upward jolt then fall
	_rope_whip   = 1.5               # extra whip energy for the dramatic rewind
	_flash(Color(4.0, 0.1, 0.1))
	_play(sfx_hook_miss)

func _do_miss_rewind(delta: float) -> void:
	_miss_timer = maxf(_miss_timer - delta, 0.0)
	var t       := 1.0 - (_miss_timer / hook_miss_duration)

	# Elastic overshoot ease -- snaps past the player then bounces back
	# This makes the rewind feel like a rubber band snapping
	var ease_t  := _elastic_out(t)
	_hpos        = _rewind_from.lerp(global_position, clampf(ease_t, 0.0, 1.4))

	# Ragdoll: gravity pulls hard, very slow horizontal drag so they tumble
	velocity.y = minf(velocity.y + gravity * 1.4 * delta, max_fall_speed)
	velocity.x = move_toward(velocity.x, 0.0, 80.0 * delta)  # barely any brake -- tumble

	# Rope pulses red -> orange -> grey as it rewinds
	var col_t := clampf(t, 0.0, 1.0)
	if col_t < 0.3:
		_rope.default_color = Color(1.0, 0.15, 0.1).lerp(Color(1.0, 0.6, 0.0), col_t / 0.3)
	else:
		_rope.default_color = Color(1.0, 0.6, 0.0).lerp(Color(0.35, 0.35, 0.35), (col_t - 0.3) / 0.7)

	# Flash red repeatedly during punishment
	if fmod(_miss_timer, 0.14) < delta:
		modulate = Color(1.8, 0.2, 0.2)
	else:
		modulate = modulate.lerp(Color.WHITE, 8.0 * delta)

	if _miss_timer <= 0.0:
		modulate = Color.WHITE
		_rope.default_color = Color(1.0, 0.85, 0.1)
		_release_hook()

# -----------------------------------------------------------------------
# ROPE DRAW — animated wobble while flying, natural sag when attached
# -----------------------------------------------------------------------

func _draw_rope() -> void:
	if _hstate == HS.IDLE:
		_rope.visible = false
		return

	var tip : Vector2
	match _hstate:
		HS.FLYING, HS.MISS_REWIND:
			tip = _hpos
		HS.ATTACHED:
			if not is_instance_valid(_htarget):
				_rope.visible = false
				return
			tip = _htarget.global_position

	# Decay whip energy every frame
	_rope_whip = maxf(_rope_whip - rope_whip_decay * get_physics_process_delta_time(), 0.0)

	_rope.visible = true
	_rope.clear_points()

	var local_tip := to_local(tip)
	var dist      := local_tip.length()
	var rope_dir  := local_tip.normalized() if dist > 0.1 else Vector2.RIGHT
	var perp      := Vector2(-rope_dir.y, rope_dir.x)

	# Rope width pulses with whip energy -- thicker at peak, thin when dead
	_rope.width = lerp(2.0, 6.5, _rope_whip)

	_rope.add_point(Vector2.ZERO)
	for i in range(1, rope_segments + 1):
		var t := float(i) / float(rope_segments)

		# Sag
		var sag := 0.0
		if _hstate == HS.ATTACHED:
			sag = clampf(dist * 0.25, 0.0, 130.0)
		elif _hstate == HS.MISS_REWIND:
			# sag explodes outward then collapses -- rubber band effect
			var rt  := 1.0 - (_miss_timer / hook_miss_duration)
			var pop := sin(rt * PI) * 80.0   # peaks in middle of rewind
			sag = clampf(dist * 0.25 + pop, 0.0, 200.0) * (1.0 - rt * 0.7)

		var mid := local_tip * 0.5 + Vector2(0.0, sag)
		var bez := (1.0-t)*(1.0-t)*Vector2.ZERO + 2.0*(1.0-t)*t*mid + t*t*local_tip

		# WOBBLE -- two overlapping sine waves for chaotic whip feel
		# Primary wave: fast, high amplitude
		var wave1 := sin(_rope_time * rope_wobble_freq + t * TAU * 1.5) * rope_wobble_amp
		# Secondary wave: slower, offset phase -- makes it feel less mechanical
		var wave2 := sin(_rope_time * rope_wobble_freq * 0.6 + t * TAU * 0.8 + 1.2) * rope_wobble_amp * 0.45
		var wave  := (wave1 + wave2) * _rope_whip
		# Envelope: zero at both ends, peaks 30% from the player end (like a whip)
		var env   := sin(t * PI) * pow(1.0 - t, 0.3)
		bez       += perp * wave * env

		_rope.add_point(bez)

# -----------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------

# Elastic overshoot easing -- goes past 1.0 then bounces back
# Used for the rope rewind snap effect
func _elastic_out(t: float) -> float:
	if t <= 0.0: return 0.0
	if t >= 1.0: return 1.0
	var c4 := (2.0 * PI) / 3.0
	return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * c4) + 1.0

# -----------------------------------------------------------------------
# SOUND HELPER
# -----------------------------------------------------------------------

func _play(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()

# -----------------------------------------------------------------------
# VISUALS
# -----------------------------------------------------------------------

func _flash(col: Color) -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", col,         0.04)
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.10)

func _burst(pos: Vector2, col: Color, count: int) -> void:
	var p := CPUParticles2D.new()
	get_parent().add_child(p)
	p.global_position      = pos
	p.emitting             = true
	p.one_shot             = true
	p.explosiveness        = 1.0
	p.amount               = count
	p.lifetime             = 0.55
	p.direction            = Vector2(0.0, -1.0)
	p.spread               = 180.0
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 220.0
	p.scale_amount_min     = 2.5
	p.scale_amount_max     = 6.5
	p.color                = col
	p.gravity              = Vector2(0.0, 340.0)
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)

# -----------------------------------------------------------------------
# DEATH
# -----------------------------------------------------------------------

func die() -> void:
	if not alive:
		return
	alive = false
	_end_slowmo()
	set_physics_process(false)
	set_process_input(false)
	_release_hook()
	_play(sfx_die)
	_burst(global_position, Color.RED,   30)
	_burst(global_position, Color.WHITE, 12)
	_flash(Color.RED)
	velocity = Vector2(0.0, -280.0)
	set_physics_process(true)
	await get_tree().create_timer(1.4).timeout
	get_tree().change_scene_to_file("res://Scenes/new_main_menu.tscn")
