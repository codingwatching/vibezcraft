# gdlint: disable=max-public-methods
extends GutTest

# Field report #8 (github.com/donth77/vibezcraft/issues/8). One file per
# report rather than one per subsystem: these are unrelated defects that
# happen to share a reporter, and keeping them together is what makes a
# re-test of that issue a single run. Each test names the symptom the
# reporter saw so the mapping back to the report survives.

const _SNOWBALL_SCRIPT: GDScript = preload("res://scripts/entities/snowball.gd")
const _DROPPED_ITEM_SCRIPT: GDScript = preload("res://scripts/world/dropped_item.gd")
const _PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const _PORTAL_RENDERER: GDScript = preload("res://scripts/world/portal_renderer.gd")
const _PIGMAN_SCRIPT: GDScript = preload("res://scripts/entities/zombie_pigman.gd")
const _INTERACTION_SCRIPT: GDScript = preload("res://scripts/player/interaction.gd")

const _FLOOR_Y: int = 63


# Minimal voxel world. Deliberately NOT a Node: half of what is under test
# is code that used to reach for the physics server or for a node's light
# API, and a plain RefCounted proves those paths are gone.
class VoxelWorld:
	extends RefCounted
	var blocks: Dictionary = {}
	var metas: Dictionary = {}
	var drops: Array = []

	func get_world_block(pos: Vector3i) -> int:
		return blocks.get(pos, Blocks.AIR)

	func get_world_block_meta(pos: Vector3i) -> int:
		return metas.get(pos, 0)

	func set_world_block(pos: Vector3i, id: int, meta: int = -1) -> bool:
		blocks[pos] = id
		metas[pos] = 0 if meta < 0 else (meta & 0xF)
		return true

	func set_world_block_with_meta(pos: Vector3i, id: int, meta: int) -> bool:
		blocks[pos] = id
		metas[pos] = meta & 0xF
		return true

	func spawn_block_drop(pos: Vector3i, dropped_id: int) -> void:
		drops.append([pos, dropped_id])

	func get_chunk_at_coord(_coord: Vector2i):
		return null

	func put(pos: Vector3i, id: int, meta: int = 0) -> void:
		blocks[pos] = id
		metas[pos] = meta


# Same world, as a Node. Entities type their manager reference as `Node`,
# so a RefCounted assigned to one is silently dropped — and a null manager
# is exactly the state these tests must not accidentally be asserting on.
# It answers light queries too, standing in for the ChunkManager that
# BlockFx samples through.
class VoxelWorldNode:
	extends Node3D
	var blocks: Dictionary = {}
	var metas: Dictionary = {}

	func get_world_block(pos: Vector3i) -> int:
		return blocks.get(pos, Blocks.AIR)

	func get_world_block_meta(pos: Vector3i) -> int:
		return metas.get(pos, 0)

	func set_world_block(pos: Vector3i, id: int, meta: int = -1) -> bool:
		blocks[pos] = id
		metas[pos] = 0 if meta < 0 else (meta & 0xF)
		return true

	func set_world_block_with_meta(pos: Vector3i, id: int, meta: int) -> bool:
		blocks[pos] = id
		metas[pos] = meta & 0xF
		return true

	func get_world_sky_light(_pos: Vector3i) -> int:
		return 15

	func get_world_block_light(_pos: Vector3i) -> int:
		return 0

	func put(pos: Vector3i, id: int, meta: int = 0) -> void:
		blocks[pos] = id
		metas[pos] = meta


# Duck-typed stand-in for the player in the save round-trip. PlayerSave
# reads everything through `.get(...)`, and instantiating the real scene
# here would drag in UI children whose _ready needs a live viewport.
class PitchStub:
	extends Node3D
	var inventory: Inventory = Inventory.new()
	var health: int = 20
	var _look_pitch: float = 0.0


var _dimension_was: int = 0


func before_each() -> void:
	_dimension_was = DimensionContext.active()
	DimensionContext.set_active(DimensionContext.OVERWORLD)
	TickScheduler.reset_for_tests()


func after_each() -> void:
	DimensionContext.set_active(_dimension_was)


