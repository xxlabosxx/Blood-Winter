class_name ItemData
extends Resource
## Read-only item blueprint Resource for Blood Winter's modular Inventory & Hotbar system.
## Never mutate shared ItemData instances at runtime; store stack quantities in InventorySlotData.

enum ItemCategory {
	NONE,
	WEAPON,
	CONSUMABLE,
	RELIC,
	TOOL,
	MATERIAL,
}

@export var item_id: StringName = &""
@export var display_name: String = "Unnamed Item"
@export var short_tag: String = "ITEM"
@export var category: ItemCategory = ItemCategory.NONE
@export_multiline var description: String = ""

@export_group("Stacking & Weight")
@export var max_stack: int = 1
@export var weight: float = 1.0

@export_group("Presentation")
@export var accent_color: Color = Color(0.86, 0.14, 0.22, 1.0)
@export var icon: Texture2D = null

@export_group("Equipment Payload")
## Optional WeaponData payload when category == ItemCategory.WEAPON.
@export var weapon_data: WeaponData = null
