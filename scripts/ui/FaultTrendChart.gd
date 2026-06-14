extends Control
class_name FaultTrendChart
## FaultTrendChart — 故障强度变化折线图（T3.3 图2）
##
## 展示每轮各根因的修复进度（0~1），以及未修复时的残余强度。
## 数据来源：GameState.run_log 中每轮的 gauge 快照。

const CAUSE_COLORS := {
	"magnet_psu_aging": Color(0.30, 0.78, 1.00),
	"wall_microcrack": Color(1.00, 0.55, 0.30),
	"tritium_pump_decay": Color(0.45, 0.90, 0.50),
}

const CAUSE_LABELS := {
	"magnet_psu_aging": "磁体电源老化",
	"wall_microcrack": "第一壁微裂纹",
	"tritium_pump_decay": "氚提取泵衰减",
}

var _run_log: Array = []
var _root_causes: Array = []


func setup(run_log: Array) -> void:
	_run_log = run_log
	_root_causes = GameState.ROOT_CAUSES.duplicate()
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var fs := 14
	var w: float = size.x
	var h: float = size.y

	# 背景
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.09, 0.16, 0.6), true)

	if _run_log.is_empty():
		draw_string(font, Vector2(20.0, h * 0.5), "暂无运行日志",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.55, 0.62, 0.72))
		return

	var plot_l: float = 90.0
	var plot_r: float = w - 20.0
	var plot_t: float = 40.0
	var plot_b: float = h - 30.0
	var plot_w: float = maxf(plot_r - plot_l, 1.0)
	var plot_h: float = maxf(plot_b - plot_t, 1.0)

	var round_count: int = _run_log.size()
	var x_at := func(idx: int, n: int) -> float:
		if n <= 1:
			return plot_l + plot_w * 0.5
		return plot_l + plot_w * float(idx) / float(n - 1)

	# 坐标轴标签
	draw_string(font, Vector2(plot_l, plot_t - 8.0), "修复进度",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.62, 0.72))
	draw_string(font, Vector2(plot_l, plot_b + 18.0), "轮次",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.62, 0.72))

	# Y 轴刻度 0.0 / 0.5 / 1.0
	for val in [0.0, 0.5, 1.0]:
		var y: float = plot_b - plot_h * val
		draw_line(Vector2(plot_l, y), Vector2(plot_r, y), Color(1, 1, 1, 0.06), 1.0)
		var y_label := "%.1f" % val
		draw_string(font, Vector2(2.0, y + 4.0), y_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.62, 0.72))

	# X 轴标签
	for i in range(round_count):
		var x: float = x_at.call(i, round_count)
		var rn: int = int(_run_log[i].get("round", i + 1))
		draw_string(font, Vector2(x - 12.0, plot_b + 14.0), "R%d" % rn,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.62, 0.72))

	# 绘制每个根因的修复进度
	for cid in _root_causes:
		var color: Color = CAUSE_COLORS.get(cid, Color.GRAY)
		var label: String = CAUSE_LABELS.get(cid, cid)
		var pts: PackedVector2Array = PackedVector2Array()

		for i in range(round_count):
			var entry: Dictionary = _run_log[i]
			var identified: Array = entry.get("identified", [])
			var progress: float = 1.0 if identified.has(cid) else 0.0
			var x: float = x_at.call(i, round_count)
			var y: float = plot_b - plot_h * progress
			pts.append(Vector2(x, y))

		if pts.size() >= 2:
			draw_polyline(pts, color, 2.0, true)
		for p in pts:
			draw_circle(p, 4.0, color)

		# 图例
		var legend_x: float = plot_l + plot_w * 0.5 + 10.0
		var legend_y: float = plot_t - 20.0
		draw_rect(Rect2(legend_x, legend_y, 10.0, 10.0), color, true)
		draw_string(font, Vector2(legend_x + 14.0, legend_y + 9.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.82, 0.88, 0.94))