# --- "throwing snowballs results in a crash" ---


# BlockFx takes ONE node for both the emitter's scene parent and the voxel
# light sample, and the snowball handed it its own parent (`Main`) instead
# of the ChunkManager. The light query then hit a bare Node3D:
#   Invalid call. Nonexistent function 'get_world_sky_light' in base 'Node3D'
func test_snowball_impact_particles_sample_light_from_the_chunk_manager() -> void:
	var manager := VoxelWorldNode.new()
	add_child_autofree(manager)
	manager.put(Vector3i(0, _FLOOR_Y, 0), Blocks.STONE)
	var ball: Node3D = _SNOWBALL_SCRIPT.new()
	add_child_autofree(ball)
	ball.set("_chunk_manager", manager)
	assert_eq(ball.get("_chunk_manager"), manager, "the fizzle has a real manager to sample")
	# The throw used to die right here. A clean call plus a freed projectile
	# is the whole contract.
	ball.call("_fizzle_at", Vector3(0.5, float(_FLOOR_Y) + 1.0, 0.5))
	assert_true(ball.is_queued_for_deletion(), "the snowball despawns after its burst")


# Belt and braces for the same crash: the shared helper must degrade to
# full brightness for a node that cannot answer light queries at all,
# rather than raising and killing whatever entity called it.
func test_entity_lighting_tolerates_a_node_that_is_not_the_manager() -> void:
	var stray := Node3D.new()
	autofree(stray)
	var brightness: float = EntityLighting.sample_brightness(stray, Vector3i.ZERO)
	assert_eq(brightness, 1.0, "no light API → full brightness, no error")


# --- "you can look up/down without a limit ... upside down or bugged" ---


func test_look_pitch_cannot_pass_vertical_however_hard_you_flick() -> void:
	var player: CharacterBody3D = _PLAYER_SCENE.instantiate()
	autofree(player)
	player.health = 20
	var camera: Camera3D = player.get_node("Camera3D")
	player.set("_camera", camera)
	var limit: float = deg_to_rad(float(player.get("PITCH_LIMIT_DEG")))
	# Twenty hard upward flicks. The old code clamped `_camera.rotation.x`
	# AFTER rotating, and Godot's YXZ Euler decomposition never reports
	# |x| > 90° — it hands back a smaller x with y and z flipped by 180°,
	# so every one of these passed the clamp and rolled the view over.
	for _i: int in range(20):
		player.apply_look_delta(Vector2(0.0, -0.5))
	assert_almost_eq(float(player.get("_look_pitch")), limit, 1e-6, "pinned at the limit")
	assert_almost_eq(camera.rotation.x, limit, 1e-6, "camera agrees")
	assert_almost_eq(camera.rotation.z, 0.0, 1e-6, "no 180° roll — the view stays upright")
	for _i: int in range(40):
		player.apply_look_delta(Vector2(0.0, 0.5))
	assert_almost_eq(float(player.get("_look_pitch")), -limit, 1e-6, "pinned looking down")
	assert_almost_eq(camera.rotation.z, 0.0, 1e-6, "still upright")


# The view-bob offsets are added on top of the look pitch, so they get their
# own clamp: falling adds about +10° of airborne tilt, and on a view already
# parked at the limit that would carry the camera past vertical — the same
# upside-down render, arriving through the effects path rather than input.
func test_fall_tilt_cannot_carry_a_maxed_out_view_past_vertical() -> void:
	var player: CharacterBody3D = _PLAYER_SCENE.instantiate()
	autofree(player)
	player.health = 20
	var camera: Camera3D = player.get_node("Camera3D")
	player.set("_camera", camera)
	var limit: float = deg_to_rad(float(player.get("PITCH_LIMIT_DEG")))
	# Look straight up, then fall hard.
	for _i: int in range(20):
		player.apply_look_delta(Vector2(0.0, -0.5))
	player.velocity = Vector3(0.0, -60.0, 0.0)
	for _i: int in range(120):
		player.call("_apply_camera_effects", 1.0 / 60.0)
		assert_lte(camera.rotation.x, limit + 1e-6, "camera never tips over the top")
	assert_gt(absf(float(player.get("_bob_pitch_deg"))), 0.5, "premise: the fall tilt engaged")


