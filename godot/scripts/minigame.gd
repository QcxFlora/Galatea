extends RefCounted
## Galatea 的 Godot 脚本块示例。
##
## 约定（运行时按这个调用你）：
##   1. 脚本里声明 `var galatea` —— 运行时自动注入 Galatea 实例
##   2. 入口函数默认叫 run()，无参数；想换名字就在脚本块里填 entry
##   3. 通过 galatea.vars 读写剧情变量，剧情后续分支立刻能用
##   4. 入口函数应当是同步的。要做带交互的小游戏/3D 演出，
##      直接改导出项目里的 scenes/main.gd —— 那是完整 Godot 工程，你说了算。
##
## 剧情里这样挂：
##   {"type":"script","engine":"godot","src":"res://scripts/minigame.gd",
##    "entry":"run","next":"n_after"}

var galatea                      # Galatea 运行时，自动注入

func run() -> void:
	if galatea == null:
		push_error("minigame: galatea 没被注入 —— 运行时版本不对？")
		return
	# 示例：算一个分数写回剧情变量，后面的 branch 块就能用 minigame_score 判断
	var base: float = float(galatea.vars.get("affection", 0))
	var score := int(clampf(base * 2.0 + 3.0, 0.0, 100.0))
	galatea.vars["minigame_score"] = score
	galatea.vars["minigame_passed"] = score >= 60
	print("[minigame] 得分 %d，通过=%s" % [score, galatea.vars["minigame_passed"]])
