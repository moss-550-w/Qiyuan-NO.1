extends Control
## ControlRoom —— 中控台主场景（D3：故障联动 + 轮次提交结算）
##
## 在 D2 拖放/预测基础上接入 FaultTree：
##   - 每轮开始按 faults.json 施加故障，物理仪表偏离正常、Q/稳定/燃料 baseline 被拉低。
##   - 玩家在"正确部位"投入修复，仪表读数回升、指标缓解（实时预测可见）。
##   - 点"提交本轮"：投入达阈值的根因被识破并记录，推进下一轮；末轮触发结局占位。

const GAUGE_SCENE := preload("res://scenes/components/Gauge.tscn")
const TOKEN_SCENE := preload("res://scenes/components/BudgetToken.tscn")
const BRIEFING_SCENE := preload("res://scenes/components/BriefingCard.tscn")
const TOKEN_FACE := 10   # 单枚代币面额

@onready var _title: Label = $Root/Main/Header/Title
@onready var _btn_submit: Button = $Root/Main/Header/BtnSubmit
@onready var _btn_back: Button = $Root/Main/Header/BtnBack
@onready var _info: RichTextLabel = $Root/Main/InfoLabel
@onready var _briefing_row: HBoxContainer = $Root/Main/BriefingRow
@onready var _metrics: RichTextLabel = $Root/Main/MetricsPanel/MetricsLabel
@onready var _gauge_row: HBoxContainer = $Root/Main/GaugeRow
@onready var _device_view: HBoxContainer = $Root/Main/DeviceView
@onready var _token_row: HBoxContainer = $Root/Main/PoolPanel/PoolVBox/TokenRow
@onready var _pool_label: Label = $Root/Main/PoolPanel/PoolVBox/PoolLabel

var _gauges: Dictionary = {}          # gauge_id → Gauge
var _gauge_base: Dictionary = {}      # gauge_id → 基准读数
var _zones: Array[DropZone] = []
var _part_labels: Dictionary = {}     # part_id → 显示名
var _actual: Dictionary = {"q": 1.0, "stability": 1.0, "fuel": 1.0}
var _predicting: bool = false


func _ready() -> void:
	GameState.reset(SaveManager.settings.get("difficulty", "novice"))
	_btn_back.pressed.connect(_on_back)
	_btn_submit.pressed.connect(_on_submit)
	_build_gauges()
	_wire_zones()
	_start_round(1)


func _process(_dt: float) -> void:
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
		_gauge_base[id] = float((gauges_def[id] as Dictionary).get("base", 0.0))


func _wire_zones() -> void:
	for child in _device_view.get_children():
		if child is DropZone:
			var zone := child as DropZone
			_zones.append(zone)
			_part_labels[zone.part_id] = zone.part_label
			zone.token_dropped.connect(_on_token_dropped)
			zone.withdraw_requested.connect(_on_withdraw)
			zone.hover_preview.connect(_on_hover_preview)


func _rebuild_pool() -> void:
	for t in _token_row.get_children():
		t.queue_free()
	var count: int = int(GameState.budget_remaining / TOKEN_FACE)
	for i in count:
		var token: BudgetToken = TOKEN_SCENE.instantiate()
		_token_row.add_child(token)
		token.set_face_value(TOKEN_FACE)
	_pool_label.text = "经费池 · 剩余 ¥%d（每枚 ¥%d，拖到下方装置部位投资修复）" % \
		[GameState.budget_remaining, TOKEN_FACE]


# ---------------------------------------------------------------------------
# 轮次流程
# ---------------------------------------------------------------------------

## 开始第 r 轮：重置经费分配、施加故障、刷新全部显示
func _start_round(r: int) -> void:
	GameState.start_round(r)
	_btn_submit.disabled = false
	_title.text = "启元一号 · 中控台　|　第 %d 轮 / %d" % [r, GameState.TOTAL_ROUNDS]

	var fault_round: Dictionary = FaultTree.round_data(r)
	_info.text = "[color=#f5c63f]%s[/color]　%s" % [
		fault_round.get("title", "第 %d 轮" % r),
		_round_intro(r),
	]
	_build_briefings(r)
	_rebuild_pool()
	for z in _zones:
		z.refresh()
	_settle()


## 生成并显示本轮四份专家简报
func _build_briefings(r: int) -> void:
	for c in _briefing_row.get_children():
		c.queue_free()
	for b in BriefingSystem.generate(r):
		var card: BriefingCard = BRIEFING_SCENE.instantiate()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_briefing_row.add_child(card)
		card.setup(b)


