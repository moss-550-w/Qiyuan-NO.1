extends RefCounted
class_name EndingResolver
## EndingResolver —— 2D 结局矩阵判定（纯函数式）
##
## 横轴 Q 值区间（阈值取自 balance.ending_thresholds）：
##   Qlt1 (<q_low) / Q1to11 (q_low~q_high) / Qgt11 (>q_high)
## 纵轴 识破根因数：root0 / root1 / root2 / root3
## 组合 3×4=12 个结局键，对应 endings.json 文案。

## Q 区间键（与 endings.json 的键前缀一致）
static func q_band_key(q_value: float) -> String:
	var th: Dictionary = DataManager.get_balance().get("ending_thresholds", {})
	var low: float = float(th.get("q_low", 1.0))
	var high: float = float(th.get("q_high", 1.1))
	if q_value < low:
		return "Qlt1"
	elif q_value <= high:
		return "Q1to11"
	return "Qgt11"


## Q 区间中文描述
static func q_band_label(q_value: float) -> String:
	var th: Dictionary = DataManager.get_balance().get("ending_thresholds", {})
	var low: float = float(th.get("q_low", 1.0))
	var high: float = float(th.get("q_high", 1.1))
	if q_value < low:
		return "Q < %.1f（未达临界点火）" % low
	elif q_value <= high:
		return "%.1f ≤ Q ≤ %.1f（临界点火）" % [low, high]
	return "Q > %.1f（高增益运行）" % high


## 拼装结局键
static func build_key(q_value: float, identified_count: int) -> String:
	return "%s_root%d" % [q_band_key(q_value), clampi(identified_count, 0, 3)]


## 完整判定，返回结局信息字典。隐藏结局由系统状态自然触发，优先于标准矩阵。
static func resolve(q_value: float, identified_count: int) -> Dictionary:
	var hidden: String = _check_hidden(q_value, identified_count)
	var key: String = hidden if hidden != "" else build_key(q_value, identified_count)
	var endings: Dictionary = DataManager.get_endings()
	var data: Dictionary = endings.get(key, {})
	return {
		"key": key,
		"title": data.get("title", "未知结局"),
		"summary": data.get("summary", "（缺少该结局文案：%s）" % key),
		"q_band_label": q_band_label(q_value),
		"q_value": q_value,
		"identified": clampi(identified_count, 0, 3),
		"hidden": hidden != "",
	}


## 隐藏结局判定：由本局系统状态自然触发，命中返回隐藏结局键，否则空串。
static func _check_hidden(q_value: float, identified_count: int) -> String:
	var bal: Dictionary = DataManager.get_balance()
	var dis: float = float(bal.get("stability", {}).get("disruption_threshold", 0.4))
	var max_dmg: float = float(bal.get("irreversible_damage", {}).get("max_level", 2.0))
	var q_high: float = float(bal.get("ending_thresholds", {}).get("q_high", 1.1))

	var worst_dmg: float = 0.0
	for p in GameState.PARTS:
		worst_dmg = maxf(worst_dmg, GameState.get_damage(p))

	# 熔毁：某部位长期无视致不可逆损伤累积至上限，且全程曾跌破破裂阈值
	if worst_dmg >= max_dmg and GameState.min_stability < dis:
		return "hidden_meltdown"

	# 完美值班：高增益点火 + 三根因全识破 + 零不可逆损伤 + 全程未破裂
	if q_value > q_high and identified_count >= 3 and worst_dmg <= 0.0 and GameState.min_stability >= dis:
		return "hidden_flawless"

	return ""
