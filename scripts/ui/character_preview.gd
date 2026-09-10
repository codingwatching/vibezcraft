class_name CharacterPreview
extends TextureRect

# LIVE preview of the player avatar in the inventory. An offscreen
# SubViewport (built once at boot, parented to the Game autoload) renders
# the character_model continuously via UPDATE_ALWAYS; this TextureRect
# displays viewport.get_texture() directly so any mutation of the model
# (future armor equip, head tracking, animation) auto-reflects without
# any per-frame work in this script.
#
# Other code can grab the model via CharacterPreview.get_model() to mutate
# it (e.g. attach an armor mesh, set head rotation).

const PREVIEW_PX: int = 256
# ne.java's cursor reference point inside this 50×70 GUI rectangle, and
# the model's feet in its own frame (origin = capsule centre). See
# _apply_mouse_tracking.
const _REFERENCE_GUI := Vector2(24.0, 17.0)
const _FEET := Vector3(0.0, -0.9, 0.0)

static var _viewport: SubViewport
static var _model: Node3D
static var _held_mesh: Node3D  # preview's right-hand item (pivot root)
# Screen pixels per GUI unit of the panel this preview is drawn on.
var gui_scale: float = 1.0


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _viewport != null:
		# Live ViewportTexture binding — auto-updates as the viewport renders.
		texture = _viewport.get_texture()


func _process(_delta: float) -> void:
	_apply_mouse_tracking()


# Vanilla ne.java:60-76 (GuiInventory.drawPlayerOnGui). The preview
# camera is at -Z looking at +Z, and Godot's right-handed view basis puts
# world -X on the viewer's right, so a positive yaw turns the model
# toward "mouse right" with no sign flip.
#
# All of it is in GUI units — vanilla measures the cursor in its scaled
# GUI coordinates, not screen pixels. This control is drawn at
# `gui_scale`× (5 on the inventory panel), and the earlier port fed raw
# pixels into atan(d / 40), so the head hit its ±31° cap a fifth of the
# way to the edge and sat pinned there (issue #7 "head detached").
#   reference = the point vanilla measures from: 51 px right of the
#               panel's left edge and 25 down — about head height —
#               i.e. (24, 17) inside this 50×70 rectangle
#   body yaw  = atan(dx / 40) × 20°
#   head yaw  = body yaw + atan(dx / 40) × 20°  (head turns 2× body)
#   pitch     = atan(dy / 40) × 20°, applied TWICE: once as a lean of the
#               whole body about its feet (ne.java:71 glRotatef before
#               the render), once as the head's own pitch (ne.java:74)
func _apply_mouse_tracking() -> void:
	if _model == null or not is_visible_in_tree():
		return
	var mouse_gui: Vector2 = (get_global_mouse_position() - global_position) / gui_scale
	var pose: Dictionary = tracking_pose(mouse_gui)
	# Lean the yawed body toward/away from the viewer about its FEET, in
	# the screen's frame (lean outermost), as ne.java's glRotatef does
	# around the model's base translate point.
	var basis: Basis = Basis(Vector3.RIGHT, pose.pitch) * Basis(Vector3.UP, pose.body_yaw)
	_model.transform = Transform3D(basis, _FEET - basis * _FEET)
	var head: Node3D = _model.get("head") as Node3D
	if head != null:
		head.rotation.y = pose.head_yaw
		head.rotation.x = pose.pitch


# The three angles ne.java derives from a cursor position given in GUI
# units relative to this rectangle's top-left. Pure, for the tests.
static func tracking_pose(mouse_gui: Vector2) -> Dictionary:
	var dx: float = mouse_gui.x - _REFERENCE_GUI.x  # +ve = mouse on viewer's RIGHT
	var dy: float = mouse_gui.y - _REFERENCE_GUI.y  # +ve = mouse BELOW the reference
	var yaw: float = atan(dx / 40.0) * 20.0 * PI / 180.0
	# Positive X rotation tilts a -Z-facing face UP; mouse above the
	# reference → dy negative → negate to get positive pitch.
	var pitch: float = -atan(dy / 40.0) * 20.0 * PI / 180.0
	return {"body_yaw": yaw, "head_yaw": yaw, "pitch": pitch}