# Moving the look pose off the camera's Euler and onto `_look_pitch` means
# the save has to carry the scalar: restoring only the camera would have
# the next frame's effects pass rewrite it back to level.
func test_saved_look_pitch_survives_a_round_trip() -> void:
	# Throwaway slot, never a real one: the suite writes to the live
	# user:// dir (see test_save_load.gd's migration helpers).
	var world_name := "test_issue8_pitch_roundtrip"
	SaveLoad.delete_world(world_name)
	var player := PitchStub.new()
	add_child_autofree(player)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	player.add_child(camera)
	player._look_pitch = -0.42
	camera.rotation.x = -0.42
	assert_true(PlayerSave.save_player(player, world_name), "saved")
	player._look_pitch = 0.0
	camera.rotation.x = 0.0
	assert_true(PlayerSave.load_player(player, world_name), "loaded")
	assert_almost_eq(player._look_pitch, -0.42, 1e-5, "look pitch restored")
	assert_almost_eq(camera.rotation.x, -0.42, 1e-5, "and the camera matches it")
	SaveLoad.delete_world(world_name)


# --- "3rd person camera is like first person just placed away" ---


func test_third_person_camera_orbits_the_eye_instead_of_trailing_at_a_fixed_spot() -> void:
	var player: CharacterBody3D = _PLAYER_SCENE.instantiate()
	autofree(player)
	player.health = 20
	var camera: Camera3D = player.get_node("Camera3D")
	player.set("_camera", camera)
	player.perspective = player.PERSPECTIVE_THIRD_BACK
	player.set("_look_pitch", 0.0)
	var level: Vector3 = player.call("_third_person_camera_offset")
	# Look straight up: the boom has to swing DOWN and in, or the player
	# leaves the frame entirely (which is what the report showed).
	player.set("_look_pitch", deg_to_rad(80.0))
	var looking_up: Vector3 = player.call("_third_person_camera_offset")
	assert_lt(looking_up.y, level.y, "camera drops below the level-look height")
	assert_lt(looking_up.z, level.z, "and pulls in toward the player")
	# Looking down mirrors it.
	player.set("_look_pitch", deg_to_rad(-80.0))
	var looking_down: Vector3 = player.call("_third_person_camera_offset")
	assert_gt(looking_down.y, level.y, "camera rises when looking down")
	# The boom length is preserved at every pitch — it is an orbit, not a
	# stretch.
	var eye: Vector3 = player.get("_CAM_FIRST_PERSON")
	var distance: float = float(player.get("_CAM_THIRD_DISTANCE"))
	for offset: Vector3 in [level, looking_up, looking_down]:
		assert_almost_eq((offset - eye).length(), distance, 1e-5, "constant boom length")


# --- "water block source expanded in the nether" ---


func test_water_evaporates_in_a_dimension_that_forbids_it() -> void:
	var world := VoxelWorld.new()
	world.put(Vector3i(0, _FLOOR_Y, 0), Blocks.NETHERRACK)
	world.put(Vector3i(0, _FLOOR_Y + 1, 0), Blocks.WATER_FLOWING)
	DimensionContext.set_active(DimensionContext.NETHER)
	BlockFluids.update(world, Vector3i(0, _FLOOR_Y + 1, 0), Blocks.WATER_FLOWING)
	assert_eq(
		world.get_world_block(Vector3i(0, _FLOOR_Y + 1, 0)),
		Blocks.AIR,
		"the cell removes itself the way vanilla's onBlockAdded does"
	)


func test_water_survives_in_the_overworld() -> void:
	var world := VoxelWorld.new()
	world.put(Vector3i(0, _FLOOR_Y, 0), Blocks.STONE)
	world.put(Vector3i(0, _FLOOR_Y + 1, 0), Blocks.WATER_FLOWING)
	BlockFluids.update(world, Vector3i(0, _FLOOR_Y + 1, 0), Blocks.WATER_FLOWING)
	assert_ne(
		world.get_world_block(Vector3i(0, _FLOOR_Y + 1, 0)),
		Blocks.AIR,
		"the guard is per-dimension, not a blanket water killer"
	)


