import os

path = r'D:\CODE\Qiyuan_No.1\scripts\ui\EndingPanel.gd'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Add preload
old_c = 'const ANIM_SCENE := preload(\"res://scenes/fx/TokamakAnimation.tscn\")'
new_c = old_c + '\nconst REVIEW_SCENE := preload(\"res://scenes/panels/ReviewPanel.tscn\")'
text = text.replace(old_c, new_c)

# 2. Add variable
old_var = 'var _anim: TokamakAnimation = null'
new_var = old_var + '\nvar _review_panel: ReviewPanel = null'
text = text.replace(old_var, new_var)

# 3. Add btn_review after btn_menu
old_btn = '@onready var _btn_menu: Button = /Panel/Margin/VBox/Buttons/BtnMenu'
new_btn = old_btn + '\n@onready var _btn_review: Button = /Panel/Margin/VBox/Buttons/BtnReview'
text = text.replace(old_btn, new_btn)

# 4. Add review panel init in _reveal_card
old_anim = '_anim.finished.connect(_reveal_card)'
new_anim = '''_anim.finished.connect(_reveal_card)

	# 复盘面板
	_review_panel = REVIEW_SCENE.instantiate()
	add_child(_review_panel)
	if _btn_review:
		_btn_review.pressed.connect(_on_review)'''
text = text.replace(old_anim, new_anim)

# 5. Add _on_review at end
old_end = '''func _on_menu() -> void:
	AudioManager.play(\"ui_click\")
	get_tree().change_scene_to_file(\"res://scenes/menu/MainMenu.tscn\")'''
new_end = old_end + '''


func _on_review() -> void:
	if _review_panel:
		_review_panel.open()'''
text = text.replace(old_end, new_end)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

with open(path, 'r', encoding='utf-8') as f:
    v = f.read()
print('OK REVIEW_SCENE:', 'REVIEW_SCENE' in v)
print('OK _review_panel:', '_review_panel' in v)
print('OK _btn_review:', '_btn_review' in v)
print('OK _on_review:', '_on_review' in v)
print('Lines:', len(text.split(chr(10))))