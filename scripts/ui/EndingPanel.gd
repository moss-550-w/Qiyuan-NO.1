extends Control
## EndingPanel —— 结局面板
##
## 从 GameState 读取最终局势（Q值、识破根因、各轮日志），经 EndingResolver
## 判定 12 结局之一，展示标题、Q区间、根因识破清单、科普总结、各轮表现。
## 提供"再来一局"与"返回菜单"。

@onready var _title: Label = $Center/Panel/Margin/VBox/EndingTitle
@onready var _band: Label = $Center/Panel/Margin/VBox/BandLabel
@onready var _causes: RichTextLabel = $Center/Panel/Margin/VBox/CausesLabel
@onready var _summary: RichTextLabel = $Center/Panel/Margin/VBox/SummaryLabel
@onready var _log: RichTextLabel = $Center/Panel/Margin/VBox/LogLabel
@onready var _btn_replay: Button = $Center/Panel/Margin/VBox/Buttons/BtnReplay
@onready var _btn_menu: Button = $Center/Panel/Margin/VBox/Buttons/BtnMenu


func _ready() -> void:
	var q: float = GameState.q_value
	var identified: int = GameState.identified_causes.size()
	var result: Dictionary = EndingResolver.resolve(q, identified)

	_title.text = result["title"]
	_band.text = "%s　|　识破根因 %d / %d" % [
		result["q_band_label"], identified, GameState.ROOT_CAUSES.size()
	]
	_causes.text = _build_causes_text()
	_summary.text = "[b]科普总结[/b]\n" + str(result["summary"])
	_log.text = _build_log_text()

	_btn_replay.pressed.connect(_on_replay)
	_btn_menu.pressed.connect(_on_menu)
	AudioManager.play("ending")
	AudioManager.play_bgm("ending")


## 三根因识破清单（✓ 已识破 / ✗ 未识破）
func _build_causes_text() -> String:
	var lines: String = "[b]根本原因识别[/b]\n"
	for cid in GameState.ROOT_CAUSES:
		var done: bool = GameState.identified_causes.has(cid)
		var mark: String = "[color=#4ed36a]✓[/color]" if done else "[color=#e64040]✗[/color]"
		lines += "%s %s\n" % [mark, FaultTree.cause_name(cid)]
	return lines


## 各轮表现简表
func _build_log_text() -> String:
	if GameState.run_log.is_empty():
		return ""
	var text: String = "[b]各轮表现[/b]\n"
	for entry in GameState.run_log:
		var e: Dictionary = entry
		var ids: Array = e.get("identified", [])
		var got: String = "识破 %d 项" % ids.size() if not ids.is_empty() else "无新识破"
		text += "第 %d 轮：Q=%.2f 稳定=%d%% 燃料=%d%%　%s\n" % [
			int(e.get("round", 0)),
			float(e.get("q", 0.0)),
			roundi(float(e.get("stability", 0.0)) * 100.0),
			roundi(float(e.get("fuel", 0.0)) * 100.0),
			got,
		]
	return text


func _on_replay() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/control_room/ControlRoom.tscn")


func _on_menu() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
