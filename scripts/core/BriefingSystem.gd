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
## 剧本(scenario)接入：
##   1. expert_roles 角色驱动精度——observer 恒模糊；secondary 需更高信任才精确；primary/无角色按信任阈值。
##   2. briefings_override 当前剧本专属台词优先，缺省回退基础 briefings.json。
##   3. 本剧本中所辖根因根本不激活的专家 → 给中性简报，避免陈述不存在的故障（守住“专家不说谎”不变量）。
static func generate(round_index: int) -> Array:
	var result: Array = []
	var experts: Dictionary = DataManager.get_experts()
	var briefings: Variant = DataManager.get_config("briefings")
	var base_briefs: Dictionary = {}
	var neutral: Dictionary = {}
	if briefings is Dictionary:
		base_briefs = (briefings as Dictionary).get(str(round_index), {})
		neutral = (briefings as Dictionary).get("_neutral", {})

	var tcfg: Dictionary = DataManager.get_balance().get("expert_trust", {})
	var threshold: float = float(tcfg.get("precise_threshold", 0.5))
	var secondary_penalty: float = float(tcfg.get("secondary_precise_penalty", 0.15))

	# 剧本上下文（教学/无剧本时为空，行为回退基础表）
	var scen: Dictionary = GameState.scenario_data
	var roles: Dictionary = scen.get("expert_roles", {})
	var override_all: Variant = scen.get("briefings_override", {})
	var override_briefs: Dictionary = {}
	if override_all is Dictionary:
		override_briefs = (override_all as Dictionary).get(str(round_index), {})

	for eid in EXPERT_ORDER:
		var ex: Dictionary = experts.get(eid, {})
		var trust: float = GameState.get_trust(eid)
		var role: String = (roles.get(eid, {}) as Dictionary).get("role", "")

		# 精度判定：旁观者恒模糊；次要专家阈值上浮；其余按信任阈值
		var precise: bool
		match role:
			"observer":
				precise = false
			"secondary":
				precise = trust >= (threshold + secondary_penalty)
			_:
				precise = trust >= threshold

		var key: String = "precise" if precise else "vague"
		var text: String = ""
		var ov: Dictionary = override_briefs.get(eid, {})
		if not ov.is_empty():
			# 剧本专属台词优先
			text = ov.get(key, ov.get("precise", ""))
		elif _expert_idle(eid, scen):
			# 本剧本该专家所辖无故障：给中性简报，不陈述不存在的故障
			var nb: Dictionary = neutral.get(eid, {})
			text = nb.get(key, nb.get("precise", _default_neutral()))
		else:
			var brief: Dictionary = base_briefs.get(eid, {})
			text = brief.get(key, brief.get("precise", ""))

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


## 该专家在当前剧本中所辖根因是否“整局都不激活”（用于给中性简报）。
## 无剧本、剧本未限定根因、或该专家无关联根因（如等离子体物理师）时返回 false，保持常规简报。
static func _expert_idle(expert_id: String, scen: Dictionary) -> bool:
	if scen.is_empty():
		return false
	var scen_causes: Array = scen.get("root_causes", [])
	if scen_causes.is_empty():
		return false
	var linked: String = _linked_cause(expert_id)
	if linked == "":
		return false
	return not scen_causes.has(linked)


## 据 faults.json 的 root_causes.linked_expert 反查某专家关联的根因 id（无则空串）
static func _linked_cause(expert_id: String) -> String:
	var causes: Dictionary = DataManager.get_faults().get("root_causes", {})
	for c in causes:
		if (causes[c] as Dictionary).get("linked_expert", "") == expert_id:
			return c
	return ""


## 中性简报兜底文案（briefings.json 缺 _neutral 时使用）
static func _default_neutral() -> String:
	return "我负责的子系统这几轮读数都在正常区间，没什么要紧的，钱先紧着别处。"


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
