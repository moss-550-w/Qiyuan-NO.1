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
const PLASMA_SCENE := preload("res://scenes/fx/PlasmaCore.tscn")
const TOKAMAK_SCENE := preload("res://scenes/fx/TokamakAnimation.tscn")
const LOCK_PREVIEW_SCENE := preload("res://scenes/components/LockPreviewPanel.tscn")
const TOKEN_FACE := 10   # 单枚代币面额

@onready var _title: Label = $Root/Main/Header/Title
@onready var _timer_label: Label = $Root/Main/Header/TimerLabel
@onready var _alarm_banner: Panel = $AlarmBanner
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
var _plasma: PlasmaCore = null
var _tokamak: TokamakAnimation = null

# 破裂报警
var _disrupt_threshold: float = 0.4
var _alarming: bool = false
var _alarm_t: float = 0.0

# 时间压力
var _timed: bool = false          # 本轮是否限时
var _time_left: float = 0.0
# 本轮各物理仪表噪声偏移系数（总工模式）
var _round_noise: Dictionary = {}
# 各部位当前浮动科普标签：part_id → PopupTag
var _popups: Dictionary = {}
# 本轮已确认过"逻辑一致性提示"的轮次（避免重复打扰）
var _consistency_confirmed_round: int = -1


func _ready() -> void:
	_btn_back.pressed.connect(_on_back)
	_btn_submit.pressed.connect(_on_submit)
	_btn_manual.pressed.connect(_on_manual)
	_btn_log.pressed.connect(_on_log)
	_manual = MANUAL_SCENE.instantiate()
	add_child(_manual)
	_log_panel = LOG_SCENE.instantiate()
	add_child(_log_panel)
	# 等离子体粒子 + 托卡马克剖面动画作为背景层（BG 之上、UI 之下）
	_plasma = PLASMA_SCENE.instantiate()
	add_child(_plasma)
	move_child(_plasma, 1)
	_plasma.position = Vector2(960, 540)
	# 实时托卡马克剖面：按稳定度反映三档运行态，破裂时联动报警
	_tokamak = TOKAMAK_SCENE.instantiate()
	add_child(_tokamak)
	move_child(_tokamak, 2)
	_tokamak.start_live()
	_tokamak.modulate.a = 0.5

	# 教学战役引导提示接入
	TutorialCampaign.hint_requested.connect(_on_tutorial_hint)
	TutorialCampaign.hint_cleared.connect(_on_tutorial_hint_cleared)

	# 破裂报警阈值与横幅样式
	_disrupt_threshold = float(
		DataManager.get_balance().get("stability", {}).get("disruption_threshold", 0.4)
	)
	_setup_alarm_banner()

	_build_gauges()
	_wire_zones()

	# current_round<=0 视为新局（菜单已 reset）；>0 视为续档，回到该轮起点
	if GameState.current_round <= 0:
		GameState.reset(SaveManager.settings.get("difficulty", "novice"))
		_start_round(1)
	else:
		_start_round(GameState.current_round, true)

	# 仅总工/自定义模式（show_history_log）显示历史日志入口
	_btn_log.visible = bool(
		DataManager.get_difficulty(GameState.difficulty).get("show_history_log", false)
	)
	AudioManager.play_bgm("control")


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
	_pulse_alarm(_dt)


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


## 限时耗尽：标记延迟、重算（稳定度惩罚）、自动提交（跳过一致性提示）
func _on_timeout() -> void:
	GameState.round_delayed = true
	AudioManager.play("alarm")
	_settle()
	_do_submit()


# ---------------------------------------------------------------------------
# 破裂报警
# ---------------------------------------------------------------------------

func _setup_alarm_banner() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.62, 0.10, 0.10, 0.92)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.45, 0.35, 1.0)
	sb.set_corner_radius_all(8)
	_alarm_banner.add_theme_stylebox_override("panel", sb)
	_alarm_banner.visible = false


## 进入/解除破裂报警（仅在状态切换时触发音效与弹窗，避免刷屏）
func _set_alarm(on: bool) -> void:
	if on == _alarming:
		return
	_alarming = on
	_alarm_banner.visible = on
	if on:
		AudioManager.play("alarm")
		AudioManager.play("disruption")
		_show_event_popup("evt_disruption")


## 报警横幅脉动（_process 调用）
func _pulse_alarm(dt: float) -> void:
	if not _alarming:
		return
	_alarm_t += dt
	_alarm_banner.modulate.a = 0.6 + 0.4 * absf(sin(_alarm_t * 4.0))


