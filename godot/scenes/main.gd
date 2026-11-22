extends Node3D
## Galatea × Godot 运行时
##
## 职责：把 .gal 交给 Rust（galatea-core）跑剧情，自己只负责
## 3D 画面、立绘、对话框、选项按钮、转场。
##
## 事件协议（来自 GDExtension 的 JSON）：
##   {"type":"say","name":"阿米娅","text":"...","portrait":"...","bg":"..."}
##   {"type":"choices","prompt":"...","options":[{"index":0,"text":"..."}]}
##   {"type":"ending","ending":"tea","text":"..."}
##   {"type":"script","entry":"opening","ret":...,"emits":{...}}
##   {"type":"halt","reason":"..."}

@onready var camera: Camera3D = $Camera3D
@onready var stage: Node3D = $Stage
@onready var dialog: Label = $UI/DialogPanel/DialogText
@onready var speaker: Label = $UI/DialogPanel/Speaker
@onready var portrait: TextureRect = $UI/Portrait
@onready var options_box: VBoxContainer = $UI/Options
@onready var title_label: Label = $UI/Title

var rt: Object          # GalateaRuntime（GDExtension）
var current_options: Array = []
var typing := false
var _tween: Tween

const PORTRAIT_DIR := "user://assets/"

func _ready() -> void:
	if not ClassDB.class_exists("GalateaRuntime"):
		push_error("找不到 GalateaRuntime：检查 galatea.gdextension 与编译出的库")
		return
	rt = ClassDB.instantiate("GalateaRuntime")
	add_child(rt)

	var args := OS.get_cmdline_user_args()
	var gal_path := "res://stories/demo.gal"
	for a in args:
		if a.ends_with(".gal"):
			gal_path = a

	var title := rt.load_gal(gal_path)
	if title == "":
		title_label.text = "载入失败：" + gal_path
		return
	title_label.text = str(title)
	_next()

func _next() -> void:
	if rt == null:
		return
	var raw: String = rt.advance()
	var ev: Dictionary = JSON.parse_string(raw)
	if ev.is_empty():
		push_error("事件解析失败：" + raw)
		return
	match ev.get("type", ""):
		"say":
			_show_say(ev)
		"choices":
			_show_choices(ev)
		"ending":
			_show_ending(ev)
		"script":
			# 脚本块有两条路：
			#   engine=rust  → 已由 Rust 解释器执行完，这里只消费 emit
			#   engine=godot → 由本运行时加载 GDScript 并 await 它跑完
			if str(ev.get("engine", "rust")) == "godot":
				await _run_godot_script(ev)
			else:
				_apply_emits(ev.get("emits", {}))
			_next()
		"halt":
			dialog.text = "（停下：%s）" % ev.get("reason", "")
		_:
			_next()

func _show_say(ev: Dictionary) -> void:
	var name := str(ev.get("name", ""))
	speaker.text = name
	speaker.visible = name != ""
	_clear_options()
	_load_portrait(str(ev.get("portrait", "")))
	_set_bg(str(ev.get("bg", "")))
	_type_text(str(ev.get("text", "")))

func _type_text(full: String) -> void:
	typing = true
	dialog.visible_ratio = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(dialog, "visible_ratio", 1.0, clamp(full.length() * 0.022, 0.2, 3.0))
	_tween.finished.connect(func(): typing = false)

func _show_choices(ev: Dictionary) -> void:
	_clear_options()
	current_options = ev.get("options", [])
	var prompt := str(ev.get("prompt", ""))
	if prompt != "":
		speaker.text = prompt
		speaker.visible = true
	for i in current_options.size():
		var b := Button.new()
		b.text = "  " + str(current_options[i].get("text", ""))
		b.custom_minimum_size = Vector2(520, 46)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_on_choice.bind(int(current_options[i].get("index", i))))
		options_box.add_child(b)

