
extends CharacterBody3D

var speed: float = 5.0

const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const CROUCH_SPEED = 2.5
const JUMP_VELOCITY = 4.8
const SENSITIVITY = 0.004

# Gravity
var gravity = 9.8

# Head bob
const BOB_FREQ = 2.4
const BOB_AMP = 0.08
var t_bob = 0.0

# FOV
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5

# Crouching
const STAND_HEIGHT = 1.6
const CROUCH_HEIGHT = 1.0
const CROUCH_TRANSITION_SPEED = 8.0

var is_crouching = false

# Camera leaning
const LEAN_ANGLE = 12.0
const LEAN_SPEED = 8.0

var lean_amount = 0.0

# Node references
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

	# Crouching and leaning
	handle_crouching(delta)
	handle_leaning(delta)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY

	# Movement speed
	if is_crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# Movement direction
	var input_dir = Input.get_vector(
		"left",
		"right",
		"up",
		"down"
	)

	var direction = (
		head.transform.basis *
		transform.basis *
		Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	# Horizontal movement
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, 0.0, delta * 7.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 7.0)
	else:
		velocity.x = lerp(
			velocity.x,
			direction.x * speed,
			delta * 3.0
		)

		velocity.z = lerp(
			velocity.z,
			direction.z * speed,
			delta * 3.0
		)

	# Head bob
	t_bob += delta * velocity.length() * float(is_on_floor())

	head_bob.position = _headbob(t_bob)

	# FOV
	var velocity_clamped = clamp(
		velocity.length(),
		0.5,
		SPRINT_SPEED * 2
	)

	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped

	camera.fov = lerp(
		camera.fov,
		target_fov,
		delta * 8.0
	)

	move_and_slide()


func _headbob(time: float) -> Vector3:
	var pos = Vector3.ZERO

	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP

	return pos

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
	
# CAMERA LEANING
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
