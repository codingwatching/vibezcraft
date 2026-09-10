extends GutTest
# Issue #7: "drag dropping items in inventory don't display immediately,
# only shows after release". Vanilla ex.java:91-113 acts on PRESS and its
# release handler is empty; the screens deferred placing, merging,
# swapping and half-splitting to mouse-up. SlotDrag is the one state
# machine the inventory, crafting-table and chest screens now share.

const NONE: int = -1

var _slots: Array[ItemStack] = []
var _cursor: ItemStack
var _drag: SlotDrag
var _changed: int = 0


func before_each() -> void:
	_slots.clear()
	for _i: int in range(9):
		_slots.append(ItemStack.new())
	_cursor = ItemStack.new()
	_changed = 0
	_drag = SlotDrag.new()
	_drag.none_id = NONE
	_drag.cursor = _cursor
	_drag.stack_at = func(slot: int) -> ItemStack: return _slots[slot] if slot >= 0 else null
	_drag.sweep_excluded = func(slot: int) -> bool: return slot == 8
	_drag.click_left = _left
	_drag.click_right = _right
	_drag.changed = func() -> void: _changed += 1


# The inventory screen's click semantics, reduced to what the machine
# depends on: pick up / place all / merge / swap, and half-split / place
# one.
func _left(slot: int) -> void:
	var target: ItemStack = _slots[slot]
	if _cursor.is_empty():
		_cursor.copy_from(target)
		target.clear()
	elif target.is_empty():
		target.copy_from(_cursor)
		_cursor.clear()
	elif target.item_id == _cursor.item_id:
		_cursor.count = target.add(_cursor.count)
		if _cursor.count == 0:
			_cursor.item_id = Blocks.AIR
	else:
		var tmp := ItemStack.new(target.item_id, target.count)
		target.copy_from(_cursor)
		_cursor.copy_from(tmp)


func _right(slot: int) -> void:
	var target: ItemStack = _slots[slot]
	if _cursor.is_empty():
		if target.is_empty():
			return
		var half: int = (target.count + 1) / 2
		_cursor.item_id = target.item_id
		_cursor.count = half
		target.count -= half
		if target.count == 0:
			target.clear()
	elif target.is_empty() or target.item_id == _cursor.item_id:
		target.item_id = _cursor.item_id
		target.count += 1
		_cursor.count -= 1
		if _cursor.count == 0:
			_cursor.clear()


func test_pickup_happens_on_press() -> void:
	_slots[0] = ItemStack.new(Blocks.DIRT, 10)
	_drag.press(MOUSE_BUTTON_LEFT, 0)
	assert_eq(_cursor.count, 10, "the stack is on the cursor before release")
	assert_true(_slots[0].is_empty())


func test_placing_a_held_stack_happens_on_press_not_release() -> void:
	_cursor.item_id = Blocks.DIRT
	_cursor.count = 10
	_drag.press(MOUSE_BUTTON_LEFT, 3)
	assert_eq(_slots[3].count, 10, "placed at press")
	assert_true(_cursor.is_empty())
	_drag.release(MOUSE_BUTTON_LEFT, 3)
	assert_eq(_slots[3].count, 10, "release over the same slot changes nothing")


func test_swap_happens_on_press() -> void:
	_cursor.item_id = Blocks.DIRT
	_cursor.count = 5
	_slots[2] = ItemStack.new(Blocks.STONE, 7)
	_drag.press(MOUSE_BUTTON_LEFT, 2)
	assert_eq(_slots[2].item_id, Blocks.DIRT)
	assert_eq(_cursor.item_id, Blocks.STONE)
	assert_false(_drag.active, "a swap never arms a sweep")


func test_right_click_half_split_happens_on_press() -> void:
	_slots[1] = ItemStack.new(Blocks.DIRT, 9)
	_drag.press(MOUSE_BUTTON_RIGHT, 1)
	assert_eq(_cursor.count, 5)
	assert_eq(_slots[1].count, 4)


func test_left_sweep_redistributes_live_as_slots_are_entered() -> void:
	_cursor.item_id = Blocks.DIRT
	_cursor.count = 64
	_drag.press(MOUSE_BUTTON_LEFT, 0)
	assert_eq(_slots[0].count, 64, "the press slot shows the whole stack at once")
	assert_true(_drag.active)
	_drag.motion(1)
	assert_eq(_slots[0].count, 32, "re-dealt across two slots the moment the second is entered")
	assert_eq(_slots[1].count, 32)
	assert_true(_cursor.is_empty())
	_drag.motion(2)
	assert_eq([_slots[0].count, _slots[1].count, _slots[2].count], [21, 21, 21])
	assert_eq(_cursor.count, 1, "the remainder rides on the cursor")
	assert_eq(_changed, 2, "the screen repainted on every entry")
	_drag.release(MOUSE_BUTTON_LEFT, 2)
	assert_eq([_slots[0].count, _slots[1].count, _slots[2].count], [21, 21, 21])


func test_left_sweep_respects_existing_counts_and_room() -> void:
	_cursor.item_id = Blocks.DIRT
	_cursor.count = 64
	_slots[0] = ItemStack.new(Blocks.DIRT, 40)
	_drag.press(MOUSE_BUTTON_LEFT, 0)
	assert_eq(_slots[0].count, 64, "merge on press")
	assert_eq(_cursor.count, 40)
	_drag.motion(1)
	# 32 each from the 64 start: slot 0 = 40 + min(32, 24), slot 1 = 32.
	assert_eq(_slots[0].count, 64)
	assert_eq(_slots[1].count, 32)
	assert_eq(_cursor.count, 64 - 24 - 32)


func test_right_sweep_drops_one_per_slot_immediately() -> void:
	_cursor.item_id = Blocks.DIRT
	_cursor.count = 5
	_drag.press(MOUSE_BUTTON_RIGHT, 0)
	assert_eq(_slots[0].count, 1)
	_drag.motion(1)
	_drag.motion(2)
	assert_eq([_slots[0].count, _slots[1].count, _slots[2].count], [1, 1, 1])
	assert_eq(_cursor.count, 2)


func test_sweep_skips_excluded_and_foreign_slots() -> void:
	_cursor.item_id = Blocks.DIRT
	_cursor.count = 64
	_slots[4] = ItemStack.new(Blocks.STONE, 1)
	_drag.press(MOUSE_BUTTON_LEFT, 0)
	_drag.motion(8)  # excluded
	_drag.motion(4)  # different item
	assert_eq(_slots[0].count, 64, "nothing else was eligible")
	assert_true(_slots[8].is_empty())
	assert_eq(_slots[4].count, 1)


func test_move_drag_drops_on_the_release_slot() -> void:
	_slots[0] = ItemStack.new(Blocks.DIRT, 10)
	_drag.press(MOUSE_BUTTON_LEFT, 0)
	_drag.release(MOUSE_BUTTON_LEFT, 5)
	assert_eq(_slots[5].count, 10, "released over another slot → placed there")
	assert_true(_cursor.is_empty())


func test_release_off_any_slot_keeps_the_cursor() -> void:
	_slots[0] = ItemStack.new(Blocks.DIRT, 10)
	_drag.press(MOUSE_BUTTON_LEFT, 0)
	_drag.release(MOUSE_BUTTON_LEFT, NONE)
	assert_eq(_cursor.count, 10, "still holding it, as vanilla")
