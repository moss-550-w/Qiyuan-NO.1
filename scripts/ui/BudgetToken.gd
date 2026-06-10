extends Panel
class_name BudgetToken
## BudgetToken —— 可拖拽经费代币
##
## 代表一份固定面额的经费。玩家从经费池把它拖到 DropZone 完成分配。
## 拖放数据格式：{ "type": "budget_token", "amount": <int> }
## DropZone 通过该 type 识别合法投放。

const DRAG_TYPE := "budget_token"

@export var face_value: int = 10   # 单枚面额（单位）

@onready var _label: Label = $Label


func _ready() -> void:
	_refresh()


func set_face_value(v: int) -> void:
	face_value = v
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	_label.text = "¥%d" % face_value


## Godot 拖放：返回非 null 即开始拖动，并设置跟随鼠标的预览
func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := _make_preview()
	set_drag_preview(preview)
	AudioManager.play("ui_click")
	return { "type": DRAG_TYPE, "amount": face_value }


## 构造拖拽预览（半透明副本，居中跟随鼠标）
func _make_preview() -> Control:
	var holder := Control.new()
	var ghost := duplicate() as Panel
	ghost.modulate = Color(1, 1, 1, 0.8)
	ghost.position = -size * 0.5
	holder.add_child(ghost)
	return holder
