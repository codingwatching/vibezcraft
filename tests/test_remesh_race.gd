extends GutTest
# Issue #7: "obsidian for portal doesn't appear in nether".
#
# The arrival builds its frame with bare set_world_block calls and then
# ChunkManager.rebuild_chunk_now, which meshes the chunk synchronously
# and clears chunk.dirty. But the ring spawn that precedes it dirties
# every resident neighbour (seam heals), and relight results keep doing
# so for frames afterwards, so a worker remesh holding a PRE-EDIT
# snapshot is often still in flight when the frame is written. When it
# lands, ChunkNode._process accepts it because dirty is false — and the
# stale mesh overwrites the correct one. Block data keeps the obsidian
# (the portal renders from block data, so the sheet shows), the mesh
# and collision do not. This test is that exact interleaving.

const ChunkManagerScript := preload("res://scripts/world/chunk_manager.gd")
const _WORLD := "test_remesh_race"
const _COORD := Vector2i(0, 0)
const _CELL := Vector3i(8, 100, 8)

var _cm: Node3D
var _active_world_was: String
var _dimension_was: int


func before_each() -> void:
	_active_world_was = Game.active_world
	_dimension_was = DimensionContext.active()
	Game.active_world = _WORLD
	DimensionContext.set_active(DimensionContext.OVERWORLD)
	SaveLoad.clear_cache()
	SaveLoad.delete_world(_WORLD)
	_cm = ChunkManagerScript.new()
	add_child_autofree(_cm)
	_cm.chunk_scene = load("res://scenes/world/chunk.tscn")
	_cm.spawn_chunk_now(_COORD)


func after_each() -> void:
	SaveLoad.clear_cache()
	SaveLoad.delete_world(_WORLD)
	Game.active_world = _active_world_was
	DimensionContext.set_active(_dimension_was)


func _node() -> Node3D:
	return _cm._chunks.get(_COORD)


# Vertices at or above the edit cell — the obsidian cube's own faces.
func _mesh_vertices_at_edit(node: Node3D) -> int:
	var mi: MeshInstance3D = node.get("_mesh_instance")
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return 0
	var count: int = 0
	for surface: int in range(mi.mesh.get_surface_count()):
		var arrays: Array = mi.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			if v.y >= float(_CELL.y) and v.y <= float(_CELL.y) + 1.0 and v.x >= 8.0 and v.x <= 9.0:
				count += 1
	return count


func _collision_vertices_at_edit(node: Node3D) -> int:
	var faces: PackedVector3Array = node.get("_collision_faces_cache")
	var count: int = 0
	for v: Vector3 in faces:
		if v.y >= float(_CELL.y) and v.y <= float(_CELL.y) + 1.0 and v.x >= 8.0 and v.x <= 9.0:
			count += 1
	return count


# Poll rather than wait_for_task_completion: waiting consumes the task
# id, and the node's own drain in _process must be the one to do that.
func _wait_for_inflight_remesh(node: Node3D) -> void:
	var task: int = int(node.get("_remesh_task_id"))
	if task == -1:
		return
	for _i: int in range(5000):
		if WorkerThreadPool.is_task_completed(task):
			return
		OS.delay_msec(1)


func test_a_stale_inflight_remesh_cannot_overwrite_a_same_frame_rebuild() -> void:
	var node: Node3D = _node()
	assert_not_null(node)
	assert_eq(_cm.get_world_block(_CELL), Blocks.AIR, "the edit cell starts as air")
	# 1. A seam heal / relight dirties the chunk; the node's _process
	#    dispatches a worker remesh from a snapshot WITHOUT the frame.
	node.chunk.dirty = true
	node._process(1.0 / 60.0)
	assert_ne(int(node.get("_remesh_task_id")), -1, "a worker remesh is in flight")
	# 2. The arrival writes the frame and rebuilds synchronously.
	_cm.set_world_block(_CELL, Blocks.OBSIDIAN)
	_cm.rebuild_chunk_now(_COORD)
	assert_gt(_mesh_vertices_at_edit(node), 0, "the rebuild shows the obsidian")
	assert_gt(_collision_vertices_at_edit(node), 0, "and collides with it")
	# 3. The stale worker lands and the node drains it over the next
	#    frames (one apply per frame through the manager's budget).
	_wait_for_inflight_remesh(node)
	for _i: int in range(4):
		_cm.set("_applies_this_frame", 0)  # a fresh frame's apply budget
		node._process(1.0 / 60.0)
	assert_gt(
		_mesh_vertices_at_edit(node), 0, "the obsidian is still meshed after the stale result"
	)
	assert_gt(_collision_vertices_at_edit(node), 0, "and still solid")
	assert_eq(_cm.get_world_block(_CELL), Blocks.OBSIDIAN, "block data was never in doubt")


func test_a_stale_result_already_waiting_on_the_apply_budget_is_dropped_too() -> void:
	var node: Node3D = _node()
	node.chunk.dirty = true
	node._process(1.0 / 60.0)
	_wait_for_inflight_remesh(node)
	# The frame's apply budget is spent: the drained result parks in
	# _pending_apply instead of being applied.
	_cm.set("_applies_this_frame", 1000)
	node._process(1.0 / 60.0)
	assert_false((node.get("_pending_apply") as Dictionary).is_empty(), "stale mesh is queued")
	_cm.set_world_block(_CELL, Blocks.OBSIDIAN)
	_cm.rebuild_chunk_now(_COORD)
	for _i: int in range(3):
		_cm.set("_applies_this_frame", 0)
		node._process(1.0 / 60.0)
	assert_gt(_mesh_vertices_at_edit(node), 0, "the queued stale mesh never replaced the rebuild")
	assert_gt(_collision_vertices_at_edit(node), 0)


func test_an_edit_after_the_rebuild_still_remeshes_normally() -> void:
	# The invalidation must not swallow legitimate later work: an edit
	# that dirties the chunk after a synchronous rebuild gets its own
	# worker remesh and lands.
	var node: Node3D = _node()
	_cm.set_world_block(_CELL, Blocks.OBSIDIAN)
	_cm.rebuild_chunk_now(_COORD)
	var above: Vector3i = _CELL + Vector3i(0, 1, 0)
	_cm.set_world_block(above, Blocks.OBSIDIAN)  # plain async path
	node._process(1.0 / 60.0)  # dispatch
	_wait_for_inflight_remesh(node)
	for _i: int in range(3):
		_cm.set("_applies_this_frame", 0)
		node._process(1.0 / 60.0)
	var mi: MeshInstance3D = node.get("_mesh_instance")
	var found_upper: bool = false
	for surface: int in range(mi.mesh.get_surface_count()):
		for v: Vector3 in (
			mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		):
			if v.y >= 102.0 and v.x >= 8.0 and v.x <= 9.0:
				found_upper = true
	assert_true(found_upper, "the second block's top face was meshed by the async path")