# A fluid tick carries the id the cell held when it was enqueued, so the
# evaporation guard has to confirm the cell against the world before it
# deletes anything — otherwise a tick that outlived its water blanks
# whatever the player put there instead.
func test_a_stale_water_tick_does_not_delete_the_block_that_replaced_it() -> void:
	var world := VoxelWorld.new()
	world.put(Vector3i(0, _FLOOR_Y, 0), Blocks.NETHERRACK)
	world.put(Vector3i(0, _FLOOR_Y + 1, 0), Blocks.COBBLESTONE)
	DimensionContext.set_active(DimensionContext.NETHER)
	assert_false(
		BlockFluids.evaporate_if_forbidden(world, Vector3i(0, _FLOOR_Y + 1, 0)),
		"nothing to evaporate — the cell is not water"
	)
	assert_eq(
		world.get_world_block(Vector3i(0, _FLOOR_Y + 1, 0)),
		Blocks.COBBLESTONE,
		"the replacement block is untouched"
	)


# The route the reporter actually took: ice carried down from a snow biome
# and broken, which writes WATER_STILL straight into the world.
func test_breaking_ice_in_the_nether_leaves_no_meltwater() -> void:
	var interaction: Node = _INTERACTION_SCRIPT.new()
	autofree(interaction)
	var world := VoxelWorldNode.new()
	add_child_autofree(world)
	world.put(Vector3i(0, _FLOOR_Y, 0), Blocks.NETHERRACK)
	interaction.set("_chunk_manager", world)
	var target := Vector3i(0, _FLOOR_Y + 1, 0)
	DimensionContext.set_active(DimensionContext.OVERWORLD)
	assert_eq(
		int(interaction.call("_break_replacement", target, Blocks.ICE)),
		Blocks.WATER_STILL,
		"ice still melts over solid ground in the Overworld"
	)
	DimensionContext.set_active(DimensionContext.NETHER)
	assert_eq(
		int(interaction.call("_break_replacement", target, Blocks.ICE)),
		Blocks.AIR,
		"but leaves nothing to flood the Nether with"
	)


# --- "portal was gone entirely" ---


# Vanilla's flow-blocker list (`ja.java` l()) names the portal explicitly.
# Ours derived the answer from is_solid_collision, which is false for the
# portal by design (you walk through it), so a flood overwrote the sheet
# cell by cell.
func test_water_cannot_flow_into_a_portal_cell() -> void:
	assert_false(
		Blocks.is_solid_collision(Blocks.PORTAL), "premise: the portal has no collision box"
	)
	var world := VoxelWorld.new()
	world.put(Vector3i(0, _FLOOR_Y, 0), Blocks.STONE)
	world.put(Vector3i(1, _FLOOR_Y, 0), Blocks.STONE)
	world.put(Vector3i(1, _FLOOR_Y + 1, 0), Blocks.PORTAL)
	world.put(Vector3i(0, _FLOOR_Y + 1, 0), Blocks.WATER_STILL)
	for _i: int in range(6):
		BlockFluids.update(world, Vector3i(0, _FLOOR_Y + 1, 0), Blocks.WATER_FLOWING)
	assert_eq(
		world.get_world_block(Vector3i(1, _FLOOR_Y + 1, 0)),
		Blocks.PORTAL,
		"the portal sheet is still standing"
	)


# --- "portal frame has textures on the top" ---


func test_portal_cell_mesh_draws_only_its_two_wide_faces() -> void:
	var renderer: Node3D = _PORTAL_RENDERER.new()
	autofree(renderer)
	var mesh: ArrayMesh = renderer.call("_build_cell_mesh")
	assert_not_null(mesh, "the shared cell mesh builds")
	var arrays: Array = mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for n: Vector3 in normals:
		assert_almost_eq(absf(n.z), 1.0, 1e-5, "every face is one of the two wide faces")
	# Two quads → 12 vertices. The rim caps would have made it 36.
	assert_eq(normals.size(), 12, "no +/-Y or +/-X rim caps")


