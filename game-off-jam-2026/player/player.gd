extends CharacterBody3D

const PropertyManagerScript = preload("res://Scripts/property/property_manager.gd")

# MOVEMENT
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const CROUCH_SPEED = 2.5

var speed = WALK_SPEED

# PLAYER SIZE
const NORMAL_SIZE = 1.0
const LIGHTWEIGHT_SIZE = 0.6
const HEAVY_SIZE = 1.5

var current_size_scale = NORMAL_SIZE

var standing_capsule: CapsuleShape3D
var crouching_capsule: CapsuleShape3D

var standing_original_height: float
var standing_original_radius: float
var crouching_original_height: float
var crouching_original_radius: float

var standing_original_position: Vector3
var crouching_original_position: Vector3

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
@onready var head_bob = %Eyes
@onready var camera = %Camera3D

@onready var standing_collision = $StandingCollisionShape
@onready var crouching_collision = $CrouchingCollisionShape
@onready var standup_check = $StandupCheck

# EXTRA NODE REFERENCES
@onready var eyes: Node3D = %Eyes
@onready var interaction_controller = %InteractionController
@onready var footsteps_se: AudioStreamPlayer3D = %Footsteps
@onready var jump_se: AudioStreamPlayer3D = %Jump
@onready var note_camera: Camera3D = %NoteCamera

# NOTE SWAY
@onready var note_hand: Marker3D = %NoteHand
@export var note_sway_amount: float = 0.1

# ITEM HAND
@onready var item_hand: Marker3D = %ItemHand
var item_hand_rest_position: Vector3

# INVENTORY
@onready var inventory_controller = %InventoryController/CanvasLayer/InventoryUI
@onready var interaction_raycast: RayCast3D = %InteractionRaycast
var inventory_opened_flag: bool = false

# MOUSE SENSITIVITY
var normal_sensitivity: float = SENSITIVITY
var current_sensitivity: float = SENSITIVITY
var sensitivity_restore_speed: float = 5.0
var sensitivity_fading_in: bool = false
var mouse_input: Vector2 = Vector2.ZERO

# MOVEMENT TRACKING
var is_in_air: bool = false

# FOOTSTEP TRACKING
var last_bob_position_x: float = 0.0
var last_bob_direction: int = 0


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Duplicate shapes so we don't modify shared resources.
	standing_capsule = standing_collision.shape.duplicate()
	crouching_capsule = crouching_collision.shape.duplicate()

	standing_collision.shape = standing_capsule
	crouching_collision.shape = crouching_capsule

	# Save original dimensions.
	standing_original_height = standing_capsule.height
	standing_original_radius = standing_capsule.radius

	crouching_original_height = crouching_capsule.height
	crouching_original_radius = crouching_capsule.radius

	standing_original_position = standing_collision.position
	crouching_original_position = crouching_collision.position

	# Save item hand position.
	item_hand_rest_position = item_hand.position

	# Listen for property changes.
	property_manager.property_changed.connect(_on_property_changed)


func _unhandled_input(event):
	if event is InputEventMouseMotion:
		if interaction_controller.isCameraLocked():
			return

		head.rotate_y(-event.relative.x * SENSITIVITY)

		camera.rotate_x(-event.relative.y * SENSITIVITY)

		camera.rotation.x = clamp(
			camera.rotation.x,
			deg_to_rad(-40),
			deg_to_rad(60)
		)
func _input(event):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

	if Input.is_action_just_pressed("inventory"):
		# End current interaction.
		if interaction_controller and interaction_controller.interaction_component != null:
			interaction_controller.interaction_component.post_interact()
			interaction_controller.interaction_component.post_interact()

		# Open inventory.
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		inventory_controller.visible = true
		interaction_raycast.enabled = false
		inventory_opened_flag = true

	elif Input.is_action_just_released("inventory"):
		close_inventory()


func _process(delta):
	# Close inventory if the inventory input is released.
	if inventory_opened_flag and not Input.is_action_pressed("inventory"):
		close_inventory()

	# Restore mouse sensitivity after camera unlock.
	if sensitivity_fading_in:
		current_sensitivity = lerp(
			current_sensitivity,
			normal_sensitivity,
			delta * sensitivity_restore_speed
		)

		if abs(current_sensitivity - normal_sensitivity) < 0.01:
			current_sensitivity = normal_sensitivity
			sensitivity_fading_in = false

	set_camera_locked(interaction_controller.isCameraLocked())


