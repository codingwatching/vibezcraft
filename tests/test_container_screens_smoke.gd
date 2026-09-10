extends GutTest
# Compile + construct every container screen that shares SlotDrag. A
# parse error in one of them would otherwise only surface when a player
# opens that screen.


func test_every_container_screen_builds_with_the_shared_drag_machine() -> void:
	for path: String in [
		"res://scripts/ui/inventory_screen.gd",
		"res://scripts/ui/crafting_table_screen.gd",
		"res://scripts/ui/chest_screen.gd",
	]:
		var script: GDScript = load(path)
		assert_not_null(script, "%s loads" % path)
		var screen: Control = script.new()
		add_child_autofree(screen)
		var drag: Variant = screen.get("_drag")
		assert_true(drag is SlotDrag, "%s owns a SlotDrag" % path)
		assert_true((drag as SlotDrag).click_left.is_valid(), "%s wired click_left" % path)
		assert_true((drag as SlotDrag).stack_at.is_valid(), "%s wired stack_at" % path)