# --- "items far away bounce" ---


# Chunk trimesh colliders only exist within ChunkManager.collision_radius
# of the player, so the old downward raycast found nothing further out: the
# item sank, the push-out-of-solid shoved it back, forever.
func test_dropped_item_rests_on_voxel_ground_with_no_physics_collider() -> void:
	var world := VoxelWorldNode.new()
	add_child_autofree(world)
	world.put(Vector3i(0, _FLOOR_Y, 0), Blocks.STONE)
	var item: Node3D = _DROPPED_ITEM_SCRIPT.new()
	add_child_autofree(item)
	item.set("_chunk_manager", world)
	var half: float = float(_DROPPED_ITEM_SCRIPT.MESH_SIZE) * 0.5
	var surface: float = float(_FLOOR_Y + 1)
	# In the tree (global_transform needs it) but with no collider anywhere:
	# a physics raycast has nothing to hit, which is the far-from-player
	# case the bug lived in.
	item.global_position = Vector3(0.5, surface + 0.6, 0.5)
	item.set("_velocity", Vector3(0.0, -4.0, 0.0))
	for _i: int in range(30):
		item.call("_apply_physics", 1.0 / 60.0)
	assert_almost_eq(
		item.global_position.y, surface + half, 1e-4, "settles exactly on the block top"
	)
	assert_almost_eq(float(item.get("_velocity").y), 0.0, 1e-6, "and stops falling")
	# The bounce was visible as a position that never stopped changing.
	var settled_y: float = item.global_position.y
	for _i: int in range(30):
		item.call("_apply_physics", 1.0 / 60.0)
	assert_almost_eq(item.global_position.y, settled_y, 1e-6, "stays put — no sink-and-pop cycle")


# A door is a 3/16 slab and a fence a 4/16 post, so most of their cell is
# open air. The voxel fallback has to honour the box's XZ footprint, not
# just its height, or an item dropped in a doorway hangs a full block up in
# the gap you walk through.
func test_dropped_item_falls_through_the_open_part_of_a_doorway() -> void:
	var world := VoxelWorldNode.new()
	add_child_autofree(world)
	world.put(Vector3i(0, _FLOOR_Y, 0), Blocks.STONE)
	# Door pair above the floor, hinged so its slab hugs the -Z side.
	world.put(Vector3i(0, _FLOOR_Y + 1, 0), Blocks.WOODEN_DOOR, 0)
	world.put(Vector3i(0, _FLOOR_Y + 2, 0), Blocks.WOODEN_DOOR, 0)
	var door_box: AABB = Blocks.collision_aabb(Blocks.WOODEN_DOOR, 0)
	assert_false(
		door_box.has_point(Vector3(0.5, 0.5, 0.5)),
		"premise: the centre of the cell is the open half you walk through"
	)
	var item: Node3D = _DROPPED_ITEM_SCRIPT.new()
	add_child_autofree(item)
	item.set("_chunk_manager", world)
	var half: float = float(_DROPPED_ITEM_SCRIPT.MESH_SIZE) * 0.5
	# Dropped down the middle of the cell, clear of whichever side the slab
	# hangs on.
	item.global_position = Vector3(0.5, float(_FLOOR_Y) + 3.5, 0.5)
	item.set("_velocity", Vector3(0.0, -2.0, 0.0))
	for _i: int in range(90):
		item.call("_apply_physics", 1.0 / 60.0)
	assert_almost_eq(
		item.global_position.y,
		float(_FLOOR_Y + 1) + half,
		1e-4,
		"lands on the floor, not on top of the door's cell"
	)


