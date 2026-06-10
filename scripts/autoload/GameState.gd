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
signal game_over(ending_key: String)

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

## 历史运行日志（总工模式查阅）：每条 {round, gauge, value, note}
var run_log: Array = []


func _ready() -> void:
	reset()


## 重置为新一局初始状态
func reset(diff: String = "novice") -> void:
	difficulty = diff
	current_round = 0
	q_value = 1.0
	stability = 1.0
	fuel_ratio = 1.0

	var diff_cfg := DataManager.get_difficulty(diff)
	total_budget = int(diff_cfg.get("total_budget", 100))
	budget_remaining = total_budget

	round_allocation = {}
	cumulative_allocation = {}
	for p in PARTS:
		round_allocation[p] = 0
		cumulative_allocation[p] = 0

	identified_causes = []
	run_log = []


## 进入下一轮（清空本轮分配，恢复经费）
func start_round(index: int) -> void:
	current_round = index
	budget_remaining = total_budget
	round_delayed = false
	for p in PARTS:
		round_allocation[p] = 0
	round_changed.emit(index)
	budget_changed.emit(budget_remaining, round_allocation)


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
	metrics_changed.emit(q_value, stability, fuel_ratio)


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
	return current_round >= TOTAL_ROUNDS


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
		"run_log": run_log,
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
	var causes: Array = d.get("identified_causes", [])
	identified_causes.assign(causes)
	run_log = d.get("run_log", [])