func _on_choice(index: int) -> void:
	_clear_options()
	var raw: String = rt.choose(index)
	var ev: Dictionary = JSON.parse_string(raw)
	match ev.get("type", ""):
		"say": _show_say(ev)
		"choices": _show_choices(ev)
		"ending": _show_ending(ev)
		"script":
			if str(ev.get("engine", "rust")) == "godot":
				await _run_godot_script(ev)
			else:
				_apply_emits(ev.get("emits", {}))
			_next()
		_: _next()

func _show_ending(ev: Dictionary) -> void:
	_clear_options()
	speaker.text = "ENDING · " + str(ev.get("ending", ""))
	speaker.visible = true
	_type_text(str(ev.get("text", "")))

func _clear_options() -> void:
	for c in options_box.get_children():
		c.queue_free()

func _load_portrait(path: String) -> void:
	portrait.visible = false
	if path == "" or rt == null:
		return
	var bytes: PackedByteArray = rt.asset_bytes(path)
	if bytes.is_empty():
		return
	var img := Image.new()
	var err := OK
	if path.ends_with(".webp"):
		err = img.load_webp_from_buffer(bytes)
	elif path.ends_with(".png"):
		err = img.load_png_from_buffer(bytes)
	else:
		err = img.load_jpg_from_buffer(bytes)
	if err != OK:
		push_warning("立绘解码失败：" + path)
		return
	portrait.texture = ImageTexture.create_from_image(img)
	portrait.visible = true
	portrait.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(portrait, "modulate:a", 1.0, 0.28)

func _set_bg(path: String) -> void:
	# 背景先用环境色代替（正式版接 WorldEnvironment + 天空盒）
	if path == "":
		return

## 脚本节点的 emit 通道 → 简单 3D 动作（给"自己搓动画"用）
func _apply_emits(emits: Dictionary) -> void:
	if emits.has("cameraY"):
		var y := float(emits["cameraY"])
		var t := create_tween()
		t.tween_property(camera, "position:y", 2.0 + y * 0.01, 0.3)
	if emits.has("beat"):
		var t2 := create_tween()
		t2.tween_property(stage, "scale", Vector3.ONE * (1.0 + float(emits["beat"]) * 0.01), 0.12)
		t2.tween_property(stage, "scale", Vector3.ONE, 0.18)
	if emits.has("bgm"):
		pass # 正式版接 AudioStreamPlayer

## 输入：点击对话框 = 下一句
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if typing:
			dialog.visible_ratio = 1.0
			typing = false
			if _tween: _tween.kill()
		elif options_box.get_child_count() == 0:
			_next()
	if event is InputEventScreenTouch and event.pressed:
		if typing:
			dialog.visible_ratio = 1.0
			typing = false
		elif options_box.get_child_count() == 0:
			_next()

## ─────────────────────────────────────────────────────────────
## GDScript 脚本块：脚本作者可以直接写小游戏
##
## scripts/minigame.gd：
##     extends RefCounted
##     func start(ctx: Node) -> void:
##         # 想做什么都行：生成 3D 物体、接碰撞、放音乐…
##         await ctx.get_tree().create_timer(2.0).timeout
##
## 约定：入口函数可以是普通函数，也可以是协程（内部 await）；
## 协程会等它真正结束再推进剧情。
## ─────────────────────────────────────────────────────────────
func _run_godot_script(ev: Dictionary) -> void:
	var path := str(ev.get("src", ""))
	var entry := str(ev.get("entry", "start"))
	if path == "":
		push_warning("[galatea] 脚本块没有 src")
		return
	if not ResourceLoader.exists(path):
		push_warning("[galatea] 找不到脚本：" + path)
		return
	var script: Script = load(path)
	if script == null:
		push_warning("[galatea] 无法加载：" + path)
		return
	var inst = script.new()
	if inst == null:
		push_warning("[galatea] 无法实例化：" + path)
		return
	if inst is Object and not inst.has_method(entry):
		push_warning("[galatea] %s 没有方法 %s" % [path, entry])
		return
	var result = inst.call(entry, rt)
	if result is Signal:
		await result
