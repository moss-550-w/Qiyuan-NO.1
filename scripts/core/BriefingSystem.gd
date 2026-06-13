extends RefCounted
class_name BriefingSystem
## BriefingSystem —— 专家简报生成与信任度博弈（纯函数式）
##
## 新模型(信任度→情报精度，专家不说谎)：
##   - 信任度 ≥ precise_threshold → 采用 precise 简报（窄区间/确定语气），便于与仪表交叉核对；
##     否则采用 vague 简报（模糊/含糊），需玩家多方拼合判断。
##   - 两版均为真实情况的不同粒度表述，不存在隐瞒/夸大。
##   - 信任度变化：玩家在某专家负责部位"对症投入"(该部位本轮确有故障且投入达比例) → 信任 +；
##     该部位有故障却被无视 → 信任 −。低信任仅降低信息质量，不会令专家主动造假。
##
## 专家信息差：每位专家只精确掌握 direct_gauge，对他部位仅间接推断（体现在文案中）。

## 专家展示顺序
const EXPERT_ORDER := ["magnet_eng", "wall_eng", "tritium_eng", "plasma_eng"]


## 生成某轮四份简报，返回 Array[Dictionary]
static func generate(round_index: int) -> Array:
	var result: Array = []
	var experts: Dictionary = DataManager.get_experts()
	var briefings: Variant = DataManager.get_config("briefings")
	var round_briefs: Dictionary = {}
	if briefings is Dictionary:
		round_briefs = (briefings as Dictionary).get(str(round_index), {})

	var threshold: float = float(DataManager.get_balance().get("expert_trust", {}).get("precise_threshold", 0.5))

	for eid in EXPERT_ORDER:
		var ex: Dictionary = experts.get(eid, {})
		var brief: Dictionary = round_briefs.get(eid, {})
		var trust: float = GameState.get_trust(eid)
		var precise: bool = trust >= threshold
		var text: String = brief.get("precise" if precise else "vague", brief.get("precise", ""))

		result.append({
			"expert_id": eid,
			"name": ex.get("name", eid),
			"title": ex.get("title", ""),
			"personality": ex.get("personality", ""),
			"personality_label": ex.get("personality_label", ""),
			"avatar": ex.get("avatar", ""),
			"direct_gauge": ex.get("direct_gauge", ""),
			"text": text,
			"trust": trust,
			"precise": precise,
			"confidence_label": "数据较确切" if precise else "数据模糊",
		})
	return result


## 据本轮"对症投入"情况更新各专家信任度（有副作用，玩家提交本轮时调用）。
## 对每位专家：若其负责部位本轮确有故障，玩家达比例投入→信任+，被无视→信任−；
## 无故障则不变。plasma_control 无对应根因，信任保持。
static func update_trust(round_index: int) -> void:
	var experts: Dictionary = DataManager.get_experts()
	var tcfg: Dictionary = DataManager.get_balance().get("expert_trust", {})
	var gain: float = float(tcfg.get("trust_gain", 0.15))
	var loss: float = float(tcfg.get("trust_loss", 0.2))
	var heed_ratio: float = float(tcfg.get("invest_heed_ratio", 0.1))
	var heed_amount: float = heed_ratio * float(GameState.total_budget)

	var active: Array = FaultTree.round_active_causes(round_index)
	var causes: Dictionary = DataManager.get_faults().get("root_causes", {})

	for eid in experts:
		var part: String = (experts[eid] as Dictionary).get("bias_target", "")
		if part == "":
			continue
		# 该专家负责部位本轮是否确有故障
		var part_faulty: bool = false
		for c in active:
			if (causes.get(c, {}) as Dictionary).get("fix_part", "") == part:
				part_faulty = true
				break
		if not part_faulty:
			continue
		var invested: float = float(GameState.round_allocation.get(part, 0))
		if invested >= heed_amount:
			GameState.adjust_trust(eid, gain)
		else:
			GameState.adjust_trust(eid, -loss)
