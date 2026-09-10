class_name SlotDrag
extends RefCounted

# Press-time slot interaction shared by the inventory, crafting-table and
# chest screens.
#
# Vanilla ex.java:91-113 (GuiContainer.mouseClicked) does every pickup,
# place, merge, swap and half-split ON PRESS; its release handler
# (ex.java:184-188) is empty. The three screens used to defer four of
# the five click cases to mouse-up, so the slot you clicked did not
# change until you let go — "drag dropping items don't display
# immediately, only shows after release" (issue #7).
#
# Two QoL layers Alpha never had are kept, but both now repaint as they
# happen rather than on release:
#   * hold-and-sweep distribution — press with a stack and drag across
#     slots: LMB splits the starting stack evenly across every slot
#     entered, RMB drops one per slot. Each newly entered slot re-runs
#     the split from the recorded base counts, so what is on screen is
#     always the current outcome (modern MC's quick-craft preview).
#   * move-drag — pick up on press, release over another slot to drop.
#
# The screen supplies the slot model through callables; this class owns
# no UI.

# Sentinel the screen's slot lookup returns for "not over a slot".
var none_id: int = -1
# (slot) -> ItemStack, or null when the id is not a real slot.
var stack_at: Callable
# (slot) -> bool. Slots a sweep may never write into (craft result,
# armor, furnace output).
var sweep_excluded: Callable
# (slot) -> void. The screen's press-time handlers.
var click_left: Callable
var click_right: Callable
# () -> void. Repaint + recompute after the sweep rewrote slots.
var changed: Callable
var cursor: ItemStack

# A sweep is armed: the press placed items and the pointer may still
# enter more slots.
var active: bool = false
var _button: int = -1
var _press_slot: int = -1
var _slots: Array[int] = []
var _base_counts: Array[int] = []
var _start_count: int = 0
var _start_id: int = 0


# Slots the current sweep has written into, in entry order.
func swept() -> Array[int]:
	return _slots


func press(button: int, slot: int) -> void:
	if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
		return
	if slot == none_id:
		return
	_button = button
	_press_slot = slot
	active = false
	_slots.clear()
	_base_counts.clear()
	var target: ItemStack = stack_at.call(slot)
	# A sweep can only start from a PLACE: cursor holding something and
	# the slot able to take more of it. Record the pre-click state so
	# later slots can redistribute from the same starting stack.
	var arm: bool = (
		target != null
		and not cursor.is_empty()
		and not bool(sweep_excluded.call(slot))
		and (
			target.is_empty()
			or (target.item_id == cursor.item_id and target.count < ItemStack.MAX_SIZE)
		)
	)
	if arm:
		_start_count = cursor.count
		_start_id = cursor.item_id
		_slots.append(slot)
		_base_counts.append(target.count)
	if button == MOUSE_BUTTON_LEFT:
		click_left.call(slot)
	else:
		click_right.call(slot)
	active = arm


func motion(hovered: int) -> void:
	if not active or hovered == none_id or _slots.has(hovered):
		return
	if bool(sweep_excluded.call(hovered)):
		return
	var target: ItemStack = stack_at.call(hovered)
	if target == null:
		return
	if not target.is_empty():
		if target.item_id != _start_id or target.count >= ItemStack.MAX_SIZE:
			return
	_slots.append(hovered)
	_base_counts.append(target.count)
	_redistribute()


func release(button: int, slot: int) -> void:
	if button != _button:
		return
	# Move-drag: the press picked something up (or was a plain click that
	# left the cursor holding a stack) and the pointer let go over a
	# DIFFERENT slot — drop it there. A sweep never does this; its
	# writes already happened as the pointer moved.
	if not active and slot != none_id and slot != _press_slot and not cursor.is_empty():
		if button == MOUSE_BUTTON_LEFT:
			click_left.call(slot)
		else:
			click_right.call(slot)
	active = false
	_button = -1
	_press_slot = none_id
	_slots.clear()
	_base_counts.clear()


# Reset every swept slot to what it held before the sweep touched it,
# then deal the starting stack out again across all of them.
func _redistribute() -> void:
	var n: int = _slots.size()
	var per_slot: int = _start_count / n if _button == MOUSE_BUTTON_LEFT else 1
	if per_slot <= 0:
		return
	var distributed: int = 0
	for i: int in range(n):
		var target: ItemStack = stack_at.call(_slots[i])
		if target == null:
			continue
		target.count = _base_counts[i]
		if target.count == 0:
			target.item_id = _start_id
		var added: int = mini(per_slot, ItemStack.MAX_SIZE - target.count)
		target.count += added
		distributed += added
		if target.count == 0:
			target.clear()
	cursor.item_id = _start_id
	cursor.count = _start_count - distributed
	if cursor.count <= 0:
		cursor.clear()
	changed.call()
