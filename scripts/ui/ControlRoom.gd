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
const MANUAL_SCENE := preload("res://scenes/panels/ManualPanel.tscn")
const LOG_SCENE := preload("res://scenes/panels/LogPanel.tscn")
const POPUP_SCENE := preload("res://scenes/components/PopupTag.tscn")
const TOKEN_FACE := 10   # 单枚代币面额

@onready var _title: Label = $Root/Main/Header/Title
@onready var _timer_label: Label = $Root/Main/Header/TimerLabel
@onready var _btn_log: Button = $Root/Main/Header/BtnLog
@onready var _btn_manual: Button = $Root/Main/Header/BtnManual
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
var _manual: ManualPanel = null
var _log_panel: LogPanel = null

# 时间压力
var _timed: bool = false          # 本轮是否限时
var _time_left: float = 0.0
# 本轮各物理仪表噪声偏移系数（总工模式）
var _round_noise: Dictionary = {}
# 各部位当前浮动科普标签：part_id → PopupTag
var _popups: Dictionary = {}


func _ready() -> void:
	_btn_back.pressed.connect(_on_back)
	_btn_submit.pressed.connect(_on_submit)
	_btn_manual.pressed.connect(_on_manual)
	_btn_log.pressed.connect(_on_log)
	_manual = MANUAL_SCENE.instantiate()
	add_child(_manual)
	_log_panel = LOG_SCENE.instantiate()
	add_child(_log_panel)
	_build_gauges()
	_wire_zones()

	# current_round<=0 视为新局（菜单已 reset）；>0 视为续档，回到该轮起点
	if GameState.current_round <= 0:
		GameState.reset(SaveManager.settings.get("difficulty", "novice"))
		_start_round(1)
	else:
		_start_round(GameState.current_round)

	# 仅总工/自定义模式（show_history_log）显示历史日志入口
	_btn_log.visible = bool(
		DataManager.get_difficulty(GameState.difficulty).get("show_history_log", false)
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			_on_manual()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_L and _btn_log.visible:
			_on_log()
			get_viewport().set_input_as_handled()


func _on_manual() -> void:
	AudioManager.play("ui_click")
	if _manual:
		_manual.toggle()


func _on_log() -> void:
	AudioManager.play("ui_click")
	if _log_panel:
		_log_panel.toggle()


func _process(_dt: float) -> void:
	if _predicting and not get_viewport().gui_is_dragging():
		_predicting = false
		_show_actual()
	_tick_timer(_dt)


## 倒计时：手册/日志打开时暂停；归零自动提交并施加延迟惩罚
func _tick_timer(dt: float) -> void:
	if not _timed or _btn_submit.disabled:
		return
	if _manual.visible or _log_panel.visible:
		return
	_time_left -= dt
	if _time_left <= 0.0:
		_time_left = 0.0
		_update_timer_label()
		_on_timeout()
	else:
		_update_timer_label()


func _update_timer_label() -> void:
	if not _timed:
		_timer_label.text = "⏱ 不限时"
		_timer_label.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62))
		return
	var total: int = int(ceil(_time_left))
	_timer_label.text = "⏱ %02d:%02d" % [total / 60, total % 60]
	var col := Color(0.85, 0.89, 0.94)
	if _time_left <= 30.0:
		col = Color(0.90, 0.25, 0.25)
	elif _time_left <= 60.0:
		col = Color(0.95, 0.80, 0.25)
	_timer_label.add_theme_color_override("font_color", col)


## 限时耗尽：标记延迟、重算（稳定度惩罚）、自动提交
func _on_timeout() -> void:
	GameState.round_delayed = true
	AudioManager.play("alarm")
	_settle()
	_on_submit()


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

## 开始第 r 轮：重置经费分配、施加故障、设置限时/噪声/提示、刷新全部显示
func _start_round(r: int) -> void:
	GameState.start_round(r)
	_btn_submit.disabled = false
	_clear_popups()
	_title.text = "启元一号 · 中控台　|　第 %d 轮 / %d" % [r, GameState.TOTAL_ROUNDS]

	var fault_round: Dictionary = FaultTree.round_data(r)
	_info.text = "[color=#f5c63f]%s[/color]　%s" % [
		fault_round.get("title", "第 %d 轮" % r),
		_round_intro(r),
	]
	_setup_timer(r)
	_setup_noise()
	_build_briefings(r)
	_apply_hints(r)
	_rebuild_pool()
	for z in _zones:
		z.refresh()
	_settle()
	SaveManager.save_game()   # 每轮开始即存档，支持退出续档


## 按难度+本轮配置启动限时（难度 time_limit=0 或全局关闭则不限时）
func _setup_timer(r: int) -> void:
	var diff: Dictionary = DataManager.get_difficulty(GameState.difficulty)
	var enabled: bool = bool(SaveManager.settings.get("time_limit_enabled", true))
	var diff_limit: float = float(diff.get("time_limit", 0))
	_timed = enabled and diff_limit > 0.0
	if _timed:
		# 难度启用限时后，具体时长取本轮 rounds 配置（缺省回退难度值）
		var rounds_cfg: Variant = DataManager.get_config("rounds")
		var per_round: float = diff_limit
		if rounds_cfg is Dictionary:
			for rr in (rounds_cfg as Dictionary).get("rounds", []):
				if int((rr as Dictionary).get("round", -1)) == r:
					per_round = float((rr as Dictionary).get("time_limit", diff_limit))
		_time_left = per_round
	_update_timer_label()


## 总工模式：为各物理仪表生成本轮固定噪声偏移
func _setup_noise() -> void:
	_round_noise.clear()
	var noise: float = float(DataManager.get_difficulty(GameState.difficulty).get("gauge_noise", 0.0))
	for id in _gauge_base:
		_round_noise[id] = randf_range(-noise, noise) if noise > 0.0 else 0.0


## 新手模式：在本轮故障的修复部位显示"建议排查"角标
func _apply_hints(r: int) -> void:
	var show_hint: bool = bool(DataManager.get_difficulty(GameState.difficulty).get("show_hint_dash", false))
	for z in _zones:
		z.set_hint(false)
	if not show_hint:
		return
	var causes: Dictionary = DataManager.get_faults().get("root_causes", {})
	for c in FaultTree.round_active_causes(r):
		var fix_part: String = (causes.get(c, {}) as Dictionary).get("fix_part", "")
		for z in _zones:
			if z.part_id == fix_part:
				z.set_hint(true)


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
		"gauges": _gauge_snapshot(r),
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
	SaveManager.clear_save()   # 一局完成，清除续档
	AudioManager.play("ending")
	get_tree().change_scene_to_file("res://scenes/panels/EndingPanel.tscn")


## 当前轮各关注仪表的读数快照（写入历史日志）
func _gauge_snapshot(r: int) -> Dictionary:
	var snap: Dictionary = {}
	for id in ["toroidal_field", "wall_temp", "tritium_ratio"]:
		if _gauge_base.has(id):
			snap[id] = FaultTree.gauge_reading(r, id, float(_gauge_base[id]))
	return snap


# ---------------------------------------------------------------------------
# 交互回调
# ---------------------------------------------------------------------------

func _on_token_dropped(part_id: String, amount: int) -> void:
	if GameState.allocate(part_id, amount):
		AudioManager.play("token_drop")
		_refresh_zone(part_id)
		_rebuild_pool()
		_settle()
		_show_popup(part_id)


## 在部位上方浮现该部位的上下文科普标签（popups.json）
func _show_popup(part_id: String) -> void:
	var popups: Variant = DataManager.get_config("popups")
	if not (popups is Dictionary):
		return
	var data: Dictionary = (popups as Dictionary).get(part_id, {})
	if data.is_empty():
		return
	# 同部位仅保留一个，先移除旧标签
	if _popups.has(part_id) and is_instance_valid(_popups[part_id]):
		_popups[part_id].queue_free()
	var tag: PopupTag = POPUP_SCENE.instantiate()
	add_child(tag)
	tag.setup(data.get("title", ""), data.get("text", ""))
	_position_popup(tag, part_id)
	_popups[part_id] = tag


## 把标签定位到对应 DropZone 的上方
func _position_popup(tag: PopupTag, part_id: String) -> void:
	for z in _zones:
		if z.part_id == part_id:
			var zpos: Vector2 = z.global_position
			tag.global_position = Vector2(zpos.x, zpos.y - 118.0)
			return


func _clear_popups() -> void:
	for k in _popups:
		if is_instance_valid(_popups[k]):
			_popups[k].queue_free()
	_popups.clear()


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
			var reading: float = FaultTree.gauge_reading(r, id, float(_gauge_base.get(id, 0.0)))
			# 总工模式叠加本轮固定噪声
			reading *= (1.0 + float(_round_noise.get(id, 0.0)))
			gauge.set_reading(reading)


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
