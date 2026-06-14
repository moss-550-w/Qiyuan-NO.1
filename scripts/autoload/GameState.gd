extends Node
## GameState —— 全局运行态单例
##
## 持有一局游戏的实时状态：难度、轮次、Q值、稳定度、经费、根因识别情况、
## 各部位累计投入、历史日志。所有 core 模块通过本单例读写状态，视图层只读 +
## 监听信号刷新，不直接改字段。

## 装置四个可投资部位（与 DropZone 的 part_id 对应）
const PARTS := ["magnet_coil", "first_wall", "breeder_blanket", "plasma_control"]

## 三个根本原因 id（与 faults.json root_causes 对应）
const ROOT_CAUSES := ["magnet_psu_aging", "wall_microcrack", "tritium_pump_decay"]

const TOTAL_ROUNDS := 4

# --- 信号：状态变化时通知视图刷新 ---
signal round_changed(round_index: int)
signal metrics_changed(q_value: float, stability: float, fuel_ratio: float)
signal budget_changed(remaining: int, allocation: Dictionary)
signal root_cause_identified(cause_id: String)


# --- 局内状态 ---
var difficulty: String = "novice"
var current_round: int = 0           # 0 = 未开始；1..4 = 进行中
var q_value: float = 1.0
var stability: float = 1.0           # 0..1
var fuel_ratio: float = 1.0          # 燃料自持率 0..1

var total_budget: int = 100
var budget_remaining: int = 100
## 本轮各部位投入：part_id → 单位数
var round_allocation: Dictionary = {}
## 全局各部位累计投入：part_id → 单位数
var cumulative_allocation: Dictionary = {}

## 已识别并处置的根因 id 集合
var identified_causes: Array[String] = []

## 本轮是否决策延迟（限时耗尽自动提交），触发稳定度惩罚
var round_delayed: bool = false

## 上一轮"超额投入奖励"结果：part_id → bool（仅作用于当前轮，不跨轮累积）
var last_round_bonus: Dictionary = {}

## 专家信任度：expert_id → 0..1（影响其简报情报精度与负责仪表抖动）
var expert_trust: Dictionary = {}

## 各轮结算后的最终稳定度序列（用于"连续下降"内生后果判定）
var stability_history: Array = []

## 各部位累计不可逆损伤等级：part_id → float（投入长期不足时累积，抬高后续故障强度）
var irreversible_damage: Dictionary = {}

## 本局稳定度历史最低值（用于"烈火中永生"等成就判定）
var min_stability: float = 1.0

## 本局结算时解锁的行为成就 id（供结局面板展示）
var last_session_achievements: Array = []

## 历史运行日志（总工模式查阅）：每条 {round, gauge, value, note}
var run_log: Array = []

## 当前剧本 id（随机抽取）
var current_scenario: String = "default_alpha"
## 剧本配置缓存
var scenario_data: Dictionary = {}


func _ready() -> void:
	reset()


## 重置为新一局初始状态
func reset(diff: String = "novice") -> void:
	difficulty = diff
	current_round = 0
	q_value = 1.0
	stability = 1.0
	fuel_ratio = 1.0
	min_stability = 1.0

	var diff_cfg := DataManager.get_difficulty(diff)
	total_budget = int(diff_cfg.get("total_budget", 100))
	budget_remaining = total_budget

	round_allocation = {}
	cumulative_allocation = {}
	last_round_bonus = {}
	irreversible_damage = {}
	for p in PARTS:
		round_allocation[p] = 0
		cumulative_allocation[p] = 0
		last_round_bonus[p] = false
		irreversible_damage[p] = 0.0

	expert_trust = {}
	var trust_init: float = float(DataManager.get_balance().get("expert_trust", {}).get("initial", 0.6))
	for eid in DataManager.get_experts():
		expert_trust[eid] = trust_init
	# 剧本初始化
	_select_scenario()


	stability_history = []
	identified_causes = []
	last_session_achievements = []
	run_log = []


## 进入下一轮（先据上一轮投入结算超额奖励，再清空本轮分配、恢复经费）。
## settle_bonus=false 用于续档恢复：此时 round_allocation 已不可考，应保留存档中的 last_round_bonus。
func start_round(index: int, settle_bonus: bool = true) -> void:
	if settle_bonus:
		_settle_over_invest_bonus()
	current_round = index
	budget_remaining = total_budget
	round_delayed = false
	for p in PARTS:
		round_allocation[p] = 0
	round_changed.emit(index)
	budget_changed.emit(budget_remaining, round_allocation)


## 据"上一轮 round_allocation"结算超额投入奖励，写入 last_round_bonus（仅作用于即将开始的这一轮）。
## 在 round_allocation 被清零前调用。
func _settle_over_invest_bonus() -> void:
	var threshold: float = float(DataManager.get_balance().get("over_invest", {}).get("bonus_threshold", 50))
	for p in PARTS:
		last_round_bonus[p] = float(round_allocation.get(p, 0)) >= threshold


## 某部位本轮是否享有上一轮超额投入带来的故障减免
func over_invest_bonus(part_id: String) -> bool:
	return bool(last_round_bonus.get(part_id, false))


## 读取某专家信任度（缺省回退配置 initial）
func get_trust(expert_id: String) -> float:
	var init: float = float(DataManager.get_balance().get("expert_trust", {}).get("initial", 0.6))
	return float(expert_trust.get(expert_id, init))


## 调整某专家信任度（clamp 0..1）
func adjust_trust(expert_id: String, delta: float) -> void:
	expert_trust[expert_id] = clampf(get_trust(expert_id) + delta, 0.0, 1.0)


## 读取某部位不可逆损伤等级
func get_damage(part_id: String) -> float:
	return float(irreversible_damage.get(part_id, 0.0))


## 尝试向某部位投入 amount 单位经费，成功返回 true
func allocate(part_id: String, amount: int) -> bool:
	if not PARTS.has(part_id):
		push_warning("[GameState] 未知部位：%s" % part_id)
		return false
	if amount <= 0 or amount > budget_remaining:
		return false
	round_allocation[part_id] += amount
	cumulative_allocation[part_id] += amount
	budget_remaining -= amount
	budget_changed.emit(budget_remaining, round_allocation)
	return true


## 撤回某部位本轮的全部投入（拖回代币）
func withdraw(part_id: String, amount: int) -> bool:
	if not PARTS.has(part_id):
		return false
	var allocated: int = round_allocation.get(part_id, 0)
	amount = min(amount, allocated)
	if amount <= 0:
		return false
	round_allocation[part_id] -= amount
	cumulative_allocation[part_id] -= amount
	budget_remaining += amount
	budget_changed.emit(budget_remaining, round_allocation)
	return true


## 更新核心指标（由 FusionEngine 结算后调用）
func set_metrics(q: float, stab: float, fuel: float) -> void:
	q_value = q
	stability = clampf(stab, 0.0, 1.0)
	fuel_ratio = clampf(fuel, 0.0, 1.0)
	min_stability = minf(min_stability, stability)
	metrics_changed.emit(q_value, stability, fuel_ratio)


## 结算行为成就：据本局状态返回应解锁的成就 id 列表（纯判定，无副作用）。
## 与 achievements.json 的元数据对应；结局矩阵键不在此处。
func evaluate_achievements() -> Array:
	var unlocked: Array = []
	var balance: Dictionary = DataManager.get_balance()

	# 偏听则暗：某专家对应部位全程零投入，却仍点火（Q≥1）
	if q_value >= 1.0:
		var experts: Dictionary = DataManager.get_experts()
		for eid in experts:
			var part: String = (experts[eid] as Dictionary).get("bias_target", "")
			if part != "" and int(cumulative_allocation.get(part, 0)) == 0:
				unlocked.append("deaf_ear")
				break

	# 耦合猎手：某一轮一次识破≥2根因
	for e in run_log:
		if (e as Dictionary).get("identified", []).size() >= 2:
			unlocked.append("chain_hunter")
			break

	# 烈火中永生：稳定度曾跌破破裂阈值，最终回到安全线之上
	var dis: float = float(balance.get("stability", {}).get("disruption_threshold", 0.4))
	if min_stability < dis and stability >= 0.7:
		unlocked.append("phoenix")

	# 预算狂人：总投入 < 80% 标准线（每轮总额×轮数），且点火
	var spent: int = 0
	for p in PARTS:
		spent += int(cumulative_allocation.get(p, 0))
	var standard: float = float(total_budget * TOTAL_ROUNDS)
	if q_value >= 1.0 and standard > 0.0 and float(spent) < 0.8 * standard:
		unlocked.append("budget_madman")

	return unlocked


## 标记某根因已识别处置
func mark_cause_identified(cause_id: String) -> void:
	if ROOT_CAUSES.has(cause_id) and not identified_causes.has(cause_id):
		identified_causes.append(cause_id)
		root_cause_identified.emit(cause_id)


## 追加一条历史日志
func add_log(entry: Dictionary) -> void:
	run_log.append(entry)


## 是否已是最后一轮
func is_final_round() -> bool:
	var max_r: int
	if TutorialCampaign.is_tutorial_active():
		max_r = TutorialCampaign.get_round_count()
	else:
		max_r = TOTAL_ROUNDS
	return current_round >= max_r

func _select_scenario() -> void:
	var configs: Variant = DataManager.get_config("scenarios")
	if not (configs is Dictionary):
		current_scenario = "default_alpha"
		scenario_data = {}
		return
	var list: Array = (configs as Dictionary).get("scenarios", [])
	if list.is_empty():
		current_scenario = "default_alpha"
		scenario_data = {}
		return
	var idx: int = randi() % list.size()
	var chosen: Dictionary = list[idx] as Dictionary
	current_scenario = chosen.get("id", "default_alpha")
	scenario_data = chosen.duplicate(true)
	print("[GameState] 抽取剧本: ", current_scenario)

## 获取当前剧本的 gauge_offset
func get_scenario_gauge_offset() -> Dictionary:
	return scenario_data.get("gauge_offset", {})

## 获取当前剧本的 expert_roles
func get_scenario_expert_roles() -> Dictionary:
	return scenario_data.get("expert_roles", {})

## 获取当前剧本的 chains 列表
func get_scenario_chains() -> Array:
	return scenario_data.get("chains", [])

## 获取当前剧本名称
func get_scenario_name() -> String:
	return scenario_data.get("name", current_scenario)
## 导出当前状态为可存档字典
func to_save_dict() -> Dictionary:
	return {
		"difficulty": difficulty,
		"current_round": current_round,
		"q_value": q_value,
		"stability": stability,
		"fuel_ratio": fuel_ratio,
		"budget_remaining": budget_remaining,
		"cumulative_allocation": cumulative_allocation,
		"identified_causes": identified_causes,
		"last_round_bonus": last_round_bonus,
		"min_stability": min_stability,
		"expert_trust": expert_trust,
		"stability_history": stability_history,
		"irreversible_damage": irreversible_damage,
		"run_log": run_log,
		"current_scenario": current_scenario,
		"scenario_data": scenario_data,
	}


## 从存档字典恢复状态
func from_save_dict(d: Dictionary) -> void:
	difficulty = d.get("difficulty", "novice")
	total_budget = int(DataManager.get_difficulty(difficulty).get("total_budget", 100))
	current_round = int(d.get("current_round", 0))
	q_value = float(d.get("q_value", 1.0))
	stability = float(d.get("stability", 1.0))
	fuel_ratio = float(d.get("fuel_ratio", 1.0))
	budget_remaining = int(d.get("budget_remaining", total_budget))
	cumulative_allocation = d.get("cumulative_allocation", {})
	last_round_bonus = d.get("last_round_bonus", {})
	for p in PARTS:
		if not last_round_bonus.has(p):
			last_round_bonus[p] = false
	min_stability = float(d.get("min_stability", 1.0))
	expert_trust = d.get("expert_trust", {})
	var trust_init: float = float(DataManager.get_balance().get("expert_trust", {}).get("initial", 0.6))
	for eid in DataManager.get_experts():
		if not expert_trust.has(eid):
			expert_trust[eid] = trust_init
	stability_history = d.get("stability_history", [])
	irreversible_damage = d.get("irreversible_damage", {})
	for p in PARTS:
		if not irreversible_damage.has(p):
			irreversible_damage[p] = 0.0
	var causes: Array = d.get("identified_causes", [])
	identified_causes.assign(causes)
	run_log = d.get("run_log", [])
	current_scenario = d.get("current_scenario", "default_alpha")
	scenario_data = d.get("scenario_data", {})