func test_dropped_item_rests_on_a_slab_at_slab_height() -> void:
	var world := VoxelWorldNode.new()
	add_child_autofree(world)
	world.put(Vector3i(0, _FLOOR_Y, 0), Blocks.HALF_SLAB)
	var item: Node3D = _DROPPED_ITEM_SCRIPT.new()
	add_child_autofree(item)
	item.set("_chunk_manager", world)
	var half: float = float(_DROPPED_ITEM_SCRIPT.MESH_SIZE) * 0.5
	var slab_top: float = float(_FLOOR_Y) + Blocks.collision_aabb(Blocks.HALF_SLAB, 0).size.y
	item.global_position = Vector3(0.5, float(_FLOOR_Y) + 1.4, 0.5)
	item.set("_velocity", Vector3(0.0, -2.0, 0.0))
	for _i: int in range(40):
		item.call("_apply_physics", 1.0 / 60.0)
	assert_almost_eq(
		item.global_position.y, slab_top + half, 1e-4, "voxel AABB, not a whole-cell snap"
	)


# --- "some items like redstone torches just lack names" ---


func test_every_block_with_an_item_form_has_a_tooltip() -> void:
	var unnamed: Array[String] = []
	for id: int in Blocks.REGISTERED_IDS:
		if id == Blocks.AIR or not Blocks.has_item_form(id):
			continue
		if Items.display_name(id).is_empty():
			unnamed.append(Blocks.name_of(id))
	assert_eq(unnamed, [] as Array[String], "blocks reachable in a slot must name themselves")


func test_the_reported_ids_name_themselves() -> void:
	assert_eq(Items.display_name(Blocks.REDSTONE_TORCH), "Redstone Torch")
	assert_eq(Items.display_name(Blocks.REDSTONE_TORCH_OFF), "Redstone Torch")
	assert_eq(Items.display_name(Blocks.LEVER), "Lever")
	assert_eq(Items.display_name(Blocks.MOSSY_COBBLESTONE), "Moss Stone")
	assert_eq(Items.display_name(Blocks.FLOWER_RED), "Rose")


# --- "the block pixels are cut in half at the edges" / "sky gap" ---


# A half-texel inset maps a 16 px tile across 15 texel widths, which halves
# the first and last pixel column of every block face. The gutter makes the
# rect land on exact texel boundaries instead.
func test_tile_uv_rects_cover_whole_texels() -> void:
	BlockAtlas.reset()
	BlockAtlas.build()
	var atlas: Texture2D = BlockAtlas.texture()
	assert_not_null(atlas, "atlas built")
	var width: float = float(atlas.get_width())
	for tex_name: String in ["stone", "grass_top", "dirt", "cobblestone"]:
		var rect: Rect2 = BlockAtlas.uv_rect(tex_name)
		var px_x: float = rect.position.x * width
		var px_w: float = rect.size.x * width
		assert_almost_eq(px_x, roundf(px_x), 1e-3, "%s starts on a texel boundary" % tex_name)
		assert_almost_eq(px_w, roundf(px_w), 1e-3, "%s spans whole texels" % tex_name)


# The gutter moves every tile's origin by a texel, so the thing that would
# quietly break is the packing offset itself: a tile clipped or shifted by
# one pixel still looks plausible in a thumbnail. Compare what the atlas
# hands back against the pack's own PNG, pixel for pixel.
func test_packed_tiles_match_the_source_art_pixel_for_pixel() -> void:
	BlockAtlas.reset()
	BlockAtlas.build()
	for entry: Array in [["stone", Blocks.STONE], ["dirt", Blocks.DIRT]]:
		var source: Texture2D = load(
			"%s%s/%s.png" % [BlockAtlas.PACK_BASE, BlockAtlas.active_pack, entry[0]]
		)
		assert_not_null(source, "%s ships in the active pack" % entry[0])
		var want: Image = source.get_image()
		if want.is_compressed():
			want.decompress()
		want.convert(Image.FORMAT_RGBA8)
		var got: Image = BlockAtlas.tile_image(int(entry[1]), BlockAtlas.FACE_SIDE)
		assert_not_null(got, "%s resolves out of the atlas" % entry[0])
		assert_eq(got.get_size(), want.get_size(), "%s keeps its full tile size" % entry[0])
		var mismatches: int = 0
		for y: int in range(want.get_height()):
			for x: int in range(want.get_width()):
				if got.get_pixel(x, y) != want.get_pixel(x, y):
					mismatches += 1
		assert_eq(mismatches, 0, "%s is packed unshifted and unclipped" % entry[0])


