extends RefCounted
class_name FaultTree
## FaultTree —— 故障树推演与根因识别（纯函数式）
##
## 职责：把 faults.json 的"根因 → 每轮表象(symptom)"转换为：
##   1. 仪表读数偏移（gauge_reading）：随玩家在正确部位投入修复而回归正常。
##   2. 指标 baseline 惩罚（metric_offsets）：未修复根因持续拉低 Q/稳定度/燃料。
##   3. 根因识别评定（evaluate_round）：在正确部位投入达阈值即视为识破并处置。
##
## 所有读取分配的函数都接受可选 alloc 参数（默认 GameState.round_allocation），
## 以便悬停预测时传入"假想分配"复用同一套逻辑。无副作用，evaluate_round 除外。


## 取某轮的配置块
static func round_data(round_index: int) -> Dictionary:
	var rounds: Array = DataManager.get_faults().get("rounds", [])
	for r in rounds:
		if int((r as Dictionary).get("round", -1)) == round_index:
			return r
	return {}


## 某轮的表象列表
static func round_symptoms(round_index: int) -> Array:
	return round_data(round_index).get("symptoms", [])


## 某轮涉及的根因 id（去重）
static func round_active_causes(round_index: int) -> Array:
	var causes: Array = []
	for s in round_symptoms(round_index):
		var c: String = (s as Dictionary).get("cause", "")
		if c != "" and not causes.has(c):
			causes.append(c)
	return causes


## 某根因的修复进度 0~1 = 正确部位投入 / 修复阈值
static func repair_ratio(cause_id: String, alloc: Variant = null) -> float:
	if alloc == null:
		alloc = GameState.round_allocation
	var rc: Dictionary = DataManager.get_faults().get("root_causes", {}).get(cause_id, {})
	var fix_part: String = rc.get("fix_part", "")
	var threshold: float = float(rc.get("fix_threshold", 35))
	if threshold <= 0.0 or fix_part == "":
		return 0.0
	var invest: float = float((alloc as Dictionary).get(fix_part, 0))
	return clampf(invest / threshold, 0.0, 1.0)


## 某根因本轮的"超额投入减免"系数（0,1]：上一轮在其修复部位超额投入则 <1，否则 1。
static func bonus_factor(cause_id: String) -> float:
	var rc: Dictionary = DataManager.get_faults().get("root_causes", {}).get(cause_id, {})
	var fix_part: String = rc.get("fix_part", "")
	if fix_part == "" or not GameState.over_invest_bonus(fix_part):
		return 1.0
	var relief: float = float(DataManager.get_balance().get("over_invest", {}).get("bonus_relief", 0.05))
	return clampf(1.0 - relief, 0.0, 1.0)


## 某根因因"不可逆损伤"被放大的强度系数（≥1）：其修复部位损伤越深，故障越强。
static func damage_factor(cause_id: String) -> float:
	var rc: Dictionary = DataManager.get_faults().get("root_causes", {}).get(cause_id, {})
	var fix_part: String = rc.get("fix_part", "")
	if fix_part == "":
		return 1.0
	var dmg: float = GameState.get_damage(fix_part)
	if dmg <= 0.0:
		return 1.0
	var per: float = float(DataManager.get_balance().get("irreversible_damage", {}).get("strength_per_level", 0.15))
	return 1.0 + per * dmg


## 综合强度系数 = 超额减免 × 不可逆损伤放大
static func strength_factor(cause_id: String) -> float:
	return bonus_factor(cause_id) * damage_factor(cause_id)


## 本轮已激活的故障链（round ≥ trigger_round 且主因本轮在场）
static func active_chains(round_index: int) -> Array:
	var result: Array = []
	var active: Array = round_active_causes(round_index)
	for ch in DataManager.get_faults().get("fault_chains", []):
		var cd: Dictionary = ch
		if round_index >= int(cd.get("trigger_round", 99)) and active.has(cd.get("primary", "")):
			result.append(cd)
	return result


