extends GutTest
# Issue #7: "furnace ui shows lit up ui stretched when first entering".
#
# The flame and cook-arrow indicators were built visible with ZERO-sized
# atlas regions. Godot reads a zero region dimension as "use the whole
# sheet", and a TextureRect in the default expand mode grows to the
# texture's size, so the first frame drew a 256-px column of gui art,
# squashed, over the slots. Nothing hid it because open_at never created
# the furnace state and _refresh's has_furnace gate skipped the progress
# update until the first slot click.

const FurnaceScreenScript := preload("res://scripts/ui/furnace_screen.gd")
const _FURNACE_POS := Vector3i(3, 64, 3)

var _screen: Control


func before_each() -> void:
	FurnaceManager.clear_all()
	_screen = FurnaceScreenScript.new()
	add_child_autofree(_screen)
	_screen.bind(Inventory.new())


func after_each() -> void:
	FurnaceManager.clear_all()


func test_opening_a_never_used_furnace_creates_its_state() -> void:
	assert_false(FurnaceManager.has_furnace(_FURNACE_POS))
	_screen.open_at(_FURNACE_POS)
	assert_true(FurnaceManager.has_furnace(_FURNACE_POS), "open_at materialises the tile entity")


func test_indicators_are_hidden_on_a_cold_furnace() -> void:
	_screen.open_at(_FURNACE_POS)
	var arrow: TextureRect = _screen.get("_arrow_fill")
	var flame: TextureRect = _screen.get("_flame_fill")
	assert_false(arrow.visible, "no cook progress → no arrow")
	assert_false(flame.visible, "no burn → no flame")


func test_indicators_never_carry_a_zero_sized_region() -> void:
	# The construction-time defaults, before any refresh has run.
	var fresh: Control = FurnaceScreenScript.new()
	add_child_autofree(fresh)
	var arrow_atlas: AtlasTexture = fresh.get("_arrow_atlas")
	var flame_atlas: AtlasTexture = fresh.get("_flame_atlas")
	assert_gt(arrow_atlas.region.size.x, 0.0, "arrow region has width")
	assert_gt(arrow_atlas.region.size.y, 0.0, "arrow region has height")
	assert_gt(flame_atlas.region.size.x, 0.0, "flame region has width")
	assert_gt(flame_atlas.region.size.y, 0.0, "flame region has height")
	assert_false((fresh.get("_arrow_fill") as TextureRect).visible, "arrow starts hidden")
	assert_false((fresh.get("_flame_fill") as TextureRect).visible, "flame starts hidden")
	assert_eq(
		(fresh.get("_arrow_fill") as TextureRect).expand_mode,
		TextureRect.EXPAND_IGNORE_SIZE,
		"the control never inherits the texture's minimum size"
	)


func test_a_burning_furnace_shows_a_proportional_flame() -> void:
	_screen.open_at(_FURNACE_POS)
	var state: Dictionary = FurnaceManager.get_or_create(_FURNACE_POS)
	state.burn_total = 200
	state.burn_time = 100
	_screen.call("_refresh")
	var flame: TextureRect = _screen.get("_flame_fill")
	var flame_atlas: AtlasTexture = _screen.get("_flame_atlas")
	assert_true(flame.visible)
	# 14-px flame at half burn → 7 px tall, drawn at 7 * SCALE.
	assert_eq(int(flame_atlas.region.size.y), 7)
	assert_eq(int(flame.size.y), 7 * int(_screen.get("SCALE")))
