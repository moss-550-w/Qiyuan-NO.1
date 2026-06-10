extends Control
class_name LogPanel
## LogPanel —— 历史运行日志（总工模式覆盖面板）
##
## 展示 GameState.run_log 各已完成轮次的仪表读数与指标趋势，供总工模式下
## 手动查阅、判断异常走势。纯展示，数据来自每轮提交时记录的快照。

@onready var _dimmer: ColorRect = $Dimmer
@onready var _btn_close: Button = $Center/Window/Margin/VBox/Header/BtnClose
@onready var _content: RichTextLabel = $Center/Window/Margin/VBox/Content

## 趋势中关注的仪表：id → 显示名/单位
const TRACK_GAUGES := [
	{"id": "toroidal_field", "label": "环向场", "unit": "T", "fmt": "%.2f"},
	{"id": "wall_temp", "label": "壁温", "unit": "℃", "fmt": "%.0f"},
	{"id": "tritium_ratio", "label": "氚率", "unit": "", "fmt": "%.2f"},
]


func _ready() -> void:
	visible = false
	_btn_close.pressed.connect(close)
	_dimmer.gui_input.connect(_on_dimmer_input)


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


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _render() -> void:
	var text: String = "[b]历史运行日志[/b]　[color=#8893a5]（各轮提交时的读数快照，关注异常走势）[/color]\n\n"
	if GameState.run_log.is_empty():
		_content.text = text + "[color=#8893a5]暂无已完成轮次。提交本轮后将在此记录。[/color]"
		return

	for entry in GameState.run_log:
		var e: Dictionary = entry
		var r: int = int(e.get("round", 0))
		text += "[color=#2bd6ff][b]第 %d 轮[/b][/color]　" % r

		# 仪表读数
		var gauges: Dictionary = e.get("gauges", {})
		var parts: Array = []
		for g in TRACK_GAUGES:
			if gauges.has(g["id"]):
				var v: float = float(gauges[g["id"]])
				parts.append("%s %s%s" % [g["label"], g["fmt"] % v, g["unit"]])
		text += "　".join(parts)

		# 指标
		text += "　[color=#8893a5]|[/color]　Q %.2f　稳定 %d%%　燃料 %d%%" % [
			float(e.get("q", 0.0)),
			roundi(float(e.get("stability", 0.0)) * 100.0),
			roundi(float(e.get("fuel", 0.0)) * 100.0),
		]

		# 识破
		var ids: Array = e.get("identified", [])
		if not ids.is_empty():
			var names: Array = []
			for c in ids:
				names.append(FaultTree.cause_name(c))
			text += "　[color=#4ed36a]✓ %s[/color]" % ", ".join(names)
		text += "\n\n"

	_content.text = text
