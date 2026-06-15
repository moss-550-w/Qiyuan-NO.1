extends Control
class_name ReviewPanel
## ReviewPanel — 复盘三图面板（T3.3）
##
## 职责：在游戏结束后展示三张对比图：
##   1. 经费分配比例图（水平条形图）
##   2. 故障强度变化图（折线图，按轮次）
##   3. 仪表趋势对比图（复用 TrendChart）

@onready var _btn_close: Button = /Panel/Margin/VBox/Header/BtnClose
@onready var _vbox: VBoxContainer = /Panel/Margin/VBox
@onready var _chart_area: VBoxContainer = /Panel/Margin/VBox/Charts

# 图表组件
var _bar_chart: BarChart = null
var _fault_chart: FaultTrendChart = null
var _gauge_chart: TrendChart = null


func _ready() -> void:
	visible = false
	_btn_close.pressed.connect(_on_close)


func open() -> void:
	visible = true
	move_to_front()
	_render()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _render() -> void:
	# 清理旧图表
	for c in _chart_area.get_children():
		c.queue_free()
	_chart_area.get_children() # ensure cleared

	# 1. 经费分配比例图
	_bar_chart = BarChart.new()
	_bar_chart.setup(GameState.cumulative_allocation)
	_chart_area.add_child(_bar_chart)

	# 2. 故障强度变化图
	_fault_chart = FaultTrendChart.new()
	_fault_chart.setup(GameState.run_log)
	_chart_area.add_child(_fault_chart)

	# 3. 仪表趋势对比图（复用已有 TrendChart）
	_gauge_chart = TrendChart.new()
	_gauge_chart.custom_minimum_size = Vector2(0, 220)
	_gauge_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gauge_chart.set_series(_build_gauge_series())
	_chart_area.add_child(_gauge_chart)


func _build_gauge_series() -> Array:
	var series: Array = []
	var track_ids := ["toroidal_field", "wall_temp", "tritium_ratio"]
	var gauge_labels := {
		"toroidal_field": "环向场",
		"wall_temp": "壁温",
		"tritium_ratio": "氚率",
	}
	var gauge_colors := {
		"toroidal_field": Color(0.30, 0.78, 1.00),
		"wall_temp": Color(1.00, 0.55, 0.30),
		"tritium_ratio": Color(0.45, 0.90, 0.50),
	}
	for gid in track_ids:
		var pts: Array = []
		var rounds: Array = []
		for entry in GameState.run_log:
			var gauges: Dictionary = (entry as Dictionary).get("gauges", {})
			if gauges.has(gid):
				pts.append(float(gauges[gid]))
				rounds.append(int((entry as Dictionary).get("round", 0)))
		if not pts.is_empty():
			series.append({
				"name": gauge_labels.get(gid, gid),
				"color": gauge_colors.get(gid, Color.WHITE),
				"points": pts,
				"rounds": rounds,
				"unit": "",
				"fmt": "%.2f",
			})
	return series


func _on_close() -> void:
	AudioManager.play("ui_click")
	close()