func test_the_gutter_repeats_the_tiles_own_edge_pixels() -> void:
	BlockAtlas.reset()
	BlockAtlas.build()
	var atlas_img: Image = BlockAtlas.texture().get_image()
	var width: float = float(atlas_img.get_width())
	var rect: Rect2 = BlockAtlas.uv_rect("grass_top")
	var x0: int = int(roundf(rect.position.x * width))
	var y0: int = int(roundf(rect.position.y * width))
	var size: int = int(roundf(rect.size.x * width))
	# One texel left of the tile must be a copy of its first column, so a
	# sampler that over-reaches gets the right colour rather than whatever
	# tile is packed next door.
	assert_eq(
		atlas_img.get_pixel(x0 - 1, y0),
		atlas_img.get_pixel(x0, y0),
		"left gutter mirrors the edge texel"
	)
	assert_eq(
		atlas_img.get_pixel(x0 + size, y0),
		atlas_img.get_pixel(x0 + size - 1, y0),
		"right gutter mirrors the edge texel"
	)
	assert_eq(
		atlas_img.get_pixel(x0, y0 - 1),
		atlas_img.get_pixel(x0, y0),
		"top gutter mirrors the edge texel"
	)


# The pale line along every grass edge was the tint gate failing, not a
# hole in the geometry: MSAA extrapolates an edge fragment's UV past the
# tile, the exact-rect test said "not grass", and the raw GRAYSCALE tile
# rendered. The gate must cover the gutter — and only the gutter.
func test_tint_gate_covers_the_gutter_but_not_the_neighbouring_tile() -> void:
	BlockAtlas.reset()
	BlockAtlas.build()
	var tile: Rect2 = BlockAtlas.uv_rect("grass_top")
	var gate: Rect2 = BlockAtlas.uv_gate_rect("grass_top")
	assert_lt(gate.position.x, tile.position.x, "gate starts before the tile")
	assert_gt(gate.end.x, tile.end.x, "and ends after it")
	var cell: float = 1.0 / float(BlockAtlas.GRID_SIZE)
	assert_almost_eq(gate.size.x, cell, 1e-6, "exactly one atlas cell wide")
	assert_almost_eq(gate.size.y, cell, 1e-6, "exactly one atlas cell tall")


# --- "zombie piglin holds the sword by the blade" ---


func test_a_mobs_held_item_is_gripped_at_the_handle() -> void:
	var pigman: Node = _PIGMAN_SCRIPT.new()
	autofree(pigman)
	var arm := Node3D.new()
	autofree(arm)
	var hand := Vector3(0.0, -0.75, 0.0)
	var basis: Basis = MobBase.held_item_basis_full_3d(1.0 / 22.0)
	var held: MeshInstance3D = pigman.attach_held_item(arm, Items.GOLD_SWORD, basis, hand)
	if held == null:
		pass_test("no item icon available in this environment")
		return
	# The mesh is built centred on the sprite, so gripping it correctly
	# means the node is offset AWAY from the hand by the handle pivot —
	# parenting it straight at the hand put the fist mid-blade.
	var pivot: Vector2 = SpriteExtruder.get_handle_pivot_offset(
		ItemIcons.icon_for(Items.GOLD_SWORD)
	)
	assert_gt(pivot.length(), 0.0, "premise: the sword sprite has an off-centre handle")
	assert_gt(
		(held.position - hand).length(), 0.0, "the mesh is shifted so the handle lands in the hand"
	)
	var expected: Vector3 = hand + basis * Vector3(-pivot.x, -pivot.y, 0.0)
	assert_almost_eq(held.position.x, expected.x, 1e-6, "handle pivot applied in item space (x)")
	assert_almost_eq(held.position.y, expected.y, 1e-6, "handle pivot applied in item space (y)")
	assert_almost_eq(held.position.z, expected.z, 1e-6, "handle pivot applied in item space (z)")