func close_inventory():
	if inventory_controller:
		inventory_controller.visible = false

		if inventory_controller.context_menu:
			inventory_controller.context_menu.visible = false

	if interaction_raycast:
		interaction_raycast.enabled = true

	inventory_opened_flag = false

	if interaction_controller and not interaction_controller.current_object:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
		jump_se.play()

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

	# EXTRA EYE MOVEMENT
	if input_dir != Vector2.ZERO:
		eyes.position.y = lerp(
			eyes.position.y,
			head_bob.position.y / 2.0,
			delta * 10.0
		)

		eyes.position.x = lerp(
			eyes.position.x,
			head_bob.position.x,
			delta * 10.0
		)
	else:
		eyes.position.y = lerp(eyes.position.y, 0.0, delta * 10.0)
		eyes.position.x = lerp(eyes.position.x, 0.0, delta * 10.0)

	# NOTE CAMERA FOV
	note_camera.fov = camera.fov

	# NOTE AND ITEM SWAY
	note_tilt_and_sway(delta, input_dir)

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

	# LANDING SOUND
	if not was_on_floor and is_on_floor():
		if is_in_air:
			footsteps_se.play()

	is_in_air = not is_on_floor()

	# FOOTSTEPS
	play_footsteps(input_dir)


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

	var target_height = (CROUCH_HEIGHT if is_crouching else STAND_HEIGHT) * current_size_scale

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


# CAMERA LOCK
func set_camera_locked(locked: bool) -> void:

	if locked:
		current_sensitivity = 0.0
		sensitivity_fading_in = false
	else:
		if current_sensitivity < normal_sensitivity:
			sensitivity_fading_in = true


# NOTE AND ITEM SWAY
func note_tilt_and_sway(delta: float, input_dir: Vector2) -> void:

	if note_hand:
		note_hand.rotation.z = lerp(
			note_hand.rotation.z,
			-input_dir.x * note_sway_amount,
			10.0 * delta
		)

		note_hand.rotation.x = lerp(
			note_hand.rotation.x,
			-input_dir.y * note_sway_amount,
			10.0 * delta
		)

	if item_hand:
		item_hand.rotation.z = lerp(
			item_hand.rotation.z,
			-input_dir.x * note_sway_amount * 2.0,
			10.0 * delta
		)

		item_hand.rotation.x = lerp(
			item_hand.rotation.x,
			-input_dir.y * note_sway_amount * 2.0,
			10.0 * delta
		)


# FOOTSTEPS
func play_footsteps(input_dir: Vector2) -> void:

	if input_dir != Vector2.ZERO and is_on_floor():

		var bob_position_x = head_bob.position.x
		var bob_direction = sign(bob_position_x - last_bob_position_x)

		# A direction change means the bobbing cycle reached a peak.
		if (
			bob_direction != 0
			and bob_direction != last_bob_direction
			and last_bob_direction != 0
		):
			footsteps_se.play()

		last_bob_direction = bob_direction
		last_bob_position_x = bob_position_x

	else:
		last_bob_direction = 0
		last_bob_position_x = head_bob.position.x


# PROPERTY SIZE CHANGE
func _on_property_changed(new_property):
	var new_size = NORMAL_SIZE

	match new_property:
		PropertyManagerScript.Property.LIGHTWEIGHT:
			new_size = LIGHTWEIGHT_SIZE

		PropertyManagerScript.Property.HEAVY:
			new_size = HEAVY_SIZE

	current_size_scale = new_size

	# Resize standing capsule.
	standing_capsule.height = standing_original_height * new_size
	standing_capsule.radius = standing_original_radius * new_size

	# Resize crouching capsule.
	crouching_capsule.height = crouching_original_height * new_size
	crouching_capsule.radius = crouching_original_radius * new_size

	# Keep the bottom of the capsules at floor level.
	standing_collision.position = standing_original_position * new_size
	crouching_collision.position = crouching_original_position * new_size

	print("Player size: ", new_size)
