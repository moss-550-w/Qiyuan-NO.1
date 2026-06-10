extends Panel
class_name DropZone
## DropZone —— 装置部位投放区
##
## 接收 BudgetToken 拖放，对应装置四部位之一。
## - 悬停合法代币时发出 hover_preview，供 ControlRoom 显示"投入后预测"。
## - 落定时发出 token_dropped，由 ControlRoom 调用 GameState.allocate。
## - 右键点击发出 withdraw_requested，撤回本部位投入。
## 自身实时显示累计投入与部位健康度（经费效果 0~100%）。

signal hover_preview(part_id: String, amount: int)
signal token_dropped(part_id: String, amount: int)
signal withdraw_requested(part_id: String)

@export var part_id: String = ""
@export var part_label: String = "部位"

@onready var _name: Label = $Margin/VBox/Name
@onready var _invest: Label = $Margin/VBox/Invest
@onready var _bar: ProgressBar = $Margin/VBox/Health

const COLOR_LOW := Color(0.90, 0.25, 0.25)    # 健康度低 红
const COLOR_MID := Color(0.95, 0.80, 0.25)    # 中 黄
const COLOR_HIGH := Color(0.30, 0.85, 0.40)   # 高 绿


func _ready() -> void:
	_name.text = part_label
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	gui_input.connect(_on_gui_input)
	refresh()


## 刷新累计投入与健康度显示（由 ControlRoom 在分配/撤回后调用）
func refresh() -> void:
	var invested: int = int(GameState.round_allocation.get(part_id, 0))
	_invest.text = "已投入 %d" % invested

	var effect: float = FusionEngine.part_effect(
		part_id, float(invested), DataManager.get_balance()
	)
	var pct: float = clampf(effect * 100.0, 0.0, 100.0)
	_bar.value = pct

	var color := COLOR_LOW
	if pct >= 66.0:
		color = COLOR_HIGH
	elif pct >= 33.0:
		color = COLOR_MID
	var sb := _bar.get_theme_stylebox("fill")
	if sb is StyleBoxFlat:
		(sb as StyleBoxFlat).bg_color = color


# --- Godot 拖放接口 ---

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.get("type", "") == BudgetToken.DRAG_TYPE:
		hover_preview.emit(part_id, int(data.get("amount", 0)))
		return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	token_dropped.emit(part_id, int(data.get("amount", 0)))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		withdraw_requested.emit(part_id)
