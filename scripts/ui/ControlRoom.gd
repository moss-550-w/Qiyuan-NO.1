extends Control
## ControlRoom —— 中控台主场景（D2：拖放 + 实时预测 + 仪表联动）
##
## 整合：经费池(代币) + 四部位 DropZone + 仪表行 + 核心指标显示。
## 数据流：拖放 token → GameState.allocate → FusionEngine 结算 → 刷新仪表/指标。
## 悬停预测：DropZone.hover_preview → FusionEngine.predict_with_extra → 高亮回显增量。

const GAUGE_SCENE := preload("res://scenes/components/Gauge.tscn")
const TOKEN_SCENE := preload("res://scenes/components/BudgetToken.tscn")
const TOKEN_FACE := 10   # 单枚代币面额

@onready var _metrics: RichTextLabel = $Root/Main/MetricsPanel/MetricsLabel
@onready var _gauge_row: HBoxContainer = $Root/Main/GaugeRow
@onready var _device_view: HBoxContainer = $Root/Main/DeviceView
@onready var _token_row: HBoxContainer = $Root/Main/PoolPanel/PoolVBox/TokenRow
@onready var _pool_label: Label = $Root/Main/PoolPanel/PoolVBox/PoolLabel
@onready var _btn_back: Button = $Root/Main/Header/BtnBack

var _gauges: Dictionary = {}          # gauge_id → Gauge
var _zones: Array[DropZone] = []
var _part_labels: Dictionary = {}     # part_id → 显示名
var _actual: Dictionary = {"q": 1.0, "stability": 1.0, "fuel": 1.0}
var _predicting: bool = false


func _ready() -> void:
	GameState.reset(SaveManager.settings.get("difficulty", "novice"))
	GameState.start_round(1)
	_btn_back.pressed.connect(_on_back)
	_build_gauges()
	_wire_zones()
	_rebuild_pool()
	_settle()


func _process(_dt: float) -> void:
	# 拖放结束（无论在何处释放）后，把指标显示恢复为实际值
	if _predicting and not get_viewport().gui_is_dragging():
		_predicting = false
		_show_actual()


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func _build_gauges() -> void:
	var rounds_cfg: Variant = DataManager.get_config("rounds")
	if not (rounds_cfg is Dictionary):
		return
	var gauges_def: Dictionary = (rounds_cfg as Dictionary).get("gauges", {})
	for id in gauges_def:
		var gauge: Gauge = GAUGE_SCENE.instantiate()
		_gauge_row.add_child(gauge)
		gauge.setup(id, gauges_def[id])
		_gauges[id] = gauge


func _wire_zones() -> void:
	for child in _device_view.get_children():
		if child is DropZone:
			var zone := child as DropZone
			_zones.append(zone)
			_part_labels[zone.part_id] = zone.part_label
			zone.token_dropped.connect(_on_token_dropped)
			zone.withdraw_requested.connect(_on_withdraw)
			zone.hover_preview.connect(_on_hover_preview)


## 按剩余经费重建代币池（剩余 / 面额 枚）
func _rebuild_pool() -> void:
	for t in _token_row.get_children():
		t.queue_free()
	var count: int = int(GameState.budget_remaining / TOKEN_FACE)
	for i in count:
		var token: BudgetToken = TOKEN_SCENE.instantiate()
		_token_row.add_child(token)
		token.set_face_value(TOKEN_FACE)
	_pool_label.text = "经费池 · 剩余 ¥%d（每枚 ¥%d，拖到下方装置部位投资）" % \
		[GameState.budget_remaining, TOKEN_FACE]


# ---------------------------------------------------------------------------
# 交互回调
# ---------------------------------------------------------------------------

func _on_token_dropped(part_id: String, amount: int) -> void:
	if GameState.allocate(part_id, amount):
		AudioManager.play("token_drop")
		_refresh_zone(part_id)
		_rebuild_pool()
		_settle()


func _on_withdraw(part_id: String) -> void:
	var cur: int = int(GameState.round_allocation.get(part_id, 0))
	if cur > 0 and GameState.withdraw(part_id, cur):
		AudioManager.play("ui_click")
		_refresh_zone(part_id)
		_rebuild_pool()
		_settle()


func _on_hover_preview(part_id: String, amount: int) -> void:
	# 经费不足以再投时不预测
	if GameState.budget_remaining < amount:
		return
	_predicting = true
	var pred: Dictionary = FusionEngine.predict_with_extra(part_id, amount)
	_show_prediction(part_id, amount, pred)


# ---------------------------------------------------------------------------
# 结算与显示
# ---------------------------------------------------------------------------

## 用当前实际分配结算核心指标，刷新仪表与指标条
func _settle() -> void:
	var pred: Dictionary = FusionEngine.predict_with_extra("", 0)
	_actual = pred
	GameState.set_metrics(pred["q"], pred["stability"], pred["fuel"])
	_update_metric_gauges(pred)
	_show_actual()


func _update_metric_gauges(m: Dictionary) -> void:
	if _gauges.has("q_value"):
		(_gauges["q_value"] as Gauge).set_reading(float(m["q"]))
	if _gauges.has("stability"):
		(_gauges["stability"] as Gauge).set_reading(float(m["stability"]) * 100.0)


func _refresh_zone(part_id: String) -> void:
	for zone in _zones:
		if zone.part_id == part_id:
			zone.refresh()
			return


func _show_actual() -> void:
	_metrics.text = "[b]核心指标[/b]    Q值 %s    稳定度 %d%%    燃料自持 %d%%    [color=#f5c63f]剩余经费 ¥%d[/color]" % [
		_fmt_q(float(_actual["q"])),
		roundi(float(_actual["stability"]) * 100.0),
		roundi(float(_actual["fuel"]) * 100.0),
		GameState.budget_remaining,
	]


func _show_prediction(part_id: String, amount: int, pred: Dictionary) -> void:
	var dq: float = float(pred["q"]) - float(_actual["q"])
	var ds: float = (float(pred["stability"]) - float(_actual["stability"])) * 100.0
	var label: String = _part_labels.get(part_id, part_id)
	_metrics.text = "[b][color=#2bd6ff]预测[/color][/b] 向 %s 投入 +%d → Q值 %s (%s)   稳定度 %d%% (%s)" % [
		label, amount,
		_fmt_q(float(pred["q"])), _fmt_delta(dq, 2),
		roundi(float(pred["stability"]) * 100.0), _fmt_delta(ds, 0),
	]


# --- 格式化辅助 ---

func _fmt_q(q: float) -> String:
	var color := "#4ed36a" if q >= 1.0 else "#e64040"
	return "[color=%s]%.2f[/color]" % [color, q]


func _fmt_delta(d: float, decimals: int) -> String:
	var arrow := "↑" if d >= 0.0 else "↓"
	var color := "#4ed36a" if d >= 0.0 else "#e64040"
	var num: String = String.num(absf(d), decimals)
	return "[color=%s]%s%s[/color]" % [color, arrow, num]


func _on_back() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