## 事件型浮动科普（如 evt_disruption），置于屏幕上方居中，同事件不重复弹
func _show_event_popup(event_id: String) -> void:
	var popups: Variant = DataManager.get_config("popups")
	if not (popups is Dictionary):
		return
	var data: Dictionary = (popups as Dictionary).get(event_id, {})
	if data.is_empty():
		return
	if _popups.has(event_id) and is_instance_valid(_popups[event_id]):
		return
	var tag: PopupTag = POPUP_SCENE.instantiate()
	add_child(tag)
	tag.setup(data.get("title", ""), data.get("text", ""))
	tag.position = Vector2(830.0, 158.0)
	_popups[event_id] = tag


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
			# 教学战役：过滤不可用部位
			if not TutorialCampaign.should_show_part(zone.part_id):
				zone.visible = false
				continue
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

## 开始第 r 轮：重置经费分配、施加故障、设置限时/噪声/提示、刷新全部显示。
## is_resume=true 表示续档恢复，保留存档中的超额奖励（不据已清零的分配重新结算）。
func _start_round(r: int, is_resume: bool = false) -> void:
	GameState.start_round(r, not is_resume)
	_btn_submit.disabled = false
	_clear_popups()
	var total_r: int
	if TutorialCampaign.is_tutorial_active():
		total_r = TutorialCampaign.get_round_count()
	else:
		total_r = GameState.TOTAL_ROUNDS
	_title.text = "启元一号 · 中控台 ｜ 第 %d 轮 / %d" % [r, total_r]
	_update_timer_label()

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
	_apply_stable_confirm(r)
	SaveManager.save_game()   # 每轮开始即存档，支持退出续档


## 超额投入奖励：对上一轮超额投入部位所关联的仪表显示"稳定确认"角标
func _apply_stable_confirm(r: int) -> void:
	var confirmed: Dictionary = {}
	var causes: Dictionary = DataManager.get_faults().get("root_causes", {})
	for s in FaultTree.round_symptoms(r):
		var sd: Dictionary = s
		var gauge: String = sd.get("gauge", "")
		var fix_part: String = (causes.get(sd.get("cause", ""), {}) as Dictionary).get("fix_part", "")
		if gauge != "" and fix_part != "" and GameState.over_invest_bonus(fix_part):
			confirmed[gauge] = true
	for id in _gauges:
		(_gauges[id] as Gauge).set_stable_confirmed(confirmed.has(id))


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


## 总工/挑战模式：为各物理仪表生成本轮干扰偏移。
## 采用确定性低频正弦 offset = amp * sin(round*freq + phase[gauge])：
## 跨轮平滑变化、多轮观察即可识别周期，从而与真实异常区分（不引入付费校准）。
## 兼容旧写法：gauge_noise 若为数值则退化为固定幅度的周期。
func _setup_noise() -> void:
	_round_noise.clear()
	var ncfg: Variant = DataManager.get_difficulty(GameState.difficulty).get("gauge_noise", 0.0)
	var amp: float = 0.0
	var freq: float = 1.0
	if ncfg is Dictionary:
		amp = float((ncfg as Dictionary).get("amp", 0.0))
		freq = float((ncfg as Dictionary).get("freq", 1.0))
	else:
		amp = float(ncfg)
	var r: int = GameState.current_round
	var idx: int = 0
	for id in _gauge_base:
		if amp <= 0.0:
			_round_noise[id] = 0.0
		else:
			# 各仪表错相位(idx*1.7)以解耦，避免所有表同步抖动
			_round_noise[id] = amp * sin(float(r) * freq + float(idx) * 1.7)
		idx += 1


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


## 生成并显示本轮四份专家简报，连接深度诊断信号
func _build_briefings(r: int) -> void:
	for c in _briefing_row.get_children():
		c.queue_free()
	for b in BriefingSystem.generate(r):
		# 教学战役：过滤不可用专家
		var eid: String = b.get("expert_id", "")
		if not TutorialCampaign.should_show_expert(eid):
			continue

		var card: BriefingCard = BRIEFING_SCENE.instantiate()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_briefing_row.add_child(card)
		card.setup(b)
		card.deep_diagnose_requested.connect(_on_deep_diagnose)


## 深度诊断（T2.2）：消耗经费，弹出该专家负责仪表近3轮趋势 + 专家解读。
## 不告知玩家故障真假，只给趋势原始数据和语气解读。
func _on_deep_diagnose(expert_id: String) -> void:
	var cost: int = int(DataManager.get_balance().get("deep_diagnose", {}).get("cost", 10))
	if GameState.budget_remaining < cost:
		return
	GameState.budget_remaining -= cost
	GameState.budget_changed.emit(GameState.budget_remaining, GameState.round_allocation)
	_rebuild_pool()

	var ex: Dictionary = DataManager.get_experts().get(expert_id, {})
	var dg: String = ex.get("direct_gauge", "")
	var expert_name: String = ex.get("name", expert_id)
	var lookback: int = int(DataManager.get_balance().get("deep_diagnose", {}).get("lookback", 3))

	# 收集历史读数
	var hist: Array = []
	for entry in GameState.run_log:
		var gs: Dictionary = (entry as Dictionary).get("gauges", {})
		if gs.has(dg):
			hist.append({"round": int((entry as Dictionary).get("round", 0)), "value": float(gs[dg])})
	hist = hist.slice(maxi(0, hist.size() - lookback))

	# 生成解读文本（据趋势方向，不判定根因）
	var trend_text: String = _build_trend_interpretation(expert_id, dg, hist)
	var gauge_label: String = dg
	var rounds_cfg: Variant = DataManager.get_config("rounds")
	if rounds_cfg is Dictionary:
		gauge_label = ((rounds_cfg as Dictionary).get("gauges", {}) as Dictionary).get(dg, {}).get("label", dg)

	var lines: String = "[b]深度诊断：%s · %s[/b]　[color=#8893a5](已扣 ¥%d)[/color]\n" % [expert_name, gauge_label, cost]
	for h in hist:
		lines += "  第 %d 轮：%.2f\n" % [(h as Dictionary)["round"], float((h as Dictionary)["value"])]
	lines += "[color=#f5c63f]%s 说：%s[/color]" % [expert_name, trend_text]

	var tag: PopupTag = POPUP_SCENE.instantiate()
	add_child(tag)
	tag.setup("深度诊断", lines)
	tag.position = Vector2(660.0, 120.0)
	_popups["deep_" + expert_id] = tag


## 据趋势方向生成专家口吻解读（不判定真假）
func _build_trend_interpretation(expert_id: String, _dg: String, hist: Array) -> String:
	var ex: Dictionary = DataManager.get_experts().get(expert_id, {})
	var personality: String = ex.get("personality", "")
	if hist.size() < 2:
		return "历史数据不足，暂无趋势判断。"
	var first: float = float((hist[0] as Dictionary)["value"])
	var last: float = float((hist[-1] as Dictionary)["value"])
	var rising: bool = last > first * 1.02
	var falling: bool = last < first * 0.98
	match personality:
		"conservative":
			if falling:  return "数值在走低，不容忽视，建议保守处置。"
			elif rising: return "数值偏高，有些担心，先观察看看。"
			else:        return "趋势基本稳定，暂无异常迹象。"
		"aggressive":
			if rising:  return "确实往上走，但在我预期范围内，不必过虑。"
			elif falling: return "偏低，我觉得系统还能承受，先不急。"
			else:        return "数据很稳，我这边没问题。"
		"pessimistic":
			if falling: return "一直在掉！这个趋势让我很担心，必须处置。"
			elif rising: return "往上走……说不准是不是坏事，先做好最坏打算。"
			else:        return "勉强稳着，但随时可能变，不敢大意。"
		_:  # idealistic
			if rising:  return "参数升高，约束算法需要关注，值得投入优化。"
			elif falling: return "下降趋势，理论上算法可以补偿，但幅度要控制。"
			else:        return "总体平稳，控制系统运行良好。"




## 锁定预览
func _show_lock_preview(r: int) -> void:
	var prediction: Dictionary = FusionEngine.predict_with_extra("", 0)
	var preview: LockPreviewPanel = LOCK_PREVIEW_SCENE.instantiate()
	add_child(preview)
	preview.setup(GameState.round_allocation.duplicate(), prediction, "第%d 轮" % r)
	preview.confirmed.connect(func() -> void:
		preview.queue_free()
		_do_submit()
	)
	preview.canceled.connect(func() -> void:
		preview.queue_free()
	)


## 玩家点"提交本轮"：先做逻辑一致性提示（仅提醒不评判），确认后再真正提交。
func _on_submit() -> void:
	var r: int = GameState.current_round
	if _consistency_confirmed_round != r and _is_inconsistent(r):
		_prompt_consistency(r)
		return
	_show_lock_preview(r)


## 分配方向与本轮最强表象明显矛盾时返回 true（零投修复部位、却在他处重投）
func _is_inconsistent(r: int) -> bool:
	var cfg: Dictionary = DataManager.get_balance().get("consistency_check", {})
	var min_dev: float = float(cfg.get("min_indicated_deviation", 0.10))
	var ratio: float = float(cfg.get("heavy_elsewhere_ratio", 0.5))
	var causes: Dictionary = DataManager.get_faults().get("root_causes", {})
	var indicated_part: String = ""
	var max_dev: float = 0.0
	for s in FaultTree.round_symptoms(r):
		var d: float = absf(float((s as Dictionary).get("deviation", 0.0)))
		if d > max_dev:
			max_dev = d
			indicated_part = (causes.get((s as Dictionary).get("cause", ""), {}) as Dictionary).get("fix_part", "")
	if indicated_part == "" or max_dev < min_dev:
		return false
	if int(GameState.round_allocation.get(indicated_part, 0)) > 0:
		return false
	# indicated_part 零投入，故本轮已花经费全在他处
	var elsewhere: int = GameState.total_budget - GameState.budget_remaining
	return float(elsewhere) >= ratio * float(GameState.total_budget)


## 温和的一致性确认弹窗（不评判对错，可继续）
func _prompt_consistency(r: int) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "逻辑一致性提示"
	dlg.dialog_text = "你的分配方向与你关注的故障似乎不一致，是否确认提交本轮？"
	dlg.ok_button_text = "确认提交"
	dlg.get_cancel_button().text = "返回调整"
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		_consistency_confirmed_round = r
		dlg.queue_free()
		_show_lock_preview(r)
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered()


## 提交本轮：识别判定 → 信任度更新 → 不可逆损伤累积 → 稳定度历史 → 记录 → 推进/结束
func _do_submit() -> void:
	var r: int = GameState.current_round
	# 教学战役：提交前触发步骤
	TutorialCampaign.on_before_submit(r)

	var newly: Array = FaultTree.evaluate_round(r)
	# 信任度博弈：据本轮对症投入情况更新各专家信任度
	BriefingSystem.update_trust(r)
	# 不可逆损伤：故障部位投入严重不足时累积
	_accumulate_damage(r)
	# 稳定度历史：记录本轮最终值，检查连续下降
	GameState.stability_history.append(float(_actual["stability"]))
	var degraded: bool = _check_stability_degradation()
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
	if degraded:
		feedback += "　[color=#e09040]⚠ 约束稳定度连续下降——内生风险累积中。[/color]"

	if GameState.is_final_round():
		_finish(feedback)
	else:
		# 教学战役：提交后触发步骤
		TutorialCampaign.on_after_submit(r)

		AudioManager.play("round_start")
		_start_round(r + 1)
		_info.text += "　" + feedback


## 各故障部位投入严重不足时累积不可逆损伤（内生后果，仅标准模式也生效）
func _accumulate_damage(r: int) -> void:
	var dcfg: Dictionary = DataManager.get_balance().get("irreversible_damage", {})
	var insuf_ratio: float = float(dcfg.get("insufficient_ratio", 0.12))
	var step: float = float(dcfg.get("damage_step", 0.5))
	var max_lvl: float = float(dcfg.get("max_level", 2.0))
	var threshold: float = insuf_ratio * float(GameState.total_budget)
	var causes: Dictionary = DataManager.get_faults().get("root_causes", {})
	for c in FaultTree.round_active_causes(r):
		var part: String = (causes.get(c, {}) as Dictionary).get("fix_part", "")
		if part == "":
			continue
		if float(GameState.round_allocation.get(part, 0)) < threshold:
			GameState.irreversible_damage[part] = \
				clampf(float(GameState.irreversible_damage.get(part, 0.0)) + step, 0.0, max_lvl)


## 稳定度历史连续两轮下降判定（需要至少3个历史值）
func _check_stability_degradation() -> bool:
	var h: Array = GameState.stability_history
	return h.size() >= 3 and float(h[-1]) < float(h[-2]) and float(h[-2]) < float(h[-3])


## 末轮结束：判定结局矩阵，解锁成就，切换到结局面板
func _finish(_last_feedback: String) -> void:
	_btn_submit.disabled = true
	GameState.set_metrics(_actual["q"], _actual["stability"], _actual["fuel"])
	var key: String = EndingResolver.build_key(
		float(_actual["q"]), GameState.identified_causes.size()
	)
	SaveManager.unlock_achievement(key)
	# 行为多样性成就：据本局状态结算并解锁，记录供结局面板展示
	GameState.last_session_achievements = GameState.evaluate_achievements()
	for aid in GameState.last_session_achievements:
		SaveManager.unlock_achievement(aid)
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
	var stability: float = float(pred["stability"])
	if _plasma:
		_plasma.set_state(stability)
	# 实时托卡马克档位 + 破裂报警联动
	if _tokamak:
		var disrupting: bool = _tokamak.update_stability(stability, _disrupt_threshold)
		_set_alarm(disrupting)


## 刷新全部仪表：物理仪表按故障残余偏移，Q值/稳定度按结算指标。
## 额外叠加：① 总工/挑战模式确定性周期噪声（_round_noise），② 低信任专家的直接仪表抖动，③ 故障链同步标记。
func _refresh_gauges() -> void:
	var r: int = GameState.current_round
	# 故障链激活的次因仪表集合（用于显示"链路同步"角标）
	var chain_gauges: Dictionary = {}
	for ch in FaultTree.active_chains(r):
		var sg: String = (ch as Dictionary).get("secondary_gauge", "")
		if sg != "":
			chain_gauges[sg] = true
	# 低信任专家→其 direct_gauge 叠加额外抖动
	var trust_jitter: Dictionary = {}
	var tcfg: Dictionary = DataManager.get_balance().get("expert_trust", {})
	var jitter_thr: float = float(tcfg.get("jitter_trust_threshold", 0.5))
	var jitter_amp: float = float(tcfg.get("jitter_amp", 0.02))
	var jitter_freq: float = float(tcfg.get("jitter_freq", 1.3))
	for eid in DataManager.get_experts():
		var trust: float = GameState.get_trust(eid)
		if trust < jitter_thr:
			var dg: String = (DataManager.get_experts()[eid] as Dictionary).get("direct_gauge", "")
			if dg != "":
				var amplitude: float = jitter_amp * (1.0 - trust)
				trust_jitter[dg] = float(trust_jitter.get(dg, 0.0)) + amplitude * sin(float(r) * jitter_freq + float(eid.hash()) * 0.7)

	for id in _gauges:
		var gauge := _gauges[id] as Gauge
		if id == "q_value":
			gauge.set_reading(float(_actual["q"]))
		elif id == "stability":
			gauge.set_reading(float(_actual["stability"]) * 100.0)
		else:
			var reading: float = FaultTree.gauge_reading(r, id, float(_gauge_base.get(id, 0.0)))
			reading *= (1.0 + float(_round_noise.get(id, 0.0)))
			reading *= (1.0 + float(trust_jitter.get(id, 0.0)))
			gauge.set_reading(reading)
		# 故障链同步标记：每帧重算（修复主因后可立即清除"⇌链路"角标）
		gauge.set_chain_linked(chain_gauges.has(id))


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



# ---------------------------------------------------------------------------
# 教学战役引导提示
# ---------------------------------------------------------------------------

func _on_tutorial_hint(step: Dictionary) -> void:
	var msg: String = step.get("message", "")
	if msg != "":
		_info.text = "[color=#2bd6ff][b][font_size=18]【教学引导】[/font_size][/b][/color]\n" + msg
	# 暂停游戏（教学需要）
	if bool(step.get("pause_game", false)):
		get_viewport().set_input_as_handled()
	# 高亮目标（部位/按钮/仪表）
	var highlight: String = step.get("highlight", "")
	if highlight != "":
		_highlight_target(highlight)

func _on_tutorial_hint_cleared() -> void:
	TutorialCampaign.clear_hint()

func _highlight_target(target: String) -> void:
	# 仪表高亮
	if target.begins_with("gauge_"):
		var gauge_id: String = target.trim_prefix("gauge_")
		if _gauges.has(gauge_id):
			_gauges[gauge_id].set_highlight(true)
	# 部位高亮
	elif target.begins_with("zone_"):
		var part_id: String = target.trim_prefix("zone_")
		for zone in _zones:
			if zone.part_id == part_id:
				zone.set_highlight(true)
	# 按钮高亮
	elif target == "btn_log":
		_btn_log.modulate = Color(1.0, 1.0, 0.5, 1.0)
	

func _on_back() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
