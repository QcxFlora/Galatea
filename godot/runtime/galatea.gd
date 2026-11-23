class_name Galatea
extends RefCounted
## Galatea 剧情运行时（纯 GDScript，零扩展依赖）。
##
## 直接读 .gal 包：Godot 4 自带 deflate 解压，不需要 GDExtension。
## 变量、表达式、分支全在这里算 —— 与 Rust 内核同一套语义。
##
## 用法：
##   var g = Galatea.new()
##   g.load_package("res://story.gal")
##   g.say.connect(_on_say)
##   g.choices.connect(_on_choices)
##   g.start()

signal say(who: String, text: String, portrait: String, background: String)
signal choices(options: Array)          # [{text, target}]
signal finished(reason: String)
signal scene_changed(payload: Dictionary)
signal failed(message: String)

var nodes: Dictionary = {}              # id -> node dict
var pool: Array = []
var vars: Dictionary = {}
var start_id: String = ""
var current: String = ""
var call_stack: Array = []
var steps: int = 0
const MAX_STEPS := 100000

# ── .gal 读取 ────────────────────────────────────────────
func load_package(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		failed.emit("打不开包：%s（%s）" % [path, error_string(FileAccess.get_open_error())])
		return false
	var magic := f.get_buffer(4)
	if magic != PackedByteArray([0x47, 0x41, 0x4C, 0x01]):
		failed.emit("不是 .gal 包（magic 不符）：%s" % path)
		return false
	var version := f.get_16()
	if version != 1:
		failed.emit("不支持的 .gal 版本 %d（本运行时只认 1）" % version)
		return false
	f.get_16()                                   # flags
	var count := f.get_32()
	var index_len := f.get_32()
	var index_start := f.get_position()
	var entries: Array = []
	for i in count:
		var nlen := f.get_16()
		var name := f.get_buffer(nlen).get_string_from_utf8()
		var method := f.get_8()
		var offset := f.get_64()
		var csize := f.get_64()
		var usize := f.get_64()
		f.get_32()                               # crc32（Godot 侧不校验，打包时已校验）
		entries.append({"name": name, "method": method,
			"offset": offset, "csize": csize, "usize": usize})
	var data_start := index_start + index_len
	var files: Dictionary = {}
	for e in entries:
		f.seek(data_start + e.offset)
		var raw := f.get_buffer(e.csize)
		var bytes: PackedByteArray
		if e.method == 1:
			bytes = raw.decompress(e.usize, FileAccess.COMPRESSION_DEFLATE)
			if bytes.size() != e.usize:
				failed.emit("解压失败：%s（期望 %d 字节，得到 %d）" % [e.name, e.usize, bytes.size()])
				return false
		else:
			bytes = raw
		files[e.name] = bytes
	f.close()
	if not files.has("doc"):
		failed.emit("包里没有 doc（剧情文档）")
		return false
	pool = JSON.parse_string(files["$gal/pool"].get_string_from_utf8()) if files.has("$gal/pool") else []
	var doc = JSON.parse_string(files["doc"].get_string_from_utf8())
	if doc == null:
		failed.emit("doc 不是合法 JSON")
		return false
	doc = _unpool(doc)
	start_id = doc.get("start", "")
	for n in doc.get("nodes", []):
		nodes[n.id] = n
	for k in doc.get("vars", {}):
		vars[k] = doc.vars[k]
	if start_id == "" or not nodes.has(start_id):
		failed.emit("起点无效：`%s`" % start_id)
		return false
	return true

## 池化还原：{"$s": i} → pool[i]
func _unpool(v):
	if v is Dictionary:
		if v.has("$s"):
			var i: int = v["$s"]
			if i < 0 or i >= pool.size():
				failed.emit("字符串池索引越界：%d（池长 %d）" % [i, pool.size()])
				return ""
			return pool[i]
		var out := {}
		for k in v:
			out[_unpool(k)] = _unpool(v[k])
		return out
	if v is Array:
		return v.map(_unpool)
	return v

# ── 执行 ────────────────────────────────────────────────
func start() -> void:
	current = start_id
	call_stack.clear()
	steps = 0
	_run()

func choose(index: int) -> void:
	var n: Dictionary = nodes.get(current, {})
	var opts: Array = n.get("options", [])
	if index < 0 or index >= opts.size():
		failed.emit("选项下标越界：%d" % index)
		return
	current = opts[index].get("target", "")
	_run()

func _run() -> void:
	while current != "":
		steps += 1
		if steps > MAX_STEPS:
			failed.emit("步数超过 %d —— 剧情里大概有死循环" % MAX_STEPS)
			return
		if not nodes.has(current):
			failed.emit("跳转到不存在的节点：`%s`" % current)
			return
		var n: Dictionary = nodes[current]
		match n.get("type", ""):
			"say":
				say.emit(_first(n, "cast"), _interp(n.get("text", "")),
					_first(n, "art"), _first(n, "bg"))
				return                            # 等玩家点击
			"choice":
				var opts: Array = []
				for o in n.get("options", []):
					if o.has("cond") and not _truthy(eval(o.cond)):
						continue
					opts.append({"text": _interp(o.get("text", "")), "target": o.get("target", "")})
				if opts.is_empty():
					failed.emit("选项全被条件挡住了，无路可走（节点 %s）" % current)
					return
				choices.emit(opts)
				return
			"branch":
				var cond_ok := _truthy(eval(n.get("cond", "false")))
				current = n.get("yes", "") if cond_ok else n.get("no", "")
			"set":
				vars[n.get("key", "")] = eval(n.get("value", "0"))
				current = n.get("next", "")
			"jump":
				current = n.get("target", "")
			"call":
				call_stack.append(n.get("next", ""))
				current = n.get("target", "")
			"return":
				current = call_stack.pop_back() if call_stack.size() > 0 else ""
			"label", "character", "portrait", "background", "value", "variable", "weighted":
				current = n.get("next", "")       # 声明块：运行时跳过
			"script":
				_run_script(n)
				current = n.get("next", "")
			"end":
				finished.emit("end")
				return
			_:
				failed.emit("未知节点类型：`%s`" % n.get("type", ""))
				return
	finished.emit("fallthrough")

func advance() -> void:
	var n: Dictionary = nodes.get(current, {})
	current = n.get("next", "")
	_run()

## Godot 脚本块：调用引用的 .gd 里的入口函数。
## 脚本由作者在自己安装的 Godot 里编写/调试，Galatea 只负责引用与打包。
func _run_script(n: Dictionary) -> void:
	var engine: String = n.get("engine", "rust")
	if engine != "godot":
		failed.emit("Godot 运行时不能执行 rust 脚本块（节点 %s）——导出前请改成 godot 引擎" % current)
		return
	var path: String = n.get("scriptPath", "")
	if path == "":
		failed.emit("脚本块没有 scriptPath（节点 %s）" % current)
		return
	var res_path := "res://" + path.trim_prefix("res://")
	if not ResourceLoader.exists(res_path):
		failed.emit("引用的脚本不存在：%s —— 导出时没拷进来？" % res_path)
		return
	var scr = load(res_path)
	var inst = scr.new()
	var entry: String = n.get("entry", "run")
	if entry == "":
		entry = "run"
	if not inst.has_method(entry):
		failed.emit("%s 里没有函数 `%s()`" % [res_path, entry])
		if inst is Node:
			inst.queue_free()
		return
	if "galatea" in inst:
		inst.set("galatea", self)
	inst.call(entry)
	if inst is Node:
		inst.queue_free()

# ── 表达式（与 Rust 内核同语义）────────────────────────────
func eval(src: String):
	var p := _Parser.new(src, vars)
	var v = p.parse_expr(0)
	if p.err != "":
		failed.emit("表达式错误 `%s`：%s" % [src, p.err])
		return 0
	return v

func _truthy(v) -> bool:
	if v is bool: return v
	if v is float or v is int: return v != 0
	if v is String: return v != "" and v != "false" and v != "0"
	return v != null

func _first(n: Dictionary, key: String) -> String:
	var a = n.get(key, [])
	if a is Array and a.size() > 0: return str(a[0])
	if a is String: return a
	return ""

func _interp(text: String) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		if text[i] == "{" and i + 1 < text.length() and text[i + 1] == "{":
			var end := text.find("}}", i + 2)
			if end < 0:
				out += text.substr(i)
				break
			out += str(eval(text.substr(i + 2, end - i - 2)))
			i = end + 2
		else:
			out += text[i]
			i += 1
	return out

## 极简 Pratt 解析器：数字/字符串/变量/+-*/%/比较/and or not/括号
class _Parser:
	var s: String
	var i: int = 0
	var vars: Dictionary
	var err: String = ""
	func _init(src: String, v: Dictionary):
		s = src
		vars = v
	func _ws() -> void:
		while i < s.length() and s[i] in [" ", "\t", "\n", "\r"]:
			i += 1
	func _eat(word: String) -> bool:
		_ws()
		if s.substr(i, word.length()) == word:
			i += word.length()
			return true
		return false
	func parse_expr(min_bp: int):
		_ws()
		var left = _prefix()
		while true:
			_ws()
			if i >= s.length(): break
			var op := _peek_op()
			if op == "": break
			var bp: int = _BP.get(op, -1)
			if bp < min_bp: break
			i += op.length()
			var right = parse_expr(bp + 1)
			left = _apply(op, left, right)
		return left
	const _BP := {"or": 1, "||": 1, "and": 2, "&&": 2,
		"==": 3, "!=": 3, "<": 4, "<=": 4, ">": 4, ">=": 4,
		"+": 5, "-": 5, "*": 6, "/": 6, "%": 6}
	func _peek_op() -> String:
		for op in ["<=", ">=", "==", "!=", "&&", "||", "and", "or", "<", ">", "+", "-", "*", "/", "%"]:
			if s.substr(i, op.length()) == op:
				if op in ["and", "or"]:
					var nxt := i + op.length()
					if nxt < s.length() and (s[nxt].is_valid_identifier() or s[nxt] in "0123456789_"):
						continue
				return op
		return ""
	func _prefix():
		_ws()
		if i >= s.length():
			err = "表达式意外结束"
			return 0
		var c := s[i]
		if c == "(":
			i += 1
			var v = parse_expr(0)
			_ws()
			if i < s.length() and s[i] == ")": i += 1
			else: err = "缺少右括号"
			return v
		if c == "-" or c == "!":
			i += 1
			var v = _prefix()
			return -v if c == "-" else (not _t(v))
		if c == "\"" or c == "'":
			var q := c
			i += 1
			var out := ""
			while i < s.length() and s[i] != q:
				out += s[i]
				i += 1
			if i >= s.length(): err = "字符串没有闭合"
			else: i += 1
			return out
		if c in "0123456789.":
			var st := i
			while i < s.length() and (s[i] in "0123456789."):
				i += 1
			return float(s.substr(st, i - st))
		var st2 := i
		while i < s.length() and (s[i].is_valid_identifier() or s[i] in "0123456789_"):
			i += 1
		var name := s.substr(st2, i - st2)
		if name == "":
			err = "无法解析的字符 `%s`" % c
			i += 1
			return 0
		match name:
			"true": return true
			"false": return false
			"not": return not _t(_prefix())
			_: return vars.get(name, 0)
	func _t(v) -> bool:
		if v is bool: return v
		if v is float or v is int: return v != 0
		if v is String: return v != "" and v != "false"
		return v != null
	func _apply(op: String, a, b):
		match op:
			"+": return (a + b) if (a is String or b is String) else (float(a) + float(b))
			"-": return float(a) - float(b)
			"*": return float(a) * float(b)
			"/":
				if float(b) == 0:
					err = "除以零"
					return 0
				return float(a) / float(b)
			"%":
				if float(b) == 0:
					err = "模零"
					return 0
				return fmod(float(a), float(b))
			"==": return a == b
			"!=": return a != b
			"<": return float(a) < float(b)
			"<=": return float(a) <= float(b)
			">": return float(a) > float(b)
			">=": return float(a) >= float(b)
			"and", "&&": return _t(a) and _t(b)
			"or", "||": return _t(a) or _t(b)
		err = "未知运算符 `%s`" % op
		return 0