# Build the offscreen viewport + character model. Call once at boot from
# Game._ready (or any node living in the persistent scene tree).
static func setup_renderer(parent: Node) -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(PREVIEW_PX, PREVIEW_PX)
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	# Only render when the inventory's TextureRect is actually drawn (i.e.,
	# when the inventory screen is open). Saves a 256² render every frame
	# while the player is just walking around with the inventory closed.
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	parent.add_child(_viewport)
	# Explicit World3D — own_world_3d=true was leaving world_3d null and the
	# camera/lights/model were rendering into a non-existent world.
	_viewport.world_3d = World3D.new()

	# Front-facing orthographic camera. Model defaults face -Z; camera at -Z
	# looking at +Z sees Steve's front. y=0.1 is the model's vertical center.
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4  # 2-unit-tall model + ~20% padding
	camera.near = 0.05
	camera.far = 10.0
	_viewport.add_child(camera)
	# look_at_from_position avoids the "Node not inside tree" error when the
	# transform is being assigned during the same frame the viewport is set up.
	camera.look_at_from_position(Vector3(0, 0.1, -4.0), Vector3(0, 0.1, 0), Vector3.UP)

	# Ambient WorldEnvironment so directional lights aren't the sole source
	# of illumination — lets the model show up reliably regardless of pose.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	_viewport.add_child(sun)
	sun.look_at_from_position(Vector3(1.0, 2.0, -2.0), Vector3.ZERO, Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	_viewport.add_child(fill)
	fill.look_at_from_position(Vector3(-1.0, 0.5, -1.0), Vector3.ZERO, Vector3.UP)

	var model_script: GDScript = load("res://scripts/player/character_model.gd")
	if model_script == null:
		push_error("[CharPreview] failed to load character_model.gd")
		return
	_model = model_script.new()
	_viewport.add_child(_model)
	# Keep materials unshaded so the preview is robust to lighting tweaks.
	_force_unshaded(_model)


# Returns the live model node so other code can mutate it (attach armor
# meshes to limb anchors, rotate head, drive walking animation, etc.).
static func get_model() -> Node3D:
	return _model


# Sets the item shown in the preview's right hand. Mirrors the player's
# third-person setup: pivot at the wrist with vanilla orient tilt
# (+50° Y / -25° Z), voxel-extruded sprite mesh with the held_item_world
# shader (per-face Notch shading + alpha cutoff), handle-pivot offset
# for tools. AIR (or 0) hides the mesh.
static func set_held_item(item_id: int) -> void:
	if _model == null:
		return
	var arm_r: Node3D = _model.get("arm_r") as Node3D
	if arm_r == null:
		return
	if _held_mesh != null:
		_held_mesh.queue_free()
		_held_mesh = null
	if item_id == 0:
		return
	# Wrap in a pivot → orient node pair so we can reproduce the same
	# rest-pose tilt the TP-world held tool uses in player.gd.
	var pivot := Node3D.new()
	pivot.position = Vector3(0, -0.75, -0.15)
	pivot.rotation = Vector3(deg_to_rad(-20), deg_to_rad(35), 0)
	arm_r.add_child(pivot)
	var orient := Node3D.new()
	var orient_basis := Basis(Vector3.UP, deg_to_rad(50.0))
	orient_basis = orient_basis * Basis(Vector3(0, 0, 1), deg_to_rad(-25.0))
	orient.transform.basis = orient_basis
	pivot.add_child(orient)

	var mesh := MeshInstance3D.new()
	# Non-cube blocks (sapling, future torches/plants) take the sprite
	# path too — same reasoning as player.gd: vanilla renders them as a
	# flat 2D billboard, not a textured cube. Without this the inventory
	# avatar holds a cube tiled with the sapling icon on every face.
	var as_sprite: bool = (
		not Blocks.is_registered(item_id)
		or (item_id != 0 and Blocks.needs_gdscript_mesher(item_id))
	)
	if as_sprite:
		var tex: Texture2D = ItemIcons.icon_for(item_id)
		if tex == null:
			return
		var arr_mesh: ArrayMesh = SpriteExtruder.build(tex)
		if arr_mesh == null:
			return
		mesh.mesh = arr_mesh
		var ps: float = 0.035
		# Non-tools (coal, ingots, diamond, plants) get tighter scale + no
		# handle-pivot offset — same rule as player.gd TP logic.
		if Items.is_tool_item(item_id):
			mesh.scale = Vector3(ps, ps, ps)
			var pivot_px: Vector2 = SpriteExtruder.get_handle_pivot_offset(tex)
			mesh.position = Vector3(-pivot_px.x * ps, -pivot_px.y * ps, 0)
		else:
			var loose_ps: float = ps * 0.6
			mesh.scale = Vector3(loose_ps, loose_ps, loose_ps)
			mesh.position = Vector3.ZERO
		var shader: Shader = load("res://shaders/held_item_world.gdshader") as Shader
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("item_texture", tex)
		mat.render_priority = 50  # above body skin to avoid z-fight at the wrist
		mesh.material_override = mat
	else:
		mesh.mesh = BlockMesh.get_cube_mesh(item_id, 0.3)
	orient.add_child(mesh)
	# Track the pivot so we can queue_free the whole subtree on next swap.
	_held_mesh = pivot


# Recursively walk a node tree and override every MeshInstance3D's material
# with an unshaded clone. Skin texture (albedo) is preserved.
static func _force_unshaded(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var orig: Material = mi.mesh.surface_get_material(0)
			if orig is StandardMaterial3D:
				var unshaded: StandardMaterial3D = (orig as StandardMaterial3D).duplicate()
				unshaded.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
				mi.material_override = unshaded
	for child in node.get_children():
		_force_unshaded(child)
