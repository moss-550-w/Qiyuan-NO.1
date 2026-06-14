extends Panel
class_name Gauge
## Gauge —— 可复用仪表盘组件
##
## 显示单个指标：标签、当前值、单位，并按正常区间着色（绿/黄/红）。
## 数据由外部通过 set_reading() 注入，组件本身不持有业务逻辑。

@onready var _label: Label = $Margin/VBox/LabelName
@onready var _value: Label = $Margin/VBox/LabelValue
@onready var _bar: ProgressBar = $Margin/VBox/Bar

var gauge_id: String = ""
var _unit: String = ""
var _normal_min: float = 0.0
var _normal_max: float = 1.0
var _base_label: String = ""        # 不含角标的原始标签名
var _stable_confirmed: bool = false

const COLOR_NORMAL := Color(0.30, 0.85, 0.40)   # 绿
const COLOR_WARN := Color(0.95, 0.80, 0.25)     # 黄
const COLOR_DANGER := Color(0.90, 0.25, 0.25)   # 红


## 用 rounds.json 的 gauge 配置初始化
func setup(id: String, cfg: Dictionary) -> void:
	gauge_id = id
	_unit = cfg.get("unit", "")
	_normal_min = float(cfg.get("normal_min", 0.0))
	_normal_max = float(cfg.get("normal_max", 1.0))
	_base_label = cfg.get("label", id)
	_label.text = _base_label
	_bar.min_value = _normal_min - (_normal_max - _normal_min) * 0.5
	_bar.max_value = _normal_max + (_normal_max - _normal_min) * 0.5
	set_reading(float(cfg.get("base", _normal_min)))


## 更新当前读数并刷新着色
func set_reading(value: float) -> void:
	_value.text = "%.2f %s" % [value, _unit] if not _unit.is_empty() else "%.2f" % value
	_bar.value = clampf(value, _bar.min_value, _bar.max_value)

	var color := COLOR_NORMAL
	if value < _normal_min or value > _normal_max:
		# 越界程度决定黄/红
		var span := maxf(_normal_max - _normal_min, 0.0001)
		var over := maxf(_normal_min - value, value - _normal_max) / span
		color = COLOR_DANGER if over > 0.25 else COLOR_WARN

	_value.add_theme_color_override("font_color", color)
	var sb := _bar.get_theme_stylebox("fill")
	if sb is StyleBoxFlat:
		(sb as StyleBoxFlat).bg_color = color


## 设置"超额投入·稳定确认"角标（由上一轮超额投入触发）
func set_stable_confirmed(on: bool) -> void:
	_stable_confirmed = on
	if not _chain_linked:
		_label.text = _base_label + ("  ✓稳定" if on else "")
		if on:
			_label.add_theme_color_override("font_color", COLOR_NORMAL)
		else:
			_label.remove_theme_color_override("font_color")


## 设置"故障链同步"角标（第3轮后激活的耦合链次因仪表）
var _chain_linked: bool = false
func set_chain_linked(on: bool) -> void:
	_chain_linked = on
	_label.text = _base_label + ("  ⇌链路" if on else ("  ✓稳定" if _stable_confirmed else ""))
	if on:
		_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.25))
	elif _stable_confirmed:
		_label.add_theme_color_override("font_color", COLOR_NORMAL)
	else:
		_label.remove_theme_color_override("font_color")
## 高亮标记（教学战役用）
var _highlighted: bool = false
func set_highlight(on: bool) -> void:
	_highlighted = on
	if on:
		add_theme_stylebox_override("panel", _get_highlight_stylebox())
	else:
		remove_theme_stylebox_override("panel")

func _get_highlight_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.84, 1.0, 0.15)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.17, 0.84, 1.0, 0.8)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb
