class_name InventoryComponent
extends Node
## Modular, signal-driven Inventory & 1-9 Hotbar component for Blood Winter.
## Follows Resource-first architecture:
## - Items are read-only ItemData blueprints; quantities are int stacks in InventorySlotData.
## - Mutations emit batched `inventory_updated` / `selected_slot_changed` signals for reactive UI.
## - Designed to scale seamlessly into full backpack, loot drops, crafting, and save/load.

signal inventory_updated()
signal selected_slot_changed(slot_index: int, slot: InventorySlotData)

@export var hotbar_size: int = 9
@export var backpack_size: int = 18

var hotbar_slots: Array[InventorySlotData] = []
var backpack_slots: Array[InventorySlotData] = []
var selected_hotbar_index: int = 0


func _ready() -> void:
	_ensure_initialized()


func _ensure_initialized() -> void:
	if hotbar_slots.size() != hotbar_size:
		hotbar_slots.clear()
		for _i: int in range(hotbar_size):
			hotbar_slots.append(InventorySlotData.new())
	if backpack_slots.size() != backpack_size:
		backpack_slots.clear()
		for _i: int in range(backpack_size):
			backpack_slots.append(InventorySlotData.new())
	selected_hotbar_index = clampi(selected_hotbar_index, 0, maxi(0, hotbar_size - 1))


func get_hotbar_slot(index: int) -> InventorySlotData:
	_ensure_initialized()
	if index < 0 or index >= hotbar_slots.size():
		return null
	return hotbar_slots[index]


func get_selected_slot() -> InventorySlotData:
	return get_hotbar_slot(selected_hotbar_index)


func get_selected_weapon() -> WeaponData:
	var slot: InventorySlotData = get_selected_slot()
	if slot == null or slot.is_empty():
		return null
	if slot.item.category == ItemData.ItemCategory.WEAPON and slot.item.weapon_data != null:
		return slot.item.weapon_data
	return null


func has_weapon_equipped() -> bool:
	return get_selected_weapon() != null


func select_hotbar_slot(index: int) -> void:
	_ensure_initialized()
	var clamped: int = clampi(index, 0, hotbar_slots.size() - 1)
	if clamped == selected_hotbar_index:
		return
	selected_hotbar_index = clamped
	selected_slot_changed.emit(selected_hotbar_index, hotbar_slots[selected_hotbar_index])
	inventory_updated.emit()


func cycle_hotbar(step: int) -> void:
	_ensure_initialized()
	if hotbar_slots.is_empty():
		return
	var next_idx: int = posmod(selected_hotbar_index + step, hotbar_slots.size())
	select_hotbar_slot(next_idx)


func set_hotbar_slot(index: int, item: ItemData, quantity: int = 1) -> void:
	_ensure_initialized()
	if index < 0 or index >= hotbar_slots.size():
		return
	var slot: InventorySlotData = hotbar_slots[index]
	if item == null or quantity <= 0:
		slot.clear()
	else:
		slot.item = item
		slot.quantity = clampi(quantity, 1, maxi(1, item.max_stack))
	if index == selected_hotbar_index:
		selected_slot_changed.emit(selected_hotbar_index, slot)
	inventory_updated.emit()


func clear_hotbar_slot(index: int) -> void:
	set_hotbar_slot(index, null, 0)


## Two-pass stack-safe item insertion (fills partial stacks first, then empty slots).
## Returns the overflow count that could not fit.
func add_item(item: ItemData, amount: int = 1) -> int:
	_ensure_initialized()
	if item == null or amount <= 0:
		return amount

	var remaining: int = amount
	var max_stk: int = maxi(1, item.max_stack)
	var all_slots: Array[InventorySlotData] = []
	all_slots.append_array(hotbar_slots)
	all_slots.append_array(backpack_slots)

	# Pass 1: stack onto existing matching slots
	if max_stk > 1:
		for slot: InventorySlotData in all_slots:
			if remaining <= 0:
				break
			if slot.can_stack_with(item):
				var space: int = max_stk - slot.quantity
				var to_add: int = mini(space, remaining)
				slot.quantity += to_add
				remaining -= to_add

	# Pass 2: place into empty slots (hotbar first, then backpack)
	for slot: InventorySlotData in all_slots:
		if remaining <= 0:
			break
		if slot.is_empty():
			var to_add: int = mini(max_stk, remaining)
			slot.item = item
			slot.quantity = to_add
			remaining -= to_add

	if remaining != amount:
		selected_slot_changed.emit(selected_hotbar_index, hotbar_slots[selected_hotbar_index])
		inventory_updated.emit()
	return remaining


func to_save_dict() -> Dictionary:
	_ensure_initialized()
	var hb: Array[Dictionary] = []
	for slot: InventorySlotData in hotbar_slots:
		hb.append(slot.to_save_dict())
	var bp: Array[Dictionary] = []
	for slot: InventorySlotData in backpack_slots:
		bp.append(slot.to_save_dict())
	return {
		"selected_hotbar_index": selected_hotbar_index,
		"hotbar": hb,
		"backpack": bp,
	}
