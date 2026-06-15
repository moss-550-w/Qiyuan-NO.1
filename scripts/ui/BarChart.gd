extends Control
class_name BarChart
## BarChart — 经费分配比例水平条形图（T3.3 图1）
##
## 展示四个部位累计投入的经费比例，用水平条表示。
## 支持颜色区分和数值标注。

const PART_LABELS := {
	"magnet_coil": "磁体线圈",
	"first_wall": "第一壁",
	"breeder_blanket": "氚增殖包层",
	"plasma_control": "等离子体控制",
}

const PART_COLORS := {
	"magnet_coil": Color(0.30, 0.78, 1.00),
	"first_wall": Color(1.00, 0.55, 0.30),
	"breeder_blanket": Color(0.45, 0.90, 0.50),
	"plasma_control": Color(0.60, 0.55, 1.00),
}

const PART_ORDER := ["magnet_coil", "first_wall", "breeder_blanket", "plasma_control"]

var _allocation: Dictionary = {}
var _total: int = 0


func setup(allocation: Dictionary) -> void:
	_allocation = allocation
	_total = 0
	for p in PART_ORDER:
		_total += int(allocation.get(p, 0))
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var fs := 14
	var w: float = size.x
	var h: float = size.y

	# 背景
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.09, 0.16, 0.6), true)

	if _total == 0:
		draw_string(font, Vector2(20.0, h * 0.5), "本轮未分配经费",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.55, 0.62, 0.72))
		return

	var bar_area_top: float = 30.0
	var bar_area_height: float = h - bar_area_top - 20.0
	var bar_count: int = PART_ORDER.size()
	var bar_height: float = minf(28.0, (bar_area_height - (bar_count - 1) * 8.0) / bar_count)
	var spacing: float = 8.0
	var label_width: float = 80.0
	var bar_max_width: float = w - label_width - 70.0

	for i in range(bar_count):
		var part: String = PART_ORDER[i]
		var amount: int = int(_allocation.get(part, 0))
		var ratio: float = float(amount) / float(_total) if _total > 0 else 0.0
		var color: Color = PART_COLORS.get(part, Color.GRAY)
		var label: String = PART_LABELS.get(part, part)

		var y_pos: float = bar_area_top + i * (bar_height + spacing)

		# 标签
		draw_string(font, Vector2(10.0, y_pos + bar_height - 4.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.82, 0.88, 0.94))

		# 条背景
		var bg_rect := Rect2(label_width, y_pos, bar_max_width, bar_height)
		draw_rect(bg_rect, Color(0.20, 0.25, 0.35, 0.5), true)

		# 条填充
		var fill_width: float = bar_max_width * ratio
		if ratio > 0.0:
			var fill_rect := Rect2(label_width, y_pos, fill_width, bar_height)
			draw_rect(fill_rect, color, true)

		# 数值标注
		if amount > 0:
			var num_text: String = "%d (%d%%)" % [amount, roundi(ratio * 100.0)]
			var label_pos: float = label_width + fill_width + 8.0
			draw_string(font, Vector2(label_pos, y_pos + bar_height - 4.0), num_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.72, 0.80))