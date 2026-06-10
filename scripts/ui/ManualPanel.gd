extends Control
class_name ManualPanel
## ManualPanel —— 运行手册（科普知识库）覆盖面板
##
## 四个板块：词条 / 中国聚变成果 / 谣言辟谣 / 考研就业。
## 统一为"条目列表 + 详情"模型；搜索框对当前板块的条目做本地检索过滤。
## 全本地、零网络。可随时唤出（open）、点遮罩或关闭按钮收起（close）。

## 板块键 → 显示名
const SECTIONS := {
	"glossary": "科普词条",
	"milestones": "中国聚变成果",
	"myth": "谣言辟谣",
	"career": "考研就业",
}

@onready var _dimmer: ColorRect = $Dimmer
@onready var _title: Label = $Center/Window/Margin/VBox/Header/Title
@onready var _btn_close: Button = $Center/Window/Margin/VBox/Header/BtnClose
@onready var _tabs: HBoxContainer = $Center/Window/Margin/VBox/Tabs
@onready var _search: LineEdit = $Center/Window/Margin/VBox/Search
@onready var _list: ItemList = $Center/Window/Margin/VBox/Body/List
@onready var _detail: RichTextLabel = $Center/Window/Margin/VBox/Body/Detail

var _current_section: String = "glossary"
var _all_items: Array = []        # 当前板块全部条目 [{label, detail, search}]
var _filtered: Array = []         # 过滤后条目


func _ready() -> void:
	visible = false
	_btn_close.pressed.connect(close)
	_dimmer.gui_input.connect(_on_dimmer_input)
	_search.text_changed.connect(_on_search_changed)
	_list.item_selected.connect(_show_detail)
	_build_tabs()
	_load_section("glossary")


# ---------------------------------------------------------------------------
# 唤出 / 收起
# ---------------------------------------------------------------------------

func open() -> void:
	visible = true
	move_to_front()
	_search.grab_focus()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close()


# ---------------------------------------------------------------------------
# 板块
# ---------------------------------------------------------------------------

func _build_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	for key in SECTIONS:
		var btn := Button.new()
		btn.text = SECTIONS[key]
		btn.custom_minimum_size = Vector2(140, 36)
		btn.pressed.connect(_load_section.bind(key))
		_tabs.add_child(btn)


func _load_section(section: String) -> void:
	_current_section = section
	_title.text = "运行手册 · %s" % SECTIONS.get(section, section)
	_all_items = _build_section(section)
	_search.text = ""
	_refresh_list("")


## 把各板块原始数据转为统一条目模型
func _build_section(section: String) -> Array:
	var items: Array = []
	match section:
		"glossary":
			for e in DataManager.get_glossary():
				var ed: Dictionary = e
				if str(ed.get("id", "")).begins_with("_"):
					continue
				var term: String = ed.get("term", "")
				var cat: String = ed.get("category", "")
				var content: String = ed.get("content", "")
				items.append({
					"label": term,
					"detail": "[b]%s[/b]　[color=#8893a5](%s)[/color]\n\n%s" % [term, cat, content],
					"search": term + cat + content,
				})
		"milestones":
			var tl: Dictionary = DataManager.get_config("timeline")
			for e in tl.get("china_milestones", []):
				var ed: Dictionary = e
				var year: String = str(ed.get("year", ""))
				var ev: String = ed.get("event", "")
				if year == "_todo":
					continue
				items.append({
					"label": "%s　%s" % [year, ev.left(16)],
					"detail": "[b][color=#2bd6ff]%s 年[/color][/b]\n\n%s" % [year, ev],
					"search": year + ev,
				})
		"myth":
			var tl: Dictionary = DataManager.get_config("timeline")
			for e in tl.get("myth_busting", []):
				var ed: Dictionary = e
				var myth: String = ed.get("myth", "")
				var fact: String = ed.get("fact", "")
				items.append({
					"label": myth.left(20),
					"detail": "[color=#e64040][b]谣言[/b][/color]　%s\n\n[color=#4ed36a][b]事实[/b][/color]　%s" % [myth, fact],
					"search": myth + fact,
				})
		"career":
			var tl: Dictionary = DataManager.get_config("timeline")
			for e in tl.get("career_guide", []):
				var ed: Dictionary = e
				var topic: String = ed.get("topic", "")
				var content: String = ed.get("content", "")
				items.append({
					"label": topic,
					"detail": "[b]%s[/b]\n\n%s" % [topic, content],
					"search": topic + content,
				})
	return items


# ---------------------------------------------------------------------------
# 检索 / 详情
# ---------------------------------------------------------------------------

func _on_search_changed(text: String) -> void:
	_refresh_list(text)


func _refresh_list(filter: String) -> void:
	_list.clear()
	_filtered.clear()
	var key: String = filter.strip_edges().to_lower()
	for item in _all_items:
		if key == "" or key in String(item["search"]).to_lower():
			_list.add_item(item["label"])
			_filtered.append(item)
	if _filtered.is_empty():
		_detail.text = "[color=#8893a5]无匹配条目[/color]"
	else:
		_list.select(0)
		_show_detail(0)


func _show_detail(index: int) -> void:
	if index >= 0 and index < _filtered.size():
		_detail.text = str(_filtered[index]["detail"])
