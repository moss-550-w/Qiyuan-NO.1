path = r'D:\CODE\Qiyuan_No.1\scenes\panels\EndingPanel.tscn'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

review_btn = '\r\n[node name=\"BtnReview\" type=\"Button\" parent=\"Center/Panel/Margin/VBox/Buttons\"]\r\ncustom_minimum_size = Vector2(200, 50)\r\nlayout_mode = 2\r\ntext = 复盘'

old_btn_menu = '[node name=\"BtnMenu\"'
text = text.replace(old_btn_menu, review_btn + '\n' + old_btn_menu)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
print('OK: added BtnReview to EndingPanel.tscn')