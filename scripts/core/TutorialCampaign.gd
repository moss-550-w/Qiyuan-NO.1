extends Node

## TutorialCampaign —— 教学战役控制器（T3.3）
##
## 职责：
## 1. 加载 tutorial.json，管理三章解锁进度。
## 2. 启动教学章节时：覆盖 GameState 的轮次数、经费、可用部位/专家；向 FaultTree 注入教学剧本。
## 3. 通过信号驱动 UI 显示引导消息与高亮。
## 4. 进度持久化到 user://tutorial.cfg（独立于主存档/成就）。
##
## 使用方式：
##   - MainMenu 中点击「教学战役」→ 调用 TutorialCampaign.start_chapter(id)
##   - ControlRoom 在关键时机调用 on_trigger(trigger_name, context)
##   - ControlRoom 通过 should_show_part / should_show_expert 过滤 UI。

const SAVE_PATH := "user://tutorial.cfg"

signal hint_requested(step: Dictionary)
signal hint_cleared()
signal chapter_started(chapter_id: String)
signal chapter_completed(chapter_id: String)

## 全部章节配置（只读）
var _chapters: Array = []

## 持久进度：{ "completed": ["ch1_basics", ...], "max_unlocked": "ch2_tritium" }
var _progress: Dictionary = { "completed": [], "max_unlocked": "ch1_basics" }

## 运行态
var _active: bool = false
var _active_chapter: Dictionary = {}
var _current_step_index: int = -1
var _steps_triggered: Dictionary = {}  # step_key -> true，防止同一步重复触发

## 原始故障数据备份（用于退出教学时恢复 FaultTree）
var _original_faults: Dictionary = {}


func _ready() -> void:
	_load_config()
	_load_progress()
	# 监听 GameState 轮次变化，自动触发 on_round_start
	GameState.round_changed.connect(_on_gamestate_round_changed)


# ---------------------------------------------------------------------------
# 配置与进度
# ---------------------------------------------------------------------------

func _load_config() -> void:
	var cfg: Variant = DataManager.get_config("tutorial")
	if cfg is Dictionary:
		_chapters = (cfg as Dictionary).get("chapters", [])
	else:
		push_error("[TutorialCampaign] tutorial.json 未加载或格式错误")


func _load_progress() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) == OK and file.has_section("progress"):
		_progress["completed"] = file.get_value("progress", "completed", [])
		_progress["max_unlocked"] = file.get_value("progress", "max_unlocked", "ch1_basics")
	else:
		_progress = { "completed": [], "max_unlocked": "ch1_basics" }


func _save_progress() -> void:
	var file := ConfigFile.new()
	file.set_value("progress", "completed", _progress.get("completed", []))
	file.set_value("progress", "max_unlocked", _progress.get("max_unlocked", "ch1_basics"))
	var err := file.save(SAVE_PATH)
	if err != OK:
		push_error("[TutorialCampaign] 进度保存失败：%d" % err)


# ---------------------------------------------------------------------------
# 公共查询
# ---------------------------------------------------------------------------

func get_chapters() -> Array:
	return _chapters.duplicate()


func is_chapter_unlocked(chapter_id: String) -> bool:
	var max_unlocked: String = _progress.get("max_unlocked", "")
	# 默认解锁的章节直接开放
	for ch in _chapters:
		var cd: Dictionary = ch
		if cd.get("id", "") == chapter_id:
			var cond: String = cd.get("unlock_condition", "")
			if cond == "default":
				return true
			break
	# 否则检查是否 ≤ 当前最大解锁
	var idx_target: int = -1
	var idx_max: int = -1
	for i in range(_chapters.size()):
		if (_chapters[i] as Dictionary).get("id", "") == chapter_id:
			idx_target = i
		if (_chapters[i] as Dictionary).get("id", "") == max_unlocked:
			idx_max = i
	return idx_target >= 0 and idx_target <= idx_max


func is_chapter_completed(chapter_id: String) -> bool:
	var completed: Array = _progress.get("completed", [])
	return completed.has(chapter_id)


func is_tutorial_active() -> bool:
	return _active


func get_active_chapter() -> Dictionary:
	return _active_chapter.duplicate() if _active else {}


## 当前可用的引导步（若刚触发则返回，否则空字典）
func get_current_hint() -> Dictionary:
	if not _active or _current_step_index < 0:
		return {}
	var steps: Array = _active_chapter.get("steps", [])
	if _current_step_index >= steps.size():
		return {}
	return steps[_current_step_index] as Dictionary


## 清除当前引导（UI 调用，表示玩家已阅读）
func clear_hint() -> void:
	hint_cleared.emit()


# ---------------------------------------------------------------------------
# 部位 / 专家 可见性过滤
# ---------------------------------------------------------------------------

func should_show_part(part_id: String) -> bool:
	if not _active:
		return true
	var enabled: Array = _active_chapter.get("parts_enabled", [])
	return enabled.is_empty() or enabled.has(part_id)


func should_show_expert(expert_id: String) -> bool:
	if not _active:
		return true
	var enabled: Array = _active_chapter.get("experts_enabled", [])
	return enabled.is_empty() or enabled.has(expert_id)


## 教学章节的轮次数（可能少于标准 4 轮）
func get_round_count() -> int:
	if not _active:
		return GameState.TOTAL_ROUNDS
	return int(_active_chapter.get("round_count", GameState.TOTAL_ROUNDS))


## 教学章节的每轮经费
func get_budget_per_round() -> int:
	if not _active:
		return GameState.total_budget
	return int(_active_chapter.get("budget_per_round", GameState.total_budget))


