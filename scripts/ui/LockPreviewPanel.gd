extends Control
class_name LockPreviewPanel

signal confirmed
signal canceled

@onready var _dimmer: ColorRect = $"Dimmer"
@onready var _panel: Panel = $"Dimmer/Center/Panel"
@onready var _title: Label = $"Dimmer/Center/Panel/Margin/VBox/Title"
@onready var _predict: RichTextLabel = $"Dimmer/Center/Panel/Margin/VBox/PredictText"
@onready var _btn_confirm: Button = $"Dimmer/Center/Panel/Margin/VBox/Buttons/BtnConfirm"
@onready var _btn_cancel: Button = $"Dimmer/Center/Panel/Margin/VBox/Buttons/BtnCancel"

var _prediction: Dictionary = {}
var _allocation: Dictionary = {}
var _round_label: String = ""

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


func setup(allocation: Dictionary, prediction: Dictionary, round_label: String = "") -> void:
	_allocation = allocation
	_prediction = prediction
	_round_label = round_label
	var parts: Array = ["magnet_coil", "first_wall", "breeder_blanket", "plasma_control"]
	var lines: String = ""
	for p in parts:
		var amt: int = int(allocation.get(p, 0))
		if amt > 0:
			var label: String = PART_LABELS.get(p, p)
			lines += "[color=%s]%s[/color]: 楼%d\n" % [PART_COLORS[p].to_html(), label, amt]
	if lines == "":
		lines = "[color=#8893a5]本轮未分配任何经费。\n请调整分配后再提交。\n"
	else:
		lines = "[b]费用分配[/b]\n" + lines
	lines += "\n[b]预测结果[/b]\n"
	var pq: float = float(prediction.get("q", 1.0))
	var ps: float = float(prediction.get("stability", 1.0)) * 100.0
	var pf: float = float(prediction.get("fuel", 1.0)) * 100.0
	lines += "  Q值: %s\n" % _fmt_q(pq)
	lines += "  稳定度: %d%%\n" % roundi(ps)
	lines += "  燃料自持: %d%%\n" % roundi(pf)
	_title.text = "确认提交"
	_predict.text = lines


func _ready() -> void:
	visible = false
	_btn_confirm.pressed.connect(_on_confirm)
	_btn_cancel.pressed.connect(_on_cancel)
	_dimmer.gui_input.connect(_on_dimmer_input)
	visible = true
	move_to_front()
	_panel.modulate.a = 0.0
	_panel.position.y = 30.0
	var tween := create_tween()
	tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(_panel, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_cancel()


func _on_confirm() -> void:
	AudioManager.play("ui_click")
	_hide()
	confirmed.emit()


func _on_cancel() -> void:
	AudioManager.play("ui_click")
	_hide()
	canceled.emit()


func _hide() -> void:
	var tween := create_tween()
	tween.tween_property(_panel, "modulate:a", 0.0, 0.15)
	tween.tween_callback(queue_free)


func _fmt_q(q: float) -> String:
	var color := "#4ed36a" if q >= 1.0 else "#e64040"
	return "[color=%s]%.2f[/color]" % [color, q]
