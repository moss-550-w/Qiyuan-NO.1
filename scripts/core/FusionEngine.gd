extends RefCounted
class_name FusionEngine
## FusionEngine —— 核心计算引擎（纯函数式）
##
## 职责：把"各部位经费投入"换算为核心指标（Q值 / 稳定度 / 燃料自持率）。
## 全部为 static 纯函数，无副作用，便于在两个场景复用：
##   1. 落定结算：用 GameState.round_allocation 算实际指标。
##   2. 悬停预测：用 allocation + 假想增量 算预测指标，回显给玩家。
##
## 所有系数取自 balance.json，禁止在此硬编码数值。
## 故障对 baseline 的拉低通过 fault_offsets 注入（D3 由 FaultTree 提供）。


## 单部位经费效果：边际递减 gain = k * (1 - exp(-invest/tau))，取值约 0~k。
static func part_effect(part_id: String, invest: float, balance: Dictionary) -> float:
	var effects: Dictionary = balance.get("budget_effect", {})
	var cfg: Dictionary = effects.get(part_id, {})
	var k: float = float(cfg.get("k", 1.0))
	var tau: float = float(cfg.get("tau", 30.0))
	if tau <= 0.0:
		return k
	return k * (1.0 - exp(-invest / tau))


## 预测核心指标。
## allocation:     part_id → 投入单位数
## unfixed_causes: 尚未修复的根因数量（D2 无故障时传 0）
## delayed:        本轮是否决策延迟（超时），触发稳定度惩罚
## fault_offsets:  故障对 {q,stability,fuel} 的 baseline 偏移（D2 传空字典）
## 返回 {"q":float, "stability":float, "fuel":float}（稳定度/燃料已 clamp 到 0~1）
static func predict(
	allocation: Dictionary,
	unfixed_causes: int,
	delayed: bool,
	balance: Dictionary,
	fault_offsets: Dictionary = {}
) -> Dictionary:
	var e_magnet: float = part_effect("magnet_coil", float(allocation.get("magnet_coil", 0)), balance)
	var e_wall: float = part_effect("first_wall", float(allocation.get("first_wall", 0)), balance)
	var e_blanket: float = part_effect("breeder_blanket", float(allocation.get("breeder_blanket", 0)), balance)
	var e_control: float = part_effect("plasma_control", float(allocation.get("plasma_control", 0)), balance)

	# --- Q 值：磁体 + 控制驱动，未修根因扣分 ---
	var qc: Dictionary = balance.get("q_value", {})
	var q: float = float(qc.get("base", 1.0)) \
		+ float(qc.get("magnet_weight", 0.20)) * e_magnet \
		+ float(qc.get("control_weight", 0.10)) * e_control \
		- float(qc.get("unfixed_cause_penalty", 0.08)) * float(unfixed_causes) \
		+ float(fault_offsets.get("q", 0.0))

	# --- 稳定度：第一壁 + 控制驱动，延迟惩罚 ---
	var sc: Dictionary = balance.get("stability", {})
	var stability: float = float(sc.get("base", 0.9)) \
		+ float(sc.get("wall_weight", 0.15)) * e_wall \
		+ float(sc.get("control_weight", 0.10)) * e_control \
		+ float(fault_offsets.get("stability", 0.0))
	if delayed:
		stability -= float(sc.get("delay_penalty", 0.05))

	# --- 燃料自持率：氚增殖包层驱动 ---
	var fc: Dictionary = balance.get("fuel", {})
	var fuel: float = float(fc.get("base", 1.0)) \
		+ float(fc.get("blanket_weight", 0.15)) * e_blanket \
		+ float(fault_offsets.get("fuel", 0.0))

	return {
		"q": q,
		"stability": clampf(stability, 0.0, 1.0),
		"fuel": clampf(fuel, 0.0, 1.0),
	}


## 便捷预测：基于 GameState 当前局势，叠加一个假想增量（用于悬停预测）。
## extra_part / extra_amount 为悬停部位与拟投入量，传空串则等价于当前实际预测。
## 故障对指标的拉低由 FaultTree 按"假想分配后的修复进度"实时计算，全部走
## fault_offsets，因此 unfixed_causes 传 0，避免与故障惩罚双重扣减。
static func predict_with_extra(extra_part: String, extra_amount: int) -> Dictionary:
	var alloc: Dictionary = GameState.round_allocation.duplicate()
	if extra_part != "" and alloc.has(extra_part):
		alloc[extra_part] = int(alloc[extra_part]) + extra_amount
	var fault_offsets: Dictionary = FaultTree.metric_offsets(GameState.current_round, alloc)
	return predict(alloc, 0, GameState.round_delayed, DataManager.get_balance(), fault_offsets)
