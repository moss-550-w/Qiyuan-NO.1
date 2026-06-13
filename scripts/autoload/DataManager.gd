extends Node
## DataManager —— 全局数据加载与校验单例
##
## 职责：
## 1. 启动时一次性加载 res://data 下所有 JSON 配置到内存（运行期只读）。
## 2. 对关键配置做字段校验，缺字段/格式错时打印明确报错，避免运行期空引用。
## 3. 对外提供 get_* 读取接口，业务模块只读取，不修改。
##
## 严格离线：仅使用 FileAccess 读取本地 res:// 资源，无任何网络访问。

## 所有配置文件清单：键名 → 相对 data 的文件名
const DATA_FILES := {
	"experts": "experts.json",
	"faults": "faults.json",
	"rounds": "rounds.json",
	"briefings": "briefings.json",
	"glossary": "kb_glossary.json",
	"timeline": "kb_timeline.json",
	"endings": "endings.json",
	"popups": "popups.json",
	"difficulty": "difficulty.json",
	"balance": "balance.json",
	"achievements": "achievements.json",

	"scenarios": "scenarios.json",
}

const DATA_DIR := "res://data/"

## 加载后的配置缓存：键 → 解析后的 Dictionary/Array
var _store: Dictionary = {}

## 是否全部加载并校验通过
var is_ready: bool = false

## 收集到的校验问题（字符串列表），供启动自检面板展示
var validation_errors: PackedStringArray = []


func _ready() -> void:
	load_all()


## 加载全部配置文件并执行校验
func load_all() -> void:
	_store.clear()
	validation_errors.clear()

	for key in DATA_FILES:
		var path: String = DATA_DIR + DATA_FILES[key]
		var parsed: Variant = _load_json(path)
		if parsed == null:
			# _load_json 内部已记录具体错误
			continue
		_store[key] = parsed

	_validate()
	is_ready = validation_errors.is_empty()

	if is_ready:
		print("[DataManager] 全部配置加载校验通过：%d 个文件" % _store.size())
	else:
		push_error("[DataManager] 配置校验存在 %d 个问题：" % validation_errors.size())
		for e in validation_errors:
			push_error("  - " + e)


## 读取并解析单个 JSON 文件，失败返回 null 并记录错误
func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		validation_errors.append("文件不存在：%s" % path)
		return null

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		validation_errors.append("文件为空：%s" % path)
		return null

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		validation_errors.append(
			"JSON 解析失败：%s（第 %d 行：%s）" % [path, json.get_error_line(), json.get_error_message()]
		)
		return null

	return json.data


## 字段校验：仅做关键结构性检查，业务细节由各模块自行兜底
func _validate() -> void:
	# experts：必须含四位专家，每位含 name/personality/direct_gauge（信任度模型）
	_require_keys("experts", ["magnet_eng", "wall_eng", "tritium_eng", "plasma_eng"])
	if _store.has("experts"):
		for id in _store["experts"]:
			if (id as String).begins_with("_"):
				continue
			var e: Variant = _store["experts"][id]
			_require_fields("experts.%s" % id, e, ["name", "personality", "direct_gauge"])

	# faults：必须含 root_causes 与 rounds
	_require_fields("faults", _store.get("faults"), ["root_causes", "rounds"])

	# difficulty：至少含 novice 与 chief 两档
	_require_keys("difficulty", ["novice", "chief"])

	# endings：12 条结局键（3 Q区间 × 4 根因识别数），缺失仅告警不阻断
	if _store.has("endings"):
		var ending_count: int = (_store["endings"] as Dictionary).size()
		if ending_count < 12:
			validation_errors.append("endings 结局数 %d < 12，矩阵不完整" % ending_count)

	# scenarios validation
	if _store.has("scenarios"):
		scen_cfg: Variant = _store["scenarios"]
		if scen_cfg is Dictionary:
			scen_list: Array = (scen_cfg as Dictionary).get("scenarios", [])
			for si in scen_list:
				if si is Dictionary:
					var sd: Dictionary = si as Dictionary
					_require_fields("scenarios[%s]" % si.get("id", "?"), sd, ["id", "name", "root_causes"])
		else:
			validation_errors.append("scenarios should be a Dictionary")


## 要求某顶层配置包含指定键
func _require_keys(store_key: String, keys: Array) -> void:
	if not _store.has(store_key):
		validation_errors.append("缺少配置：%s" % store_key)
		return
	var d: Variant = _store[store_key]
	if not (d is Dictionary):
		validation_errors.append("%s 应为对象（Dictionary）" % store_key)
		return
	for k in keys:
		if not (d as Dictionary).has(k):
			validation_errors.append("%s 缺少必需键：%s" % [store_key, k])


## 要求某对象包含指定字段
func _require_fields(label: String, obj: Variant, fields: Array) -> void:
	if not (obj is Dictionary):
		validation_errors.append("%s 应为对象（Dictionary）" % label)
		return
	for f in fields:
		if not (obj as Dictionary).has(f):
			validation_errors.append("%s 缺少字段：%s" % [label, f])


# ---------------------------------------------------------------------------
# 对外只读接口
# ---------------------------------------------------------------------------

## 获取整份配置（返回引用，调用方禁止修改）
func get_config(key: String) -> Variant:
	return _store.get(key)

func get_experts() -> Dictionary:
	var raw: Dictionary = _store.get("experts", {})
	var result: Dictionary = {}
	for k in raw:
		if raw[k] is Dictionary:
			result[k] = raw[k]
	return result

func get_faults() -> Dictionary:
	return _store.get("faults", {})

func get_rounds() -> Array:
	var faults: Dictionary = _store.get("faults", {})
	return faults.get("rounds", [])

func get_difficulty(level: String) -> Dictionary:
	var diffs: Dictionary = _store.get("difficulty", {})
	return diffs.get(level, {})

func get_balance() -> Dictionary:
	return _store.get("balance", {})

func get_endings() -> Dictionary:
	return _store.get("endings", {})

func get_glossary() -> Array:
	return _store.get("glossary", [])

func get_scenarios() -> Dictionary:
	return _store.get("scenarios", {})
