class_name CooldownCircleIndicator
extends Control
## Compact gothic crimson radial cooldown circle indicator (e.g. for Parry [F] 3.0s cooldown).
## Draws smoothly using _draw() with zero texture dependencies.

@export var key_hint: String = "F"
@export var ready_ring_color: Color = Color(0.85, 0.14, 0.22, 0.92)
@export var cooldown_fill_color: Color = Color(0.92, 0.10, 0.18, 0.85)
@export var bg_color: Color = Color(0.05, 0.05, 0.08, 0.88)

var cooldown_remaining: float = 0.0
var cooldown_total: float = 3.0


func set_cooldown_state(remaining: float, total: float) -> void:
	var new_rem: float = maxf(0.0, remaining)
	var new_tot: float = maxf(0.01, total)
	if not is_equal_approx(new_rem, cooldown_remaining) or not is_equal_approx(new_tot, cooldown_total):
		cooldown_remaining = new_rem
		cooldown_total = new_tot
		queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.44
	var is_on_cd: bool = cooldown_remaining > 0.01

	# Dark gothic circular backdrop
	draw_circle(center, radius, bg_color)

	if is_on_cd:
		# Remaining fraction sweeps clockwise from top (-PI/2)
		var frac: float = clampf(cooldown_remaining / cooldown_total, 0.0, 1.0)
		var start_angle: float = -PI * 0.5
		var end_angle: float = start_angle + TAU * frac
		var segments: int = maxi(8, int(ceil(36.0 * frac)))
		var pts: PackedVector2Array = PackedVector2Array()
		pts.append(center)
		for i: int in range(segments + 1):
			var a: float = lerpf(start_angle, end_angle, float(i) / float(segments))
			pts.append(center + Vector2(cos(a), sin(a)) * (radius - 2.0))
		draw_colored_polygon(pts, cooldown_fill_color)
		# Outer muted border while cooling down
		draw_arc(center, radius, 0.0, TAU, 36, Color(0.55, 0.12, 0.18, 0.85), 2.0, true)
	else:
		# Ready: crisp glowing crimson outer ring
		draw_arc(center, radius, 0.0, TAU, 36, ready_ring_color, 2.4, true)
		draw_arc(center, radius - 3.0, 0.0, TAU, 36, Color(1.0, 0.28, 0.36, 0.35), 1.2, true)

	# Centered text: remaining seconds (e.g. "2.4") while cooling down, or key hint ("F") when ready
	var font: Font = ThemeDB.fallback_font
	if font != null:
		var label_str: String = "%.1f" % cooldown_remaining if is_on_cd else key_hint
		var font_size: int = 11 if is_on_cd else 13
		var text_size: Vector2 = font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos: Vector2 = Vector2(center.x - text_size.x * 0.5, center.y + text_size.y * 0.32)
		draw_string(font, text_pos + Vector2(1, 1), label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.9))
		draw_string(font, text_pos, label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.95, 0.96, 1.0))
