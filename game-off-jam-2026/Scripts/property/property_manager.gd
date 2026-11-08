extends Node
class_name PropertyManager

enum Property {
	NORMAL,
	LIGHTWEIGHT,
	HEAVY,
	SLIPPERY,
	BOUNCY,
	STICKY
}

var current_property: Property = Property.NORMAL

signal property_changed(new_property: Property)


func set_property(new_property: Property) -> void:

	if new_property < Property.NORMAL or new_property > Property.STICKY:
		push_warning("Invalid property!")
		return

	if current_property == new_property:
		return

	current_property = new_property

	print("Current property: ", Property.keys()[current_property])

	property_changed.emit(current_property)


func get_current_property() -> Property:
	return current_property


func reset_property() -> void:
	set_property(Property.NORMAL)
