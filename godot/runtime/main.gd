extends Control
## Galatea 导出的默认演出场景。
## 想换皮就改这个文件 —— 剧情逻辑全在 galatea.gd 里，不用动。

var g: Galatea
var bg: TextureRect
var art: TextureRect
var name_label: Label
var text_label: RichTextLabel
var choice_box: VBoxContainer
var waiting_for_choice := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	bg = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)

	art = TextureRect.new()
	art.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(0, 720)
	art.position = Vector2(0, 0)
	add_child(art)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -220
	panel.offset_left = 32
	panel.offset_right = -32
	panel.offset_bottom = -24
	add_child(panel)

	var vb := VBoxContainer.new()
	panel.add_child(vb)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 26)
	vb.add_child(name_label)
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.custom_minimum_size = Vector2(0, 96)
	text_label.add_theme_font_size_override("normal_font_size", 22)
	vb.add_child(text_label)
	choice_box = VBoxContainer.new()
	vb.add_child(choice_box)

	g = Galatea.new()
	g.say.connect(_on_say)
	g.choices.connect(_on_choices)
	g.finished.connect(_on_finished)
	g.failed.connect(_on_failed)

	var path := "res://story.gal"
	if not g.load_package(path):
		return                                   # failed 信号已经把原因说清楚了
	g.start()

func _on_say(who: String, text: String, portrait: String, background: String) -> void:
	waiting_for_choice = false
	_clear_choices()
	name_label.text = who
	text_label.text = text
	if background != "":
		var tex := _load_tex(background)
		if tex != null:
			bg.texture = tex
	if portrait != "":
		var tex2 := _load_tex(portrait)
		if tex2 != null:
			art.texture = tex2
			art.visible = true
	else:
		art.visible = false

func _on_choices(options: Array) -> void:
	waiting_for_choice = true
	_clear_choices()
	for i in options.size():
		var b := Button.new()
		b.text = options[i].text
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(func():
			waiting_for_choice = false
			g.choose(i))
		choice_box.add_child(b)

func _on_finished(reason: String) -> void:
	name_label.text = ""
	text_label.text = "[i]—— 完 ——[/i]"
	_clear_choices()

func _on_failed(message: String) -> void:
	name_label.text = "运行失败"
	text_label.text = "[color=#E5484D]%s[/color]" % message
	_clear_choices()
	push_error("Galatea: " + message)

func _clear_choices() -> void:
	for c in choice_box.get_children():
		c.queue_free()

func _load_tex(rel: String) -> Texture2D:
	var p := "res://" + rel.trim_prefix("res://")
	if ResourceLoader.exists(p):
		return load(p)
	# 找不到就明说，不静默显示空白
	push_warning("素材不存在：%s —— 导出时没拷进来？" % p)
	return null

func _gui_input(event: InputEvent) -> void:
	if waiting_for_choice:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		g.advance()
	elif event is InputEventScreenTouch and event.pressed:
		g.advance()

func _unhandled_input(event: InputEvent) -> void:
	if waiting_for_choice:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		g.advance()
