extends Control
class_name TokamakAnimation
## TokamakAnimation —— 托卡马克装置结局运行动画（程序矢量绘制）
##
## 按结局 Q 值命运分 3 档，全程用 _draw 矢量绘制，无图片、无粒子，Web 友好、
## 严格离线。绘制要素：环形真空室、四周环向场(TF)线圈、中心等离子体环、磁场线。
##
## 流程：set_outcome() 设档 → 播放 INTRO_TIME 秒 → 发 finished（可点击/按键跳过）。

signal finished

enum Mode { SUCCESS, CRITICAL, FAILURE }

const INTRO_TIME := 2.6
const TWO_PI := PI * 2.0

# 各档主色
const COL_SUCCESS := Color(0.55, 0.82, 1.0)
const COL_CRITICAL := Color(1.0, 0.65, 0.20)
const COL_FAILURE := Color(0.90, 0.28, 0.20)
const COL_WALL := Color(0.42, 0.52, 0.66)
const COL_COIL := Color(0.30, 0.62, 0.82)

@onready var _caption: Label = $Caption

var _mode: int = Mode.SUCCESS
var _elapsed: float = 0.0
var _done: bool = false
var _center: Vector2 = Vector2.ZERO
# 失败破裂关键时刻
const DISRUPT_START := 1.25
const DISRUPT_PEAK := 1.55
const DISRUPT_END := 2.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## 由 EndingResolver.q_band_key 设定：Qgt11→SUCCESS / Q1to11→CRITICAL / Qlt1→FAILURE
func set_outcome(q_band_key: String) -> void:
	match q_band_key:
		"Qgt11":
			_mode = Mode.SUCCESS
			_caption.text = "稳态长脉冲运行 · 约束良好"
			_caption.add_theme_color_override("font_color", COL_SUCCESS)
		"Q1to11":
			_mode = Mode.CRITICAL
			_caption.text = "勉强维持临界 · 约束抖动"
			_caption.add_theme_color_override("font_color", COL_CRITICAL)
		_:
			_mode = Mode.FAILURE
			_caption.text = "等离子体破裂 · 约束失效"
			_caption.add_theme_color_override("font_color", COL_FAILURE)


func _process(dt: float) -> void:
	_elapsed += dt
	_center = size * 0.5
	queue_redraw()
	if not _done and _elapsed >= INTRO_TIME:
		_done = true
		finished.emit()


func _gui_input(event: InputEvent) -> void:
	var skip: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if skip and not _done:
		_done = true
		finished.emit()


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _center == Vector2.ZERO:
		_center = size * 0.5
	var base_r: float = minf(size.x, size.y) * 0.30

	_draw_vacuum_vessel(base_r)
	_draw_tf_coils(base_r)
	_draw_field_lines(base_r)
	_draw_plasma(base_r)

	if _mode == Mode.FAILURE:
		_draw_disruption(base_r)


## 环形真空室（双层环）
func _draw_vacuum_vessel(r: float) -> void:
	draw_arc(_center, r * 1.30, 0, TWO_PI, 96, Color(COL_WALL, 0.9), 5.0, true)
	draw_arc(_center, r * 0.62, 0, TWO_PI, 80, Color(COL_WALL, 0.7), 4.0, true)


## 四周环向场线圈（D 形示意，用矩形+描边）
func _draw_tf_coils(r: float) -> void:
	var n := 8
	var coil_col := COL_COIL
	# 失败末期线圈失超变暗
	if _mode == Mode.FAILURE and _elapsed > DISRUPT_PEAK:
		coil_col = COL_COIL.darkened(0.5)
	for i in n:
		var ang: float = TWO_PI * float(i) / float(n)
		var pos: Vector2 = _center + Vector2(cos(ang), sin(ang)) * r * 1.55
		var rect := Rect2(pos - Vector2(14, 9), Vector2(28, 18))
		draw_rect(rect, Color(coil_col, 0.85), true)
		draw_rect(rect, Color(coil_col.lightened(0.3), 0.9), false, 2.0)


