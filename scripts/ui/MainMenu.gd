extends Control
## MainMenu —— 主菜单 + 启动自检 + 难度选择 + 续档入口
##
## 职责：
## 1. 启动自检面板：显示配置加载结果与已解锁成就统计。
## 2. 新游戏 / 继续游戏（存档存在时）/ 难度切换。
## 3. 用 rounds.json 的 gauge 配置实例化一排 Gauge 并注入假数据，验证数据流。

const GAUGE_SCENE := preload("res://scenes/components/Gauge.tscn")
const CONTROL_ROOM := "res://scenes/control_room/ControlRoom.tscn"
const DIFFICULTY_CYCLE := ["novice", "chief", "custom"]

@onready var _status: RichTextLabel = $Center/Panel/Margin/VBox/StatusLabel
@onready var _gauge_row: HBoxContainer = $Center/Panel/Margin/VBox/GaugeRow
@onready var _btn_continue: Button = $Center/Panel/Margin/VBox/Buttons/BtnContinue
@onready var _btn_start: Button = $Center/Panel/Margin/VBox/Buttons/BtnStart
@onready var _btn_difficulty: Button = $Center/Panel/Margin/VBox/Buttons/BtnDifficulty
@onready var _btn_refresh: Button = $Center/Panel/Margin/VBox/Buttons/BtnRefresh

var _gauges: Array[Gauge] = []


func _ready() -> void:
	_btn_start.pressed.connect(_on_start_pressed)
	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_difficulty.pressed.connect(_on_cycle_difficulty)
	_btn_refresh.pressed.connect(_run_self_check)
	_run_self_check()
	AudioManager.play_bgm("menu")


## 启动自检：检查 DataManager 状态、构建仪表演示、刷新按钮状态
func _run_self_check() -> void:
	_show_status()
	_build_gauges()
	_inject_fake_data()
	_update_buttons()


## 显示数据加载结果与成就统计
func _show_status() -> void:
	if DataManager.is_ready:
		var unlocked: int = SaveManager.get_unlocked().size()
		_status.text = "[color=#4ed36a]● 配置自检通过[/color]  已加载 %d 份配置，数据流正常。\n已解锁结局成就：[color=#f5c63f]%d / 12[/color]" % [
			DataManager.DATA_FILES.size(), unlocked
		]
		_btn_start.disabled = false
	else:
		var lines := "[color=#e64040]● 配置自检失败[/color]  共 %d 个问题：\n" % \
			DataManager.validation_errors.size()
		for e in DataManager.validation_errors:
			lines += "  · %s\n" % e
		_status.text = lines
		_btn_start.disabled = true


## 刷新续档与难度按钮
func _update_buttons() -> void:
	_btn_continue.disabled = not SaveManager.has_save()
	var diff: String = SaveManager.settings.get("difficulty", "novice")
	var label: String = DataManager.get_difficulty(diff).get("label", diff)
	_btn_difficulty.text = "难度：%s" % label


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
		gauge.set_reading(base * 0.92)


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

func _on_start_pressed() -> void:
	AudioManager.play("ui_click")
	# 新局：清空旧状态，按当前难度初始化（current_round 归零 → ControlRoom 走新局分支）
	GameState.reset(SaveManager.settings.get("difficulty", "novice"))
	get_tree().change_scene_to_file(CONTROL_ROOM)


func _on_continue_pressed() -> void:
	if not SaveManager.has_save():
		return
	AudioManager.play("ui_click")
	SaveManager.load_game()
	get_tree().change_scene_to_file(CONTROL_ROOM)


func _on_cycle_difficulty() -> void:
	AudioManager.play("ui_click")
	var cur: String = SaveManager.settings.get("difficulty", "novice")
	var idx: int = DIFFICULTY_CYCLE.find(cur)
	var nxt: String = DIFFICULTY_CYCLE[(idx + 1) % DIFFICULTY_CYCLE.size()]
	SaveManager.settings["difficulty"] = nxt
	SaveManager.save_settings()
	_update_buttons()
