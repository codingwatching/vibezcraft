extends GutTest
# Removing a source must drain everything it fed (issue #7: "water doesn't
# deplete if source water block is destroyed").
#
# ja.java:61-63 — every level change is followed by
# notifyBlocksOfNeighborChange, and ir.java:16 is what turns a STILL
# neighbour back into a ticking FLOWING cell. The clone gated the fan-out
# on the block ID changing, so a drained source woke ring 1, ring 1
# re-levelled with a meta-only write, and rings 2..7 (long since promoted
# to STILL) never ticked again. The pool stayed, minus a dimple.
#
# This runs the real BlockFluids algorithm on a real Chunk through a
# world that applies ChunkManager's own notify rule.

const FLOOR_Y: int = 60
const POOL_Y: int = 61
const SRC := Vector3i(8, POOL_Y, 8)
const ChunkManagerScript := preload("res://scripts/world/chunk_manager.gd")


class NotifyingWorld:
	extends RefCounted
	var chunk := Chunk.new()

	func get_chunk_at_coord(coord: Vector2i) -> Chunk:
		return chunk if coord == Vector2i.ZERO else null

	func _inside(pos: Vector3i) -> bool:
		return (
			pos.x >= 0 and pos.x < 16 and pos.z >= 0 and pos.z < 16 and pos.y >= 0 and pos.y < 128
		)

	func get_world_block(pos: Vector3i) -> int:
		if _inside(pos):
			return chunk.get_block(pos.x, pos.y, pos.z)
		# The floor continues past the chunk so the drop search
		# (ja.java:115-143) sees no hole at the edge and the spread stays
		# symmetric; anything above it out there is air.
		return Blocks.STONE if pos.y <= FLOOR_Y else Blocks.AIR

	func get_world_block_meta(pos: Vector3i) -> int:
		return chunk.get_block_meta(pos.x, pos.y, pos.z) if _inside(pos) else 0

	func set_world_block(pos: Vector3i, id: int, meta: int = -1) -> bool:
		if not _inside(pos):
			return false
		var old_id: int = get_world_block(pos)
		var old_meta: int = get_world_block_meta(pos)
		chunk.set_block_with_meta(pos.x, pos.y, pos.z, id, 0 if meta < 0 else meta)
		if ChunkManagerScript.fluid_notify_needed(old_id, id, old_meta, meta):
			for offset: Vector3i in [
				Vector3i(0, 0, 0),
				Vector3i(1, 0, 0),
				Vector3i(-1, 0, 0),
				Vector3i(0, 1, 0),
				Vector3i(0, -1, 0),
				Vector3i(0, 0, 1),
				Vector3i(0, 0, -1)
			]:
				BlockFluids.on_neighbor_changed(self, pos + offset)
		if old_id != id and (Blocks.is_water(id) or Blocks.is_lava(id)):
			if id == Blocks.WATER_STILL or id == Blocks.LAVA_STILL:
				BlockFluids.on_neighbor_changed(self, pos)
			else:
				TickScheduler.schedule(pos, id, BlockFluids.WATER_TICK_RATE)
		return true

	func set_world_block_with_meta(pos: Vector3i, id: int, meta: int) -> bool:
		return set_world_block(pos, id, meta)

	func spawn_block_drop(_pos: Vector3i, _id: int) -> void:
		pass

	func water_cells() -> int:
		var count: int = 0
		for z: int in range(16):
			for x: int in range(16):
				if Blocks.is_water(chunk.get_block(x, POOL_Y, z)):
					count += 1
		return count


var _w: NotifyingWorld


func before_each() -> void:
	TickScheduler.reset_for_tests()
	_w = NotifyingWorld.new()
	for x: int in range(16):
		for z: int in range(16):
			_w.chunk.set_block(x, FLOOR_Y, z, Blocks.STONE)


func after_each() -> void:
	TickScheduler.reset_for_tests()


func _run_ticks(count: int) -> void:
	for _i: int in range(count):
		TickScheduler.advance(0.05, _w)


func _settle_pool() -> int:
	_w.set_world_block(SRC, Blocks.WATER_STILL)
	_run_ticks(200)
	return _w.water_cells()


func test_a_single_source_fills_its_full_diamond() -> void:
	var cells: int = _settle_pool()
	# Reach 7 on a flat floor: the source plus every cell within Manhattan
	# distance 7 = 1 + 4 * (1 + 2 + ... + 7) = 113.
	assert_eq(cells, 113, "the pool spreads to reach 7 before settling")
	assert_eq(TickScheduler.pending_count(), 0, "a settled pool has stopped ticking")


func test_removing_the_source_drains_every_ring() -> void:
	_settle_pool()
	_w.set_world_block(SRC, Blocks.AIR)
	_run_ticks(200)
	assert_eq(_w.water_cells(), 0, "no flowing cell survives without a source")


func test_removing_the_source_of_a_flat_pool_leaves_no_dimple() -> void:
	# The ring-1 failure looked like a level-4 dimple at the old source
	# with the rest of the pool intact; make sure the drain reaches the
	# far edge and not just the first ring.
	_settle_pool()
	_w.set_world_block(SRC, Blocks.AIR)
	_run_ticks(30)
	var far: Vector3i = SRC + Vector3i(6, 0, 0)
	assert_eq(_w.get_world_block(far), Blocks.AIR, "ring 6 drained too")


func test_two_sources_over_a_solid_floor_refill_a_bucketed_hole() -> void:
	# ja.java:45-47 — the infinite-water rule survives the drain fix.
	_w.set_world_block(SRC, Blocks.WATER_STILL)
	_w.set_world_block(SRC + Vector3i(2, 0, 0), Blocks.WATER_STILL)
	_run_ticks(200)
	var middle: Vector3i = SRC + Vector3i(1, 0, 0)
	assert_eq(_w.get_world_block_meta(middle), 0, "the cell between two sources is a source")
	_w.set_world_block(middle, Blocks.AIR)
	_run_ticks(40)
	assert_true(Blocks.is_water(_w.get_world_block(middle)), "the hole refills")
	assert_eq(_w.get_world_block_meta(middle), 0, "as a source")
