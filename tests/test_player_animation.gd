extends GutTest
# Issue #7: "no walking animation, most animations are missing like player
# damage animation, if you punch the air no animation plays".

const _PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const _MODEL_SCRIPT := preload("res://scripts/player/character_model.gd")
const _WALK_SPEED: float = 4.317


func _model() -> Node3D:
	var model: Node3D = _MODEL_SCRIPT.new()
	add_child_autofree(model)
	return model


# dc.java:66-71 with hf.java:455-460's amount: at walk speed W ≈ 0.86,
# legs swing ±1.4·W ≈ 69° and arms ±1.0·W ≈ 49°. The old 38° sine was
# about half of that.
func test_walk_cycle_reaches_vanilla_amplitude_and_cadence() -> void:
	var model: Node3D = _model()
	var leg_peak: float = 0.0
	var arm_peak: float = 0.0
	var sign_flips: int = 0
	var last_sign: float = 0.0
	var dt: float = 1.0 / 60.0
	for _i: int in range(int(3.0 / dt)):
		model.update_walk_animation(_WALK_SPEED, dt)
		leg_peak = maxf(leg_peak, absf(model.leg_r.rotation.x))
		arm_peak = maxf(arm_peak, absf(model.arm_l.rotation.x))
		var s: float = signf(model.leg_r.rotation.x)
		if s != 0.0 and last_sign != 0.0 and s != last_sign:
			sign_flips += 1
		last_sign = s
	assert_between(leg_peak, deg_to_rad(60.0), deg_to_rad(80.0), "legs ≈ 69°")
	assert_between(arm_peak, deg_to_rad(40.0), deg_to_rad(58.0), "arms ≈ 49°")
	# ≈1.85 Hz stride → 2 sign flips per cycle → ≈11 over 3 s (minus ramp-up).
	assert_between(sign_flips, 8, 13, "stride cadence ≈ 1.85 Hz (got %d flips)" % sign_flips)


func test_walk_cycle_settles_when_standing() -> void:
	var model: Node3D = _model()
	for _i: int in range(60):
		model.update_walk_animation(_WALK_SPEED, 1.0 / 60.0)
	for _i: int in range(120):
		model.update_walk_animation(0.0, 1.0 / 60.0)
	# Only dc.java:130-133's idle sway (±0.05 rad) remains.
	assert_lt(absf(model.leg_r.rotation.x), 0.1, "legs return to rest")
	assert_lt(absf(model.arm_r.rotation.x), 0.1, "arms return to rest")


func test_swing_cycle_is_eight_ticks() -> void:
	assert_almost_eq(float(_MODEL_SCRIPT.SWING_DURATION_SEC), 0.4, 0.0001, "eb.java:45-55")


func test_hurt_tint_reddens_the_skin_and_clears() -> void:
	var model: Node3D = _model()
	var mat: StandardMaterial3D = model.get("_skin_mat")
	model.set_hurt_tint(true)
	assert_lt(mat.albedo_color.g, mat.albedo_color.r, "red-shifted while hurt")
	model.set_hurt_tint(false)
	assert_almost_eq(mat.albedo_color.g, mat.albedo_color.r, 0.001, "neutral again")


func test_a_hit_arms_the_camera_flinch_and_leaves_no_residue() -> void:
	var player: CharacterBody3D = _PLAYER_SCENE.instantiate()
	autofree(player)
	player.health = 20
	var camera: Camera3D = player.get_node("Camera3D")
	# Off-tree instantiation skips @onready; wire the camera by hand.
	player.set("_camera", camera)
	player.set("_look_pitch", 0.3)
	player.take_damage(1, "mob", Vector3(0.0, 0.0, 1.0))
	assert_gt(float(player.get("_hurt_time_sec")), 0.0, "hurtTime armed")
	# Step a few frames into the flinch: the camera must move off the
	# true pitch.
	var moved: bool = false
	for _i: int in range(6):
		player.call("_apply_camera_effects", 1.0 / 60.0)
		if absf(camera.rotation.x - 0.3) > 0.001 or absf(camera.rotation.z) > 0.001:
			moved = true
	assert_true(moved, "the flinch bends the view")
	# Drop the knockback the hit imparted. Off the tree nothing integrates
	# velocity, so a standing motionY would keep the airborne view tilt
	# (eb.java:75) legitimately engaged and mask what this test is about.
	player.velocity = Vector3.ZERO
	# Run the flinch out. The view has to come back to the look pitch
	# EXACTLY: the old add-offset-then-strip-it-again bookkeeping mixed the
	# Euler axes and left the world permanently tilted a little after a fall
	# or a hit (issue #8).
	for _i: int in range(180):
		player.call("_apply_camera_effects", 1.0 / 60.0)
	assert_almost_eq(camera.rotation.x, 0.3, 0.0001, "look pitch survives the flinch")
	assert_almost_eq(camera.rotation.z, 0.0, 0.0001, "no residual roll")


