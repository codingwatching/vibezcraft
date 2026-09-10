extends SceneTree

# Chunk-seam crack probe — renders flat stone across two chunk borders
# over a MAGENTA clear colour at a grazing angle and counts ground
# pixels that carry magenta, i.e. sky showing through a hairline gap
# between chunk meshes (issue #7: "slight gaps between blocks showing
# the skybox").
#
# Chunk meshes are local-space with a per-node translation. Any ULP
# disagreement between (view × model_A) · p_A and (view × model_B) · p_B
# at a shared border vertex leaves a sliver no triangle covers. The
# count this prints is that sliver, in pixels, before and after a
# shader change — a number rather than a squint.
#
# Usage (opens a window — needs a display):
#   godot --path . -s scripts/dev/seam_probe.gd
# Writes nothing to user://.

const _SIZE := Vector2i(1280, 720)
const _FLOOR_Y: int = 60


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var atlas: GDScript = load("res://scripts/world/block_atlas.gd")
	var mesher: GDScript = load("res://scripts/world/mesher.gd")
	var lighting: GDScript = load("res://scripts/world/lighting.gd")
	var chunk_script: GDScript = load("res://scripts/world/chunk.gd")
	var blocks: GDScript = load("res://scripts/world/blocks.gd")
	atlas.build()
	root.get_window().size = _SIZE
	RenderingServer.set_default_clear_color(Color(1.0, 0.0, 1.0))
	var world := Node3D.new()
	root.add_child(world)
	# World offset in blocks, applied to every chunk AND the camera:
	# transform-rounding cracks grow with the magnitude of the float
	# coordinates, so a probe near the origin can miss what a player
	# 3000 blocks out sees. SEAM_PROBE_OFFSET=3000 etc.
	var offset_blocks: float = float(OS.get_environment("SEAM_PROBE_OFFSET").to_int())
	var offset := Vector3(offset_blocks, 0.0, offset_blocks)
	# 3x3 chunks of flat stone; the borders at x = 16, 32 and z = 16, 32.
	for cx: int in range(3):
		for cz: int in range(3):
			var chunk = chunk_script.new()
			for y: int in range(_FLOOR_Y + 1):
				for z: int in range(16):
					for x: int in range(16):
						chunk.set_block_unchecked(x, y, z, blocks.STONE)
			lighting.fill_sky_light(chunk)
			var data: Dictionary = mesher.mesh_chunk_fast(chunk)
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = data.vertices
			arrays[Mesh.ARRAY_NORMAL] = data.normals
			arrays[Mesh.ARRAY_TEX_UV] = data.uvs
			arrays[Mesh.ARRAY_COLOR] = data.colors
			arrays[Mesh.ARRAY_INDEX] = data.indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, atlas.material())
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(cx * 16, 0, cz * 16) + offset
			world.add_child(mi)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 70.0
	camera.current = true
	var counts: Array[int] = []
	# Several grazing viewpoints along and across both seam directions;
	# a crack only shows where the eye skims the surface near the border.
	var views: Array = [
		[Vector3(24.0, 61.4, 2.0), Vector3(24.0, 60.9, 46.0)],
		[Vector3(2.0, 61.4, 24.0), Vector3(46.0, 60.9, 24.0)],
		[Vector3(16.3, 61.6, 3.0), Vector3(16.0, 60.8, 40.0)],
		[Vector3(30.0, 62.0, 30.0), Vector3(12.0, 60.6, 12.0)],
		[Vector3(8.0, 61.2, 8.0), Vector3(40.0, 60.9, 40.0)],
		# Close, looking down across a seam at ~35°, like the report.
		[Vector3(14.0, 62.6, 20.0), Vector3(19.0, 61.0, 14.0)],
		[Vector3(20.5, 62.6, 13.5), Vector3(14.0, 61.0, 19.0)],
		[Vector3(31.0, 62.4, 33.5), Vector3(34.0, 61.0, 29.0)],
		[Vector3(15.5, 63.0, 15.5), Vector3(17.0, 61.0, 17.0)],
	]
	for view: Array in views:
		camera.position = (view[0] as Vector3) + offset
		camera.look_at((view[1] as Vector3) + offset, Vector3.UP)
		for _i: int in range(3):
			await process_frame
		var img: Image = root.get_viewport().get_texture().get_image()
		counts.append(_count_magenta(img))
		var dump: String = OS.get_environment("SEAM_PROBE_DUMP_DIR")
		if dump != "":
			img.save_png("%s/seam_view_%d.png" % [dump, counts.size()])
	print(
		(
			"[SEAM] offset=%d crack pixels per view: %s  total=%d"
			% [int(offset_blocks), str(counts), _sum(counts)]
		)
	)
	quit(0)


# Stone is grey (r ≈ g ≈ b). A pixel blended with the magenta clear
# colour lifts red and blue above green. Only pixels BELOW the horizon
# count: per column, the first non-background row plus a small margin.
static func _count_magenta(img: Image) -> int:
	var count: int = 0
	var h: int = img.get_height()
	var w: int = img.get_width()
	for x: int in range(w):
		var horizon: int = -1
		for y: int in range(h):
			var c: Color = img.get_pixel(x, y)
			if not (c.r > 0.9 and c.g < 0.1 and c.b > 0.9):
				horizon = y
				break
		if horizon < 0:
			continue
		for y: int in range(horizon + 4, h):
			var c: Color = img.get_pixel(x, y)
			if c.r > c.g + 0.12 and c.b > c.g + 0.12:
				count += 1
	return count


static func _sum(values: Array[int]) -> int:
	var total: int = 0
	for v: int in values:
		total += v
	return total