## 磁场线（绕环流动的弧），流速/规整度随档位
func _draw_field_lines(r: float) -> void:
	var col: Color = _mode_color()
	var line_count := 24
	var flow: float = _elapsed * _flow_speed()
	var jitter: float = _field_jitter()
	for i in line_count:
		var a0: float = TWO_PI * float(i) / float(line_count) + flow
		var seg: float = TWO_PI / float(line_count) * 0.6
		var rr: float = r * (0.95 + 0.32 * sin(a0 * 3.0))
		if jitter > 0.0:
			rr += randf_range(-jitter, jitter) * r
		var p0: Vector2 = _center + Vector2(cos(a0), sin(a0)) * rr
		var p1: Vector2 = _center + Vector2(cos(a0 + seg), sin(a0 + seg)) * rr
		draw_line(p0, p1, Color(col, 0.5), 2.0)


## 中心等离子体环（多层同心辉光 + 脉动）
func _draw_plasma(r: float) -> void:
	var col: Color = _mode_color()
	var pulse: float = _plasma_pulse()
	var core_r: float = r * pulse

	# 失败坍缩：峰值后半径骤降
	if _mode == Mode.FAILURE and _elapsed > DISRUPT_PEAK:
		var t: float = clampf((_elapsed - DISRUPT_PEAK) / (DISRUPT_END - DISRUPT_PEAK), 0.0, 1.0)
		core_r = r * (1.45 - 1.3 * t) * pulse

	# 多层辉光：外淡内浓
	var layers := 6
	for i in range(layers, 0, -1):
		var f: float = float(i) / float(layers)
		var rad: float = core_r * (0.45 + 0.55 * f)
		var a: float = 0.10 + 0.16 * (1.0 - f)
		draw_circle(_center, rad, Color(col, a))
	# 炽热核心
	draw_circle(_center, core_r * 0.35, Color(col.lightened(0.5), 0.85))


## 失败破裂特效：屏闪 + 第一壁烧蚀火花
func _draw_disruption(r: float) -> void:
	if _elapsed < DISRUPT_START or _elapsed > DISRUPT_END + 0.4:
		return
	# 屏闪
	var flash: float = maxf(0.0, 1.0 - absf(_elapsed - DISRUPT_PEAK) * 3.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.95, 0.85, flash * 0.5), true)
	# 第一壁烧蚀火花（沿真空室内壁迸射）
	if _elapsed >= DISRUPT_PEAK:
		var sparks := 30
		for i in sparks:
			var ang: float = TWO_PI * float(i) / float(sparks) + _elapsed
			var t: float = clampf((_elapsed - DISRUPT_PEAK) / 0.6, 0.0, 1.0)
			var from: Vector2 = _center + Vector2(cos(ang), sin(ang)) * r * 1.25
			var to: Vector2 = _center + Vector2(cos(ang), sin(ang)) * r * (1.25 + 0.25 * t)
			draw_line(from, to, Color(1.0, 0.6, 0.2, 1.0 - t), 3.0)


# ---------------------------------------------------------------------------
# 按档位调制的参数
# ---------------------------------------------------------------------------

func _mode_color() -> Color:
	match _mode:
		Mode.SUCCESS: return COL_SUCCESS
		Mode.CRITICAL: return COL_CRITICAL
		_: return COL_FAILURE


func _flow_speed() -> float:
	match _mode:
		Mode.SUCCESS: return 1.2
		Mode.CRITICAL: return 0.7
		_: return 2.4 if _elapsed < DISRUPT_PEAK else 0.0


## 磁场线抖动幅度（0=顺滑）
func _field_jitter() -> float:
	match _mode:
		Mode.SUCCESS: return 0.0
		Mode.CRITICAL: return 0.015
		_: return 0.04 if _elapsed > DISRUPT_START else 0.02


## 等离子体半径脉动系数
func _plasma_pulse() -> float:
	match _mode:
		Mode.SUCCESS:
			return 1.0 + 0.05 * sin(_elapsed * 3.0)
		Mode.CRITICAL:
			return 1.0 + 0.12 * sin(_elapsed * 8.0)
		_:
			# 失败：破裂前骤胀
			if _elapsed >= DISRUPT_START and _elapsed <= DISRUPT_PEAK:
				var t: float = (_elapsed - DISRUPT_START) / (DISRUPT_PEAK - DISRUPT_START)
				return 1.0 + 0.45 * t
			return 1.0 + 0.08 * sin(_elapsed * 6.0)