## 故障链对某仪表的额外耦合偏移（次因联动）
static func chain_gauge_extra(round_index: int, gauge_id: String, alloc: Variant = null) -> float:
	var extra: float = 0.0
	var def_coupling: float = float(DataManager.get_balance().get("fault_chain", {}).get("default_coupling", 0.6))
	for ch in active_chains(round_index):
		var cd: Dictionary = ch
		if cd.get("secondary_gauge", "") != gauge_id:
			continue
		# 次因联动强度 = 主因残余强度 × coupling
		var primary: String = cd.get("primary", "")
		var coupling: float = float(cd.get("coupling", def_coupling))
		# 主因在本轮表象中的残余deviation之和（无需关联修复阈值，只看其真实残余）
		var primary_residual: float = 0.0
		for s in round_symptoms(round_index):
			var sd: Dictionary = s
			if sd.get("cause", "") == primary:
				var rep: float = repair_ratio(primary, alloc)
				primary_residual += absf(float(sd.get("deviation", 0.0))) * (1.0 - rep)
		# 次因偏移方向由链定义
		var direction: float = sign(float(cd.get("secondary_deviation_sign", 1.0)))
		extra += direction * primary_residual * coupling
	return extra


## 仪表读数：base * (1 + 残余 deviation + 链耦合偏移)，含综合强度系数（减免×损伤）
static func gauge_reading(round_index: int, gauge_id: String, base: float, alloc: Variant = null) -> float:
	if round_index <= 0:
		return base
	var dev_sum: float = 0.0
	for s in round_symptoms(round_index):
		var sd: Dictionary = s
		if sd.get("gauge", "") == gauge_id:
			var cause: String = sd.get("cause", "")
			var repair: float = repair_ratio(cause, alloc)
			dev_sum += float(sd.get("deviation", 0.0)) * (1.0 - repair) * strength_factor(cause)
	dev_sum += chain_gauge_extra(round_index, gauge_id, alloc)
	return base * (1.0 + dev_sum)


## 故障对核心指标的残余惩罚 {q, stability, fuel}（均 ≤ 0）
static func metric_offsets(round_index: int, alloc: Variant = null) -> Dictionary:
	var off: Dictionary = {"q": 0.0, "stability": 0.0, "fuel": 0.0}
	if round_index <= 0:
		return off
	var impact: Dictionary = DataManager.get_balance().get("fault_impact", {})
	var ref_dev: float = float(impact.get("reference_deviation", 0.10))
	if ref_dev <= 0.0:
		ref_dev = 0.10
	for s in round_symptoms(round_index):
		var sd: Dictionary = s
		var cause: String = sd.get("cause", "")
		var imp: Dictionary = impact.get(cause, {})
		if imp.is_empty():
			continue
		var metric: String = imp.get("metric", "q")
		var max_pen: float = float(imp.get("max_penalty", 0.1))
		var repair: float = repair_ratio(cause, alloc)
		var scale: float = absf(float(sd.get("deviation", 0.0))) / ref_dev
		off[metric] = float(off[metric]) - max_pen * (1.0 - repair) * scale * strength_factor(cause)
	return off


## 本轮未修复（修复进度 < 1）的根因数量
static func unrepaired_count(round_index: int, alloc: Variant = null) -> int:
	var n: int = 0
	for c in round_active_causes(round_index):
		if repair_ratio(c, alloc) < 1.0:
			n += 1
	return n


## 提交本轮：把"投入达阈值的本轮激活根因"标记为已识别，返回本次新识别列表。
## 注意：有副作用（写入 GameState），仅在玩家点"提交"时调用。
static func evaluate_round(round_index: int) -> Array:
	var newly: Array = []
	for c in round_active_causes(round_index):
		if repair_ratio(c) >= 1.0 and not GameState.identified_causes.has(c):
			GameState.mark_cause_identified(c)
			newly.append(c)
	return newly


## 取根因显示名
static func cause_name(cause_id: String) -> String:
	var rc: Dictionary = DataManager.get_faults().get("root_causes", {}).get(cause_id, {})
	return rc.get("name", cause_id)
