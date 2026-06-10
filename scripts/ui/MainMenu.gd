extends Control
## MainMenu —— 主菜单 + 启动自检 + 数据流验证
##
## 职责：
## 1. 显示 DataManager 启动加载结果（自检面板），配置异常时直观暴露问题。
## 2. 用 rounds.json 的 gauge 配置实例化一排 Gauge，并注入假数据，验证数据流通。
## 3. 提供开始/难度入口（后续接 ControlRoom 主场景）。

const GAUGE_SCENE := preload("res://scenes/components/Gauge.tscn")

@onready var _status: RichTextLabel = $Center/Panel/Margin/VBox/StatusLabel
@onready var _gauge_row: HBoxContainer = $Center/Panel/Margin/VBox/GaugeRow
@onready var _btn_start: Button = $Center/Panel/Margin/VBox/Buttons/BtnStart
@onready var _btn_refresh: Button = $Center/Panel/Margin/VBox/Buttons/BtnRefresh

var _gauges: Array[Gauge] = []


func _ready() -> void:
	_btn_start.pressed.connect(_on_start_pressed)
	_btn_refresh.pressed.connect(_run_self_check)
	_run_self_check()


## 启动自检：检查 DataManager 状态并构建仪表演示
func _run_self_check() -> void:
	_show_status()
	_build_gauges()
	_inject_fake_data()


## 显示数据加载结果
func _show_status() -> void:
	if DataManager.is_ready:
		_status.text = "[color=#4ed36a]● 配置自检通过[/color]  已加载 %d 份配置，数据流正常。" % \
			DataManager.DATA_FILES.size()
		_btn_start.disabled = false
	else:
		var lines := "[color=#e64040]● 配置自检失败[/color]  共 %d 个问题：\n" % \
			DataManager.validation_errors.size()
		for e in DataManager.validation_errors:
			lines += "  · %s\n" % e
		_status.text = lines
		_btn_start.disabled = true


## 用 rounds.json 的 gauge 定义构建一排仪表
func _build_gauges() -> void:
	for g in _gauges:
		g.queue_free()
	_gauges.clear()

	var rounds_cfg: Variant = DataManager.get_config("rounds")
	if not (rounds_cfg is Dictionary):
		return
	var gauges_def: Dictionary = (rounds_cfg as Dictionary).get("gauges", {})
	for id in gauges_def:
		var gauge: Gauge = GAUGE_SCENE.instantiate()
		_gauge_row.add_child(gauge)
		gauge.setup(id, gauges_def[id])
		_gauges.append(gauge)


## 注入一组偏离正常区间的假数据，验证着色与读数更新
func _inject_fake_data() -> void:
	var rounds_cfg: Variant = DataManager.get_config("rounds")
	if not (rounds_cfg is Dictionary):
		return
	var gauges_def: Dictionary = (rounds_cfg as Dictionary).get("gauges", {})
	for gauge in _gauges:
		var cfg: Dictionary = gauges_def.get(gauge.gauge_id, {})
		var base: float = float(cfg.get("base", 1.0))
		# 制造 -8% 偏移演示告警着色
		gauge.set_reading(base * 0.92)


func _on_start_pressed() -> void:
	AudioManager.play("ui_click")
	# ControlRoom 主场景将在 D1-D2 落地，此处先占位提示
	_status.text += "\n[color=#2bd6ff]→ 即将进入中控台（ControlRoom 开发中）[/color]"
