extends RefCounted
class_name BriefingSystem
## BriefingSystem —— 专家简报生成与立场过滤（纯函数式）
##
## 据 experts.json + briefings.json + 当前难度，为某轮生成四份带立场的简报。
## 动态判定：
##   - 隐瞒(is_hiding)：专家 hide_signal 中的根因正是本轮激活故障 → 他在淡化真问题。
##   - 夸大(is_exaggerating)：专家 exaggerate_signal 中的根因本轮并未激活 → 虚张声势。
## 新手模式高亮可疑卡片，并把 spin 中 {{suspect}} 片段染红；总工模式仅去标记。

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

	var active: Array = FaultTree.round_active_causes(round_index)
	var diff: Dictionary = DataManager.get_difficulty(GameState.difficulty)
	var highlight_mode: bool = bool(diff.get("highlight_suspect", false))

	for eid in EXPERT_ORDER:
		var ex: Dictionary = experts.get(eid, {})
		var brief: Dictionary = round_briefs.get(eid, {})
		var spin: String = brief.get("spin", brief.get("honest", ""))
		var suspect_point: String = brief.get("suspect_point", "")

		var is_hiding: bool = _intersects(ex.get("hide_signal", []), active)
		var is_exaggerating: bool = _check_exaggeration(ex.get("exaggerate_signal", []), active)
		var has_issue: bool = (is_hiding or is_exaggerating) and suspect_point != ""

		result.append({
			"expert_id": eid,
			"name": ex.get("name", eid),
			"title": ex.get("title", ""),
			"personality": ex.get("personality", ""),
			"personality_label": ex.get("personality_label", ""),
			"avatar": ex.get("avatar", ""),
			"text": _render(spin, highlight_mode),
			"is_hiding": is_hiding,
			"is_exaggerating": is_exaggerating,
			"suspect_point": suspect_point,
			"highlight": highlight_mode and has_issue,
		})
	return result


## 渲染 spin 文本：处理 {{suspect}} 标记
static func _render(spin: String, highlight: bool) -> String:
	if highlight:
		return spin.replace("{{suspect}}", "[color=#ff6b6b]").replace("{{/suspect}}", "[/color]")
	return spin.replace("{{suspect}}", "").replace("{{/suspect}}", "")


## signals 与本轮激活故障是否有交集
static func _intersects(signals: Array, active: Array) -> bool:
	for s in signals:
		if active.has(s):
			return true
	return false


## 夸大：声称的信号本轮并未激活（喊狼来了）
static func _check_exaggeration(exaggerate_signals: Array, active: Array) -> bool:
	if exaggerate_signals.is_empty():
		return false
	for s in exaggerate_signals:
		if not active.has(s):
			return true
	return false