func test_flinch_axis_follows_the_attacker() -> void:
	var player: CharacterBody3D = _PLAYER_SCENE.instantiate()
	autofree(player)
	player.health = 20
	# Attacker straight ahead (player forward = -Z, knockback = attacker → player = +Z).
	player.take_damage(1, "mob", Vector3(0.0, 0.0, 1.0))
	assert_almost_eq(float(player.get("_attacked_at_yaw")), PI * 0.5, 0.01, "front → 90° (a nod)")
	player.set("_damage_cooldown_remaining", 0.0)
	# Attacker on the +X side.
	player.take_damage(1, "mob", Vector3(-1.0, 0.0, 0.0))
	assert_almost_eq(float(player.get("_attacked_at_yaw")), 0.0, 0.01, "right → 0° (a roll)")


# dc.java:26-27 — the head rotates about the NECK. With the pivot at the
# cube's centre a nod lifted the back of the head off the shoulders; the
# preview's raw-pixel sensitivity kept it pinned at that pose (issue #7
# "head detached from body").
func test_head_nods_from_the_neck_not_its_centre() -> void:
	var model: Node3D = _model()
	var head: Node3D = model.head
	var mesh: MeshInstance3D = model.head_mesh
	assert_almost_eq(head.position.y, 0.6, 0.0001, "pivot at the body top")
	# The mesh's bottom face sits ON the pivot at rest.
	var rest_bottom: Vector3 = mesh.global_transform * Vector3(0.0, -0.25, 0.0)
	assert_almost_eq(rest_bottom.y, 0.6, 0.0001)
	head.rotation.x = deg_to_rad(31.4)
	# The centre of the bottom face does not move: it IS the pivot.
	var nod_bottom: Vector3 = mesh.global_transform * Vector3(0.0, -0.25, 0.0)
	assert_almost_eq(nod_bottom.y, 0.6, 0.0001, "the neck stays on the shoulders through a nod")
	# And the back-bottom edge rises only by the half-width swing, never
	# by the centre-pivot's extra (1 - cos) lift.
	var back_edge: Vector3 = mesh.global_transform * Vector3(0.0, -0.25, 0.25)
	assert_lt(back_edge.y - 0.6, 0.25 * sin(deg_to_rad(31.4)) + 0.0001)


func test_preview_tracking_follows_the_vanilla_curve_in_gui_units() -> void:
	var preview_script: GDScript = load("res://scripts/ui/character_preview.gd")
	# ne.java: atan(d / 40) × 20° with d in GUI units from the reference
	# point (24, 17). 20 units right and 20 down of it:
	var pose: Dictionary = preview_script.tracking_pose(Vector2(44.0, 37.0))
	var expected: float = atan(0.5) * 20.0 * PI / 180.0  # ≈ 9.3°
	assert_almost_eq(float(pose.body_yaw), expected, 0.0001, "body yaw")
	assert_almost_eq(float(pose.head_yaw), expected, 0.0001, "head turns as much again")
	assert_almost_eq(float(pose.pitch), -expected, 0.0001, "cursor below → looks down")
	# At the reference point everything is neutral.
	var centre: Dictionary = preview_script.tracking_pose(Vector2(24.0, 17.0))
	assert_almost_eq(float(centre.body_yaw), 0.0, 0.0001)
	assert_almost_eq(float(centre.pitch), 0.0, 0.0001)
