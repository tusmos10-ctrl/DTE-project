extends CharacterBody2D

# ── Stats ──────────────────────────────────────────────────────────────────────
@export var walk_speed   : float = 200.0
@export var jump_force   : float = -500.0
@export var gravity      : float = 1200.0
@export var max_fall     : float = 800.0
@export var dash_speed   : float = 700.0
@export var dash_time    : float = 0.18
@export var dash_cd_time : float = 0.4
@export var hook_speed   : float = 1600.0
@export var hook_pull    : float = 950.0
@export var hook_range   : float = 520.0

# ── State ──────────────────────────────────────────────────────────────────────
var alive        : bool    = true
var facing       : float   = 1.0
var dash_cd      : float   = 0.0
var is_dashing   : bool    = false
var dash_timer   : float   = 0.0
var dash_dir     : Vector2 = Vector2.RIGHT

enum H { IDLE, FLYING, ATTACHED }
var hstate   : H      = H.IDLE
var hpos     : Vector2 = Vector2.ZERO
var hdir     : Vector2 = Vector2.ZERO
var htraveled: float   = 0.0
var htarget  : Node2D  = null

var spr  : AnimatedSprite2D = null
var rope : Line2D = null

# ── Setup ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("player")
	process_mode = Node.PROCESS_MODE_ALWAYS

	for c in get_children():
		if c is AnimatedSprite2D:
			spr = c
			break

	rope = Line2D.new()
	rope.width = 4.0
	rope.default_color = Color(1.0, 0.85, 0.1)
	rope.joint_mode = Line2D.LINE_JOINT_ROUND
	rope.begin_cap_mode = Line2D.LINE_CAP_ROUND
	rope.end_cap_mode = Line2D.LINE_CAP_ROUND
	rope.visible = false
	add_child(rope)

# ── Input — using _input so nothing is missed ─────────────────────────────────

func _input(event: InputEvent) -> void:
	if not alive:
		return

	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.is_echo():
			if k.keycode == KEY_SPACE or k.keycode == KEY_UP:
				if is_on_floor():
					velocity.y = jump_force
					print("jumped")
			if k.keycode == KEY_Q:
				_start_dash()
			if k.keycode == KEY_E:
				_fire_hook()
		if not k.pressed:
			if k.keycode == KEY_E:
				_release_hook()

# ── Physics ────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not alive:
		return

	dash_cd = maxf(dash_cd - delta, 0.0)

	# Gravity
	if not is_dashing and hstate != H.ATTACHED:
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y = minf(velocity.y + gravity * delta, max_fall)

	# Walk
	if not is_dashing and hstate != H.ATTACHED:
		var left  := Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A)
		var right := Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
		if right:
			velocity.x = walk_speed
		elif left:
			velocity.x = -walk_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, walk_speed)

	# Dash
	if is_dashing:
		velocity = dash_dir * dash_speed
		# Check hit
		for node in get_tree().get_nodes_in_group("enemy"):
			if node is Node2D:
				var d : float = global_position.distance_to((node as Node2D).global_position)
				if d < 55.0:
					_hit_enemy(node as Node2D)
					break
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false
			dash_cd    = dash_cd_time

	# Grapple pull
	if hstate == H.ATTACHED:
		if not is_instance_valid(htarget):
			_release_hook()
		else:
			var to := htarget.global_position - global_position
			if to.length() < 45.0:
				velocity = to.normalized() * 280.0
				_release_hook()
			else:
				velocity = to.normalized() * hook_pull

	# Hook projectile
	if hstate == H.FLYING:
		hpos      += hdir * hook_speed * delta
		htraveled += hook_speed * delta
		for node in get_tree().get_nodes_in_group("enemy"):
			if node is Node2D:
				var d : float = hpos.distance_to((node as Node2D).global_position)
				if d < 50.0:
					hstate  = H.ATTACHED
					htarget = node as Node2D
					break
		if htraveled >= hook_range:
			_release_hook()

	_draw_rope()
	_update_facing()
	move_and_slide()

# ── Dash ───────────────────────────────────────────────────────────────────────

func _start_dash() -> void:
	if is_dashing or dash_cd > 0.0:
		return
	var mouse  := get_global_mouse_position()
	dash_dir    = (mouse - global_position).normalized()
	is_dashing  = true
	dash_timer  = dash_time
	velocity    = Vector2.ZERO
	Engine.time_scale = 1.0
	_release_hook()
	_flash(Color(6, 6, 6))

