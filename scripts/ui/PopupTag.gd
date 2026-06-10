extends Panel
class_name PopupTag
## PopupTag —— 上下文浮动科普标签
##
## 拖放经费到部位时浮现，半透明、3 秒自动淡出消失；点击一次"钉住"（取消自动
## 消退），再次点击关闭。零弹窗打断——它只是叠在操作对象旁的背景信息。

@onready var _title: Label = $Margin/VBox/Title
@onready var _text: RichTextLabel = $Margin/VBox/Text
@onready var _pin: Label = $Margin/VBox/PinHint

const SHOW_SECONDS := 3.0

var _pinned: bool = false
var _tween: Tween = null


func setup(title: String, body: String) -> void:
	_title.text = title
	_text.text = body
	_pin.text = "点击钉住"
	modulate.a = 0.0
	_start_fade()


func _start_fade() -> void:
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.tween_interval(SHOW_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(queue_free)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not _pinned:
			_pin_it()
		else:
			queue_free()


## 钉住：停止自动消退，常驻直到再次点击
func _pin_it() -> void:
	_pinned = true
	if _tween and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	_pin.text = "已钉住 · 点击关闭"
