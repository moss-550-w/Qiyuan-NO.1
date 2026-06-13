extends Control
class_name TrendChart
## TrendChart —— 仪表跨轮趋势折线（复盘用，纯绘制）
##
## 输入多条序列，每条按自身极值独立归一化后绘制折线，便于对比"曲线形状"——
## 渐变故障呈平滑斜坡、突发故障呈陡变折点。无业务逻辑。
##
## set_series 数据格式：Array[ {name:String, color:Color, points:Array[float],
##   rounds:Array[int], unit:String, fmt:String} ]

const PAD_L := 16.0
const PAD_R := 16.0
const PAD_T := 40.0   # 顶部留给图例
const PAD_B := 26.0   # 底部留给轮次标签

var _series: Array = []


func set_series(series: Array) -> void:
	_series = series
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var fs := 14
	var w: float = size.x
	var h: float = size.y

	# 背景
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.09, 0.16, 0.6), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.17, 0.55, 0.75, 0.35), false, 1.0)

	if _series.is_empty():
		draw_string(font, Vector2(PAD_L, h * 0.5), "完成 ≥1 轮后在此显示仪表跨轮趋势",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.55, 0.62, 0.72))
		return

	var plot_l := PAD_L
	var plot_r := w - PAD_R
	var plot_t := PAD_T
	var plot_b := h - PAD_B
	var plot_w := maxf(plot_r - plot_l, 1.0)
	var plot_h := maxf(plot_b - plot_t, 1.0)

	# 水平网格（4 等分）
	for i in range(5):
		var gy := plot_t + plot_h * float(i) / 4.0
		draw_line(Vector2(plot_l, gy), Vector2(plot_r, gy), Color(1, 1, 1, 0.06), 1.0)

	# 以最长序列确定 x 轴轮次数
	var max_n := 0
	for s in _series:
		max_n = maxi(max_n, (s["points"] as Array).size())
	if max_n <= 0:
		return

	# x 坐标：单点居中，多点等分
	var x_at := func(idx: int, n: int) -> float:
		if n <= 1:
			return plot_l + plot_w * 0.5
		return plot_l + plot_w * float(idx) / float(n - 1)

	# 轮次标签（取最长序列的 rounds）
	var ref_rounds: Array = []
	for s in _series:
		if (s["points"] as Array).size() == max_n:
			ref_rounds = s.get("rounds", [])
			break
	for idx in range(max_n):
		var rx: float = x_at.call(idx, max_n)
		var rn: int = int(ref_rounds[idx]) if idx < ref_rounds.size() else idx + 1
		draw_string(font, Vector2(rx - 18.0, plot_b + 18.0), "第%d轮" % rn,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.62, 0.72))

	# 逐序列绘制
	var legend_x := plot_l
	for s in _series:
		var pts: Array = s["points"]
		var col: Color = s.get("color", Color.WHITE)
		var n: int = pts.size()
		# 自身极值归一化（平直序列居中）
		var lo: float = pts[0]
		var hi: float = pts[0]
		for v in pts:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		var span: float = maxf(hi - lo, 0.0001)
		var flat: bool = (hi - lo) < 0.0001

		var poly := PackedVector2Array()
		for idx in range(n):
			var nx: float = x_at.call(idx, n)
			var norm: float = 0.5 if flat else (float(pts[idx]) - lo) / span
			var ny: float = plot_b - plot_h * norm
			poly.append(Vector2(nx, ny))

		if n >= 2:
			draw_polyline(poly, col, 2.0, true)
		for p in poly:
			draw_circle(p, 3.0, col)

		# 图例：色块 + 名称 + 末值
		var last_v: float = float(pts[n - 1])
		var fmt: String = s.get("fmt", "%.2f")
		var unit: String = s.get("unit", "")
		var legend: String = "%s  %s%s" % [s.get("name", ""), fmt % last_v, unit]
		draw_rect(Rect2(legend_x, PAD_T - 26.0, 12.0, 12.0), col, true)
		draw_string(font, Vector2(legend_x + 18.0, PAD_T - 15.0), legend,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.82, 0.88, 0.94))
		legend_x += 18.0 + font.get_string_size(legend, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 28.0