func _hit_enemy(enemy: Node2D) -> void:
	is_dashing = false
	dash_cd    = 0.0
	velocity.x = -dash_dir.x * 850.0
	velocity.y = -550.0
	_flash(Color(9, 9, 9))
	_burst(enemy.global_position, Color.BLACK, 45)
	_burst(enemy.global_position, Color.WHITE, 18)
	if enemy.has_method("explode_and_respawn"):
		enemy.explode_and_respawn()
	else:
		enemy.queue_free()
	Engine.time_scale = 0.0
	get_tree().create_timer(0.05, true, false, true).timeout.connect(func():
		Engine.time_scale = 0.15
		get_tree().create_timer(1.2, true, false, true).timeout.connect(func():
			Engine.time_scale = 1.0
		)
	)

# ── Hook ───────────────────────────────────────────────────────────────────────

func _fire_hook() -> void:
	var mouse := get_global_mouse_position()
	hdir       = (mouse - global_position).normalized()
	hpos       = global_position
	htraveled  = 0.0
	hstate     = H.FLYING
	htarget    = null
	Engine.time_scale = 1.0

func _release_hook() -> void:
	hstate    = H.IDLE
	htarget   = null
	hpos      = Vector2.ZERO
	htraveled = 0.0

# ── Rope ──────────────────────────────────────────────────────────────────────

func _draw_rope() -> void:
	if hstate == H.IDLE:
		rope.visible = false
		return

	rope.visible = true
	rope.clear_points()

	var end_world : Vector2
	if hstate == H.FLYING:
		end_world = hpos
	elif is_instance_valid(htarget):
		end_world = htarget.global_position
	else:
		rope.visible = false
		return

	var end  : Vector2 = to_local(end_world)
	var dist : float   = end.length()
	var sag  : float   = minf(maxf(110.0 - dist * 0.18, 0.0), 110.0)
	# Slight sideways wobble on the midpoint for spaghetti feel
	var wobble : float = sin(htraveled * 0.04) * 14.0
	var mid  : Vector2 = end * 0.5 + Vector2(wobble, sag)

	rope.add_point(Vector2.ZERO)
	var segs : int = 20
	for i in range(1, segs + 1):
		var t : float   = float(i) / float(segs)
		var p : Vector2 = (1.0-t)*(1.0-t)*Vector2.ZERO + 2.0*(1.0-t)*t*mid + t*t*end
		rope.add_point(p)

# ── Facing ────────────────────────────────────────────────────────────────────

func _update_facing() -> void:
	if is_dashing and abs(dash_dir.x) > 0.1:
		facing = sign(dash_dir.x)
	elif hstate == H.ATTACHED and is_instance_valid(htarget):
		var dx : float = htarget.global_position.x - global_position.x
		if abs(dx) > 2.0:
			facing = sign(dx)
	else:
		var left  := Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A)
		var right := Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
		if right:   facing =  1.0
		elif left:  facing = -1.0
		else:
			var mdx : float = get_global_mouse_position().x - global_position.x
			if abs(mdx) > 8.0:
				facing = sign(mdx)
	if spr:
		spr.flip_h = facing < 0.0

# ── Visuals ────────────────────────────────────────────────────────────────────

func _flash(col: Color) -> void:
	var t := create_tween()
	t.tween_property(self, "modulate", col,         0.04)
	t.tween_property(self, "modulate", Color.WHITE, 0.1)

func _burst(pos: Vector2, col: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	get_tree().root.add_child(p)
	p.global_position      = pos
	p.emitting             = true
	p.one_shot             = true
	p.explosiveness        = 1.0
	p.amount               = amount
	p.lifetime             = 0.55
	p.direction            = Vector2(0, -1)
	p.spread               = 180.0
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 210.0
	p.scale_amount_min     = 2.5
	p.scale_amount_max     = 6.0
	p.color                = col
	p.gravity              = Vector2(0, 320)
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

# ── Death ──────────────────────────────────────────────────────────────────────

func die() -> void:
	if not alive:
		return
	alive = false
	Engine.time_scale = 1.0
	set_physics_process(false)
	set_process_input(false)
	_release_hook()
	modulate = Color.RED
	velocity  = Vector2(0, -300)
	await get_tree().create_timer(1.2).timeout
	get_tree().reload_current_scene()