## 教学难度覆盖（如无限时、无噪声）
func get_difficulty_overrides() -> Dictionary:
	if not _active:
		return {}
	return (_active_chapter.get("difficulty_overrides", {}) as Dictionary).duplicate()


# ---------------------------------------------------------------------------
# 启动 / 结束章节
# ---------------------------------------------------------------------------

func start_chapter(chapter_id: String) -> bool:
	if not is_chapter_unlocked(chapter_id):
		push_warning("[TutorialCampaign] 章节未解锁：%s" % chapter_id)
		return false

	var found: Dictionary = {}
	for ch in _chapters:
		if (ch as Dictionary).get("id", "") == chapter_id:
			found = ch
			break
	if found.is_empty():
		push_error("[TutorialCampaign] 章节不存在：%s" % chapter_id)
		return false

	_active = true
	_active_chapter = found.duplicate()
	_current_step_index = -1
	_steps_triggered.clear()

	# 备份原始 faults 并注入教学剧本
	_backup_and_inject_faults()

	# 重置 GameState：使用教学覆盖参数
	var diff_overrides: Dictionary = get_difficulty_overrides()
	# 先按 novice 重置，再由覆盖参数调整
	GameState.reset("novice")
	GameState.total_budget = get_budget_per_round()
	GameState.budget_remaining = GameState.total_budget
	# 清空剧本随机，使用教学固定剧本
	GameState.current_scenario = "tutorial_%s" % chapter_id
	GameState.scenario_data = {}

	chapter_started.emit(chapter_id)

	# 立即触发 chapter_start 步骤
	on_trigger("on_chapter_start", {})
	return true


func end_chapter() -> void:
	if not _active:
		return
	_restore_faults()
	_active = false
	_active_chapter = {}
	_current_step_index = -1
	_steps_triggered.clear()


func complete_chapter() -> void:
	if not _active:
		return
	var chapter_id: String = _active_chapter.get("id", "")

	# 标记完成
	var completed: Array = _progress.get("completed", [])
	if not completed.has(chapter_id):
		completed.append(chapter_id)

	# 尝试解锁下一章
	var next_id: String = _find_next_chapter_id(chapter_id)
	if next_id != "":
		_progress["max_unlocked"] = next_id

	_save_progress()
	chapter_completed.emit(chapter_id)

	# 触发 on_chapter_complete 步骤
	on_trigger("on_chapter_complete", {})

	end_chapter()


func _find_next_chapter_id(after_id: String) -> String:
	var found: bool = false
	for ch in _chapters:
		if found:
			return (ch as Dictionary).get("id", "")
		if (ch as Dictionary).get("id", "") == after_id:
			found = true
	return ""


# ---------------------------------------------------------------------------
# FaultTree 剧本注入与恢复
# ---------------------------------------------------------------------------

func _backup_and_inject_faults() -> void:
	var scenario: Dictionary = _active_chapter.get("scenario", {})
	if scenario.is_empty():
		return
	# 备份当前 DataManager 中的 faults（引用备份）
	_original_faults = DataManager.get_faults().duplicate(true)
	# 构造覆盖：保留原始 root_causes 定义（修复阈值等），仅覆盖轮次症状和可选的根因列表
	var injected: Dictionary = _original_faults.duplicate(true)
	if scenario.has("root_causes"):
		injected["root_causes"] = {}
		# 只保留教学场景用到的根因完整定义
		var all_rc: Dictionary = _original_faults.get("root_causes", {})
		for rc in scenario["root_causes"]:
			if all_rc.has(rc):
				injected["root_causes"][rc] = all_rc[rc]
	if scenario.has("rounds"):
		injected["rounds"] = scenario["rounds"]
	FaultTree.set_tutorial_override(injected)


func _restore_faults() -> void:
	FaultTree.clear_tutorial_override()
	_original_faults = {}


# ---------------------------------------------------------------------------
# 触发器：由 ControlRoom / GameState 调用
# ---------------------------------------------------------------------------

func _on_gamestate_round_changed(round_index: int) -> void:
	if not _active:
		return
	on_trigger("on_round_start", { "round": round_index })


## ControlRoom 在「提交」按钮按下前调用
func on_before_submit(round_index: int) -> void:
	if not _active:
		return
	on_trigger("on_before_submit", { "round": round_index })


## ControlRoom 在「提交」结算完成后调用
func on_after_submit(round_index: int) -> void:
	if not _active:
		return
	on_trigger("on_after_submit", { "round": round_index })


## 通用触发入口：匹配当前 chapter 的 steps
func on_trigger(trigger: String, ctx: Dictionary) -> void:
	if not _active:
		return
	var steps: Array = _active_chapter.get("steps", [])
	for i in range(steps.size()):
		var step: Dictionary = steps[i]
		if step.get("trigger", "") != trigger:
			continue
		# 条件校验
		var conditions_met: bool = true
		if step.has("round"):
			if int(step["round"]) != int(ctx.get("round", -1)):
				conditions_met = false
		if not conditions_met:
			continue

		# 去重：同一 step 在同一轮只触发一次
		var step_key: String = "%s_%d" % [trigger, i]
		if _steps_triggered.get(step_key, false):
			continue
		_steps_triggered[step_key] = true

		_current_step_index = i
		hint_requested.emit(step)
		break


# ---------------------------------------------------------------------------
# 成就隔离：教学模式不解锁标准成就/结局（防污染）
# ---------------------------------------------------------------------------

func blocks_standard_achievements() -> bool:
	return _active
