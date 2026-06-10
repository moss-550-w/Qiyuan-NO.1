extends Control
class_name SettingsPanel
## SettingsPanel —— 游戏内设置面板（覆盖式）
##
## 调整 BGM 音量 / 音效音量 / 粒子质量 / 限时开关 / 难度，全部实时生效并持久化
## 到 SaveManager.settings。纯本地，无网络。

signal settings_changed

@onready var _dimmer: ColorRect = $Dimmer
@onready var _btn_close: Button = $Center/Window/Margin/VBox/Header/BtnClose
@onready var _bgm_slider: HSlider = $Center/Window/Margin/VBox/BgmRow/BgmSlider
@onready var _bgm_value: Label = $Center/Window/Margin/VBox/BgmRow/BgmValue
@onready var _sfx_slider: HSlider = $Center/Window/Margin/VBox/SfxRow/SfxSlider
@onready var _sfx_value: Label = $Center/Window/Margin/VBox/SfxRow/SfxValue
@onready var _particle_opt: OptionButton = $Center/Window/Margin/VBox/ParticleRow/ParticleOpt
@onready var _difficulty_opt: OptionButton = $Center/Window/Margin/VBox/DifficultyRow/DifficultyOpt
@onready var _time_check: CheckButton = $Center/Window/Margin/VBox/TimeRow/TimeCheck

const PARTICLE_OPTIONS := [
	{"id": "high", "label": "高（桌面端）"},
	{"id": "low", "label": "低（网页/低端）"},
	{"id": "off", "label": "关闭"},
]
const DIFFICULTY_OPTIONS := ["novice", "chief", "custom"]


func _ready() -> void:
	visible = false
	_btn_close.pressed.connect(close)
	_dimmer.gui_input.connect(_on_dimmer_input)
	_build_options()
	_wire_signals()


func open() -> void:
	_load_into_ui()
	visible = true
	move_to_front()


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


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func _build_options() -> void:
	_particle_opt.clear()
	for opt in PARTICLE_OPTIONS:
		_particle_opt.add_item(opt["label"])

	_difficulty_opt.clear()
	for d in DIFFICULTY_OPTIONS:
		_difficulty_opt.add_item(DataManager.get_difficulty(d).get("label", d))


func _wire_signals() -> void:
	_bgm_slider.value_changed.connect(_on_bgm_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_particle_opt.item_selected.connect(_on_particle_selected)
	_difficulty_opt.item_selected.connect(_on_difficulty_selected)
	_time_check.toggled.connect(_on_time_toggled)


## 把当前设置载入到控件（不触发信号副作用）
func _load_into_ui() -> void:
	var s: Dictionary = SaveManager.settings
	_bgm_slider.set_value_no_signal(float(s.get("bgm_volume", 0.5)) * 100.0)
	_sfx_slider.set_value_no_signal(float(s.get("master_volume", 1.0)) * 100.0)
	_bgm_value.text = "%d%%" % roundi(_bgm_slider.value)
	_sfx_value.text = "%d%%" % roundi(_sfx_slider.value)

	var pq: String = s.get("particle_quality", "high")
	for i in PARTICLE_OPTIONS.size():
		if PARTICLE_OPTIONS[i]["id"] == pq:
			_particle_opt.select(i)
			break

	var diff: String = s.get("difficulty", "novice")
	var di: int = DIFFICULTY_OPTIONS.find(diff)
	_difficulty_opt.select(maxi(di, 0))

	_time_check.set_pressed_no_signal(bool(s.get("time_limit_enabled", true)))


# ---------------------------------------------------------------------------
# 变更回调（实时生效 + 持久化）
# ---------------------------------------------------------------------------

func _on_bgm_changed(value: float) -> void:
	var v: float = value / 100.0
	AudioManager.set_bgm_volume(v)   # 内部已写入 settings
	_bgm_value.text = "%d%%" % roundi(value)
	_persist()


func _on_sfx_changed(value: float) -> void:
	SaveManager.settings["master_volume"] = value / 100.0
	_sfx_value.text = "%d%%" % roundi(value)
	AudioManager.play("ui_click")   # 即时试听
	_persist()


func _on_particle_selected(index: int) -> void:
	SaveManager.settings["particle_quality"] = PARTICLE_OPTIONS[index]["id"]
	_persist()
	settings_changed.emit()


func _on_difficulty_selected(index: int) -> void:
	SaveManager.settings["difficulty"] = DIFFICULTY_OPTIONS[index]
	_persist()
	settings_changed.emit()


func _on_time_toggled(pressed: bool) -> void:
	SaveManager.settings["time_limit_enabled"] = pressed
	_persist()
	settings_changed.emit()


func _persist() -> void:
	SaveManager.save_settings()
