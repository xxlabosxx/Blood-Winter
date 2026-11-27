class_name InventorySlotData
extends Resource
## Single mutable container slot holding a reference to a read-only ItemData blueprint and an int quantity.

@export var item: ItemData = null
@export var quantity: int = 0


func is_empty() -> bool:
	return item == null or quantity <= 0


func can_stack_with(other_item: ItemData) -> bool:
	if is_empty() or other_item == null:
		return false
	if item.item_id != other_item.item_id:
		return false
	return quantity < maxi(1, item.max_stack)


func clear() -> void:
	item = null
	quantity = 0


func to_save_dict() -> Dictionary:
	if is_empty():
		return {}
	return {
		"item_id": String(item.item_id),
		"resource_path": item.resource_path,
		"quantity": quantity,
	}
