extends CharacterBody3D

const PropertyManagerScript = preload("res://Scripts/property/property_manager.gd")

# MOVEMENT
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const CROUCH_SPEED = 2.5

var speed = WALK_SPEED

# NORMAL PHYSICS
const NORMAL_GRAVITY = 9.8
const NORMAL_JUMP = 4.8

# LIGHTWEIGHT
const LIGHT_GRAVITY = 6.0
const LIGHT_JUMP = 7.0

# HEAVY
const HEAVY_GRAVITY = 16.0
const HEAVY_JUMP = 3.0

# BOUNCY
const BOUNCE_VELOCITY = 8.0

# STICKY
const STICKY_SPEED = 3.0

# FRICTION
const SLIPPERY_FRICTION = 1.0
const NORMAL_FRICTION = 7.0
const STICKY_FRICTION = 14.0

# CAMERA
const SENSITIVITY = 0.004
const BOB_FREQ = 2.4
const BOB_AMP = 0.08

var t_bob = 0.0

const BASE_FOV = 75.0
const FOV_CHANGE = 1.5

# CROUCHING
const STAND_HEIGHT = 1.6
const CROUCH_HEIGHT = 1.0
const CROUCH_TRANSITION_SPEED = 8.0

var is_crouching = false

# LEANING
const LEAN_ANGLE = 12.0
const LEAN_SPEED = 8.0

var lean_amount = 0.0

# PROPERTY MANAGER
@onready var property_manager = $PropertyManager

# NODE REFERENCES
@onready var head = $Head
@onready var head_bob = $Head/Headbob
@onready var camera = $Head/Headbob/Camera3D

@onready var standing_collision = $StandingCollisionShape
@onready var crouching_collision = $CrouchingCollisionShape
@onready var standup_check = $StandupCheck


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)

		camera.rotate_x(-event.relative.y * SENSITIVITY)

		camera.rotation.x = clamp(
			camera.rotation.x,
			deg_to_rad(-40),
			deg_to_rad(60)
		)


func _physics_process(delta):

	handle_property_input()
	handle_crouching(delta)
	handle_leaning(delta)

	var current_property = property_manager.get_current_property()

	# DEFAULT PHYSICS
	var current_gravity = NORMAL_GRAVITY
	var current_jump = NORMAL_JUMP
	var current_friction = NORMAL_FRICTION

	# PROPERTY EFFECTS
	match current_property:

		PropertyManagerScript.Property.NORMAL:
			current_gravity = NORMAL_GRAVITY
			current_jump = NORMAL_JUMP
			current_friction = NORMAL_FRICTION

		PropertyManagerScript.Property.LIGHTWEIGHT:
			current_gravity = LIGHT_GRAVITY
			current_jump = LIGHT_JUMP
			current_friction = NORMAL_FRICTION

		PropertyManagerScript.Property.HEAVY:
			current_gravity = HEAVY_GRAVITY
			current_jump = HEAVY_JUMP
			current_friction = NORMAL_FRICTION

		PropertyManagerScript.Property.SLIPPERY:
			current_gravity = NORMAL_GRAVITY
			current_jump = NORMAL_JUMP
			current_friction = SLIPPERY_FRICTION

		PropertyManagerScript.Property.BOUNCY:
			current_gravity = NORMAL_GRAVITY
			current_jump = NORMAL_JUMP
			current_friction = NORMAL_FRICTION

		PropertyManagerScript.Property.STICKY:
			current_gravity = NORMAL_GRAVITY
			current_jump = NORMAL_JUMP
			current_friction = STICKY_FRICTION

	# GRAVITY
	if not is_on_floor():
		velocity.y -= current_gravity * delta

	# JUMPING
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = current_jump

	# MOVEMENT SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# STICKY MOVEMENT
	if current_property == PropertyManagerScript.Property.STICKY:
		speed = min(speed, STICKY_SPEED)

	# MOVEMENT DIRECTION
	var input_dir = Input.get_vector("left", "right", "up", "down")

	var direction = (
		head.transform.basis *
		transform.basis *
		Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	# HORIZONTAL MOVEMENT
	if is_on_floor():

		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed

		else:
			velocity.x = lerp(velocity.x, 0.0, delta * current_friction)
			velocity.z = lerp(velocity.z, 0.0, delta * current_friction)

	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 3.0)

	# HEAD BOB
	t_bob += delta * velocity.length() * float(is_on_floor())
	head_bob.position = _headbob(t_bob)

	# FOV
	var velocity_clamped = clamp(
		velocity.length(),
		0.5,
		SPRINT_SPEED * 2
	)

	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped

	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)

	# FLOOR CHECK
	var was_on_floor = is_on_floor()

	move_and_slide()

	# BOUNCY LANDING
	if (
		current_property == PropertyManagerScript.Property.BOUNCY
		and not was_on_floor
		and is_on_floor()
	):
		velocity.y = BOUNCE_VELOCITY


# PROPERTY INPUT
func handle_property_input():

	if Input.is_action_just_pressed("property_normal"):
		property_manager.set_property(PropertyManagerScript.Property.NORMAL)

	elif Input.is_action_just_pressed("property_lightweight"):
		property_manager.set_property(PropertyManagerScript.Property.LIGHTWEIGHT)

	elif Input.is_action_just_pressed("property_heavy"):
		property_manager.set_property(PropertyManagerScript.Property.HEAVY)

	elif Input.is_action_just_pressed("property_slippery"):
		property_manager.set_property(PropertyManagerScript.Property.SLIPPERY)

	elif Input.is_action_just_pressed("property_bouncy"):
		property_manager.set_property(PropertyManagerScript.Property.BOUNCY)

	elif Input.is_action_just_pressed("property_sticky"):
		property_manager.set_property(PropertyManagerScript.Property.STICKY)


# HEAD BOB
func _headbob(time: float) -> Vector3:
	var pos = Vector3.ZERO

	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP

	return pos


# CROUCHING
func handle_crouching(delta):

	is_crouching = Input.is_action_pressed("crouch")

	standing_collision.disabled = is_crouching
	crouching_collision.disabled = not is_crouching

	var target_height = CROUCH_HEIGHT if is_crouching else STAND_HEIGHT

	head.position.y = lerp(
		head.position.y,
		target_height,
		delta * CROUCH_TRANSITION_SPEED
	)


# LEANING
func handle_leaning(delta):

	var target_lean = 0.0

	if Input.is_action_pressed("lean_left"):
		target_lean = deg_to_rad(LEAN_ANGLE)

	elif Input.is_action_pressed("lean_right"):
		target_lean = deg_to_rad(-LEAN_ANGLE)

	lean_amount = lerp(
		lean_amount,
		target_lean,
		delta * LEAN_SPEED
	)

	camera.rotation.z = lean_amount