## 提交本轮：识别判定 → 记录 → 推进 / 结束
func _on_submit() -> void:
	var r: int = GameState.current_round
	var newly: Array = FaultTree.evaluate_round(r)
	GameState.add_log({
		"round": r,
		"q": _actual["q"],
		"stability": _actual["stability"],
		"fuel": _actual["fuel"],
		"identified": newly.duplicate(),
	})
	AudioManager.play("ui_click")

	var feedback: String = _identify_feedback(newly)
	if GameState.is_final_round():
		_finish(feedback)
	else:
		AudioManager.play("round_start")
		_start_round(r + 1)
		_info.text += "　" + feedback


## 末轮结束：判定结局矩阵，解锁成就，切换到结局面板
func _finish(_last_feedback: String) -> void:
	_btn_submit.disabled = true
	GameState.set_metrics(_actual["q"], _actual["stability"], _actual["fuel"])
	var key: String = EndingResolver.build_key(
		float(_actual["q"]), GameState.identified_causes.size()
	)
	SaveManager.unlock_achievement(key)
	AudioManager.play("ending")
	get_tree().change_scene_to_file("res://scenes/panels/EndingPanel.tscn")


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
	_refresh_gauges()
	_show_actual()


## 刷新全部仪表：物理仪表按故障残余偏移，Q值/稳定度按结算指标
func _refresh_gauges() -> void:
	var r: int = GameState.current_round
	for id in _gauges:
		var gauge := _gauges[id] as Gauge
		if id == "q_value":
			gauge.set_reading(float(_actual["q"]))
		elif id == "stability":
			gauge.set_reading(float(_actual["stability"]) * 100.0)
		else:
			gauge.set_reading(FaultTree.gauge_reading(r, id, float(_gauge_base.get(id, 0.0))))


func _refresh_zone(part_id: String) -> void:
	for zone in _zones:
		if zone.part_id == part_id:
			zone.refresh()
			return


func _show_actual() -> void:
	_metrics.text = "[b]核心指标[/b]    Q值 %s    稳定度 %s    燃料自持 %s    [color=#f5c63f]剩余经费 ¥%d[/color]" % [
		_fmt_q(float(_actual["q"])),
		_fmt_pct(float(_actual["stability"]), 75),
		_fmt_pct(float(_actual["fuel"]), 85),
		GameState.budget_remaining,
	]


func _show_prediction(part_id: String, amount: int, pred: Dictionary) -> void:
	var dq: float = float(pred["q"]) - float(_actual["q"])
	var ds: float = (float(pred["stability"]) - float(_actual["stability"])) * 100.0
	var df: float = (float(pred["fuel"]) - float(_actual["fuel"])) * 100.0
	var label: String = _part_labels.get(part_id, part_id)
	_metrics.text = "[b][color=#2bd6ff]预测[/color][/b] 向 %s 投入 +%d → Q %s(%s)  稳定 %d%%(%s)  燃料 %d%%(%s)" % [
		label, amount,
		_fmt_q(float(pred["q"])), _fmt_delta(dq, 2),
		roundi(float(pred["stability"]) * 100.0), _fmt_delta(ds, 0),
		roundi(float(pred["fuel"]) * 100.0), _fmt_delta(df, 0),
	]


# --- 文本辅助 ---

func _round_intro(r: int) -> String:
	var rounds_cfg: Variant = DataManager.get_config("rounds")
	if rounds_cfg is Dictionary:
		for rr in (rounds_cfg as Dictionary).get("rounds", []):
			if int((rr as Dictionary).get("round", -1)) == r:
				return (rr as Dictionary).get("intro", "")
	return ""


func _identify_feedback(newly: Array) -> String:
	if newly.is_empty():
		return "[color=#e09040]本轮未在根因部位投足修复阈值，未识破根因。[/color]"
	var names: Array = []
	for c in newly:
		names.append(FaultTree.cause_name(c))
	return "[color=#4ed36a]✓ 识破并处置：%s[/color]" % ", ".join(names)


func _fmt_q(q: float) -> String:
	var color := "#4ed36a" if q >= 1.0 else "#e64040"
	return "[color=%s]%.2f[/color]" % [color, q]


func _fmt_pct(ratio: float, warn_below: int) -> String:
	var pct: int = roundi(ratio * 100.0)
	var color := "#4ed36a" if pct >= warn_below else "#e64040"
	return "[color=%s]%d%%[/color]" % [color, pct]


func _fmt_delta(d: float, decimals: int) -> String:
	var arrow := "↑" if d >= 0.0 else "↓"
	var color := "#4ed36a" if d >= 0.0 else "#e64040"
	var num: String = String.num(absf(d), decimals)
	return "[color=%s]%s%s[/color]" % [color, arrow, num]


func _on_back() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
