extends RefCounted
## Galatea 的 GDScript 脚本块示例：一个"接住方块"的小游戏骨架
##
## 剧情里这样挂：
##   {"type":"script","engine":"godot","src":"res://scripts/minigame.gd",
##    "entry":"start","next":"n_after"}
##
## 入口函数结束（或协程 await 完）后，剧情自动往下走。

var ctx: Node            # GalateaRuntime
var stage: Node3D        # 3D 舞台
var won := false
var score := 0
var target := 3
var _running := true

func start(runtime: Node) -> void:
	ctx = runtime
	stage = runtime.get_parent().get_node("Stage")
	print("[minigame] 开始，目标分数 ", target)

	# 在舞台上摆三个可以点的小方块
	for i in 3:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.5, 0.5)
		box.mesh = mesh
		box.position = Vector3(-1.5 + i * 1.5, 0.8, 0)
		box.name = "target_%d" % i
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.79, 0.89, 0.72)
		box.material_override = mat
		stage.add_child(box)

	# 用定时器模拟"一局"：真实小游戏里这里可以接输入与碰撞
	while _running:
		await ctx.get_tree().create_timer(1.0).timeout
		score += 1
		print("[minigame] 第 %d 秒，分数 %d" % [score, score])
		if score >= target:
			won = true
			_running = false

	if won:
		print("[minigame] 通关！")
	else:
		print("[minigame] 结束")

	# 把结果写回剧情变量（VM 侧可以用 ${变量} 读）
	ctx.call("advance")  # 触发一次推进（可选）
