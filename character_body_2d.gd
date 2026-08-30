extends CharacterBody2D

# ── Stats ──────────────────────────────────────────────────────────────────────
@export var move_speed     : float = 100.0
@export var hover_amplitude: float = 20.0
@export var hover_frequency: float = 2.0
@export var max_hp         : int   = 3        # hits to kill

# ── Dash ───────────────────────────────────────────────────────────────────────
@export var dash_speed     : float = 360.0
@export var dash_windup    : float = 1
@export var dash_duration  : float = 0.5
@export var dash_cooldown  : float = 3.0
@export var dash_hit_radius: float = 50.0

# ── Escape ─────────────────────────────────────────────────────────────────────
@export var escape_speed   : float = 350.0
@export var escape_duration: float = 0.35

# ── Animation names ────────────────────────────────────────────────────────────
@export var anim_fly   : String = "Fly"
@export var anim_windup: String = "Fly"
@export var anim_dash  : String = "Attack"
@export var anim_escape: String = "Fly"

# ── Internal ───────────────────────────────────────────────────────────────────
enum State { CHASE, WINDUP, DASH, ESCAPE, COOLDOWN, DEAD }
var state         : State   = State.CHASE
var state_timer   : float   = 0.0
var cooldown_left : float   = 2.0
var hover_t       : float   = 0.0
var dash_dir      : Vector2 = Vector2.ZERO
var hit_this_dash : bool    = false
var hp            : int     = 0

var player: Node2D = null
@onready var sprite: AnimatedSprite2D = _find_sprite()

# ── Setup ──────────────────────────────────────────────────────────────────────

func _find_sprite() -> AnimatedSprite2D:
	for c in get_children():
		if c is AnimatedSprite2D:
			return c
	return null

func _find_player() -> void:
	var group := get_tree().get_nodes_in_group("player")
	for n in group:
		if n != self:
			player = n
			return
	var by_name = get_tree().root.find_child("Player", true, false)
	if by_name and by_name != self:
		player = by_name
		return
	_search_for_body(get_tree().root)

func _search_for_body(node: Node) -> void:
	if player:
		return
	if node is CharacterBody2D and node != self:
		player = node
		return
	for child in node.get_children():
		_search_for_body(child)

func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	_find_player()
	if player:
		print("FlyingEnemy: found player → ", player.name)
	else:
		push_warning("FlyingEnemy: could not find player.")

# ── Main loop ──────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	hover_t += delta

	if state == State.DEAD:
		return

	if not player:
		_find_player()
		return

	match state:
		State.CHASE:    _chase(delta)
		State.WINDUP:   _windup(delta)
		State.DASH:     _dash(delta)
		State.ESCAPE:   _escape(delta)
		State.COOLDOWN: _cooldown(delta)

	move_and_slide()

# ── States ─────────────────────────────────────────────────────────────────────

func _chase(delta: float) -> void:
	var dir := (player.global_position - global_position).normalized()
	velocity = velocity.lerp(dir * move_speed, 6.0 * delta)
	velocity.y += sin(hover_t * hover_frequency * TAU) * hover_amplitude
	_play(anim_fly)
	_face(velocity.x)
	cooldown_left -= delta
	if cooldown_left <= 0.0:
		_enter(State.WINDUP)

func _windup(delta: float) -> void:
	velocity = velocity.lerp(Vector2.ZERO, 10.0 * delta)
	velocity.y += sin(hover_t * hover_frequency * TAU) * hover_amplitude * 0.3
	dash_dir = (player.global_position - global_position).normalized()
	_face(dash_dir.x)
	_play(anim_windup)
	modulate = Color(1.0 + sin(state_timer * 20.0) * 0.5, 0.2, 0.2)
	state_timer -= delta
	if state_timer <= 0.0:
		modulate = Color.WHITE
		_enter(State.DASH)

func _dash(delta: float) -> void:
	velocity = dash_dir * dash_speed

	state_timer -= delta
	if state_timer <= 0.0:
		_enter(State.ESCAPE)

func _escape(delta: float) -> void:
	velocity.x = lerp(velocity.x, 0.0, 6.0 * delta)
	velocity.y = lerp(velocity.y, 0.0, 3.0 * delta)
	_face(velocity.x)
	state_timer -= delta
	if state_timer <= 0.0:
		_enter(State.COOLDOWN)

func _cooldown(delta: float) -> void:
	velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)
	velocity.y += sin(hover_t * hover_frequency * TAU) * hover_amplitude
	_play(anim_fly)
	_face(velocity.x)
	cooldown_left -= delta
	if cooldown_left <= 0.0:
		_enter(State.CHASE)

# ── State transitions ──────────────────────────────────────────────────────────

func _enter(new_state: State) -> void:
	state = new_state
	match new_state:
		State.WINDUP:
			state_timer = dash_windup
			dash_dir = (player.global_position - global_position).normalized()
		State.DASH:
			state_timer = dash_duration
			hit_this_dash = false
			_play(anim_dash)
			_face(dash_dir.x)
		State.ESCAPE:
			state_timer = escape_duration
			velocity = Vector2(-dash_dir.x * 100.0, -escape_speed)
			_play(anim_escape)
			_face(-dash_dir.x)
		State.COOLDOWN:
			cooldown_left = dash_cooldown
		State.CHASE:
			cooldown_left = dash_cooldown

# ── Sprite helpers ─────────────────────────────────────────────────────────────

func _play(anim_name: String) -> void:
	if sprite == null:
		return
	if not sprite.sprite_frames.has_animation(anim_name):
		anim_name = anim_fly
	if sprite.animation != anim_name:
		sprite.play(anim_name)

func _face(x_vel: float) -> void:
	if sprite == null:
		return
	if x_vel > 10.0:
		sprite.flip_h = false
	elif x_vel < -10.0:
		sprite.flip_h = true

# ── Taking damage ──────────────────────────────────────────────────────────────

# ── Offscreen spawn positions based on camera zoom 1.19, Y offset -45.565 ────

func _offscreen_positions(center: Vector2, count: int) -> Array:
	var hw  : float = 618.0
	var hh  : float = 383.0
	var cam_center := center + Vector2(0.0, -45.565)
	var result : Array = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in range(count):
		var edge := rng.randi() % 4
		var pos  := Vector2.ZERO
		match edge:
			0:
				pos = cam_center + Vector2(rng.randf_range(-hw, hw), -hh - rng.randf_range(20, 100))
			1:
				pos = cam_center + Vector2(rng.randf_range(-hw, hw),  hh + rng.randf_range(20, 100))
			2:
				pos = cam_center + Vector2(-hw - rng.randf_range(20, 100), rng.randf_range(-hh, hh))
			3:
				pos = cam_center + Vector2( hw + rng.randf_range(20, 100), rng.randf_range(-hh, hh))
		result.append(pos)
	return result

# Call this from the player when the dash hits
func explode_and_respawn() -> void:
	hp -= 1
	if hp > 0:
		# Still alive — flash white and show remaining hp
		print("Enemy HP: ", hp, "/", max_hp)
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color(4, 4, 4), 0.05)
		tween.tween_property(self, "modulate", Color.WHITE, 0.1)
		return

	# Dead — remove from groups so player can't target it anymore
	_die()

func _die() -> void:
	state = State.DEAD
	remove_from_group("enemy")
	set_physics_process(false)

	# Disable ALL CollisionShape2D children so nothing can interact with corpse
	for child in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).disabled = true
		if child is CollisionPolygon2D:
			(child as CollisionPolygon2D).disabled = true

	var spawn_pos   := global_position
	var parent_node := get_parent()
	var scene_path  := scene_file_path

	# Fade out
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(0, 0, 0, 0), 0.3)
	tween.tween_callback(func():
		# Fully gone — now start respawn timer
		visible = false

		var respawn_timer := Timer.new()
		respawn_timer.wait_time = 3.0
		respawn_timer.one_shot  = true
		parent_node.add_child(respawn_timer)
		respawn_timer.start()

		respawn_timer.timeout.connect(func():
			respawn_timer.queue_free()

			# Spawn 3 enemies just outside the player's visible area
			var player_pos := spawn_pos
			if player != null:
				player_pos = player.global_position

			var positions : Array = _offscreen_positions(player_pos, 3)

			if scene_path != "":
				var packed = load(scene_path)
				if packed:
					for i in range(3):
						var e = packed.instantiate()
						parent_node.add_child(e)
						e.global_position = positions[i]
					queue_free()
					return

			# Fallback: reset this node and duplicate 2 more
			hp            = max_hp
			state         = State.CHASE
			cooldown_left = 2.0
			hit_this_dash = false
			state_timer   = 0.0
			modulate      = Color.WHITE
			visible       = true
			set_physics_process(true)
			add_to_group("enemy")
			global_position = positions[0]
			for child in get_children():
				if child is CollisionShape2D:
					(child as CollisionShape2D).disabled = false
				if child is CollisionPolygon2D:
					(child as CollisionPolygon2D).disabled = false
			if player == null:
				_find_player()
			for i in range(1, 1):
				var copy = duplicate()
				parent_node.add_child(copy)
				copy.global_position = positions[i]
				copy.set_physics_process(true)
				copy.visible = true
		)
	)
