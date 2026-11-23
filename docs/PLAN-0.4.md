# Galatea 0.4 计划（用户真机反馈驱动）

> 状态：⬜ 没做 / 🔧 进行中 / ✅ 能用（有验证）/ ❌ 坏了
> 每项做完勾掉并附验证。不做完不勾。

## A. 立刻修坏的（用户真机发现）
- A1 ❌→⬜ 书架上的书点了进不去（tap 没导航）→ 修 home_page 卡片 onTap → 打开编辑器/播放器
- A2 ❌→⬜ 台词块 inspector 还残留「背景图/立绘（资源路径）」旧字段 → 删除（已解耦为 cast/art/bg 连线 + 图块）
- A3 ⬜ 积木面板（工具栏 chips）可视度太低 → 提高对比/尺寸/命中区域
- A4 ⬜ 触碰逻辑不好（拖拽/平移/端口命中）→ 加大端口命中半径、区分 tap 与 drag
- A5 ⬜ app 图标糊 → 高分辨率渲染 SVG 到各 mipmap，避免放大模糊
- A6 ⬜ GitHub Release 更新介绍还是 1.0 模板 → 每版写真实更新内容/已知问题/验证方法，或干脆不带

## B. 仓库与发布
- B1 ⬜ 仓库名首字母大写：QcxFlora/galatea → QcxFlora/Galatea（API rename + 更新 remote/引用）

## C. 完成度改为「分支级」（推翻 0.3 的节点级）
- C1 ⬜ 完成度 = 分支是否以 End 收尾（反向可达性），不是节点手动标记
- C2 ⬜ 连线颜色：能走到 End 的边=绿，走不到的=红
- C3 ⬜ 一键筛查未完成：只高亮红边/不可达节点，其余调暗
- C4 ⬜ 顶栏进度改为 可达End节点/总节点；移除节点手动 todo/wip/done 选择器
- C5 ⬜ Rust+Dart 双端 reaches_end 计算 + 测试

## D. 循环块（高可扩展）
- D1 ⬜ NodeKind::Loop { kind: Count/While/ForEach, expr, body, next, max_iters }
- D2 ⬜ VM 循环帧栈：body 尾连回 Loop=下一次迭代； Count/While/ForEach 三种判定；loop_index/loop_item 变量；max_iters 防死循环；快照含循环栈（撤销/存读档一致）
- D3 ⬜ Dart VM 同步 + inspector（kind/expr/body/max）+ 工具栏 + 端口 + 测试

## E. 组合块预览 / 排版块 / 手k动画→Rust 脚本
- E1 ⬜ 组合块（group）单个渲染预览 sheet：组内节点作为可拖拽元素排版
- E2 ⬜ NodeKind::Layout { group, items:[{node,x,y,scale,opacity,rot}], next }；「生成排版块」连到组合块
- E3 ⬜ 手k关键帧（time/prop/value）→「一键生成 Rust 脚本块」（弹簧补间代码）
- E4 ⬜ VM Event::Layout + 播放器按 items 定位渲染（不半开）

## 顺序
A(修坏) → B(改名) → C(分支完成度) → D(循环) → E(预览/排版/脚本)
每块独立提交，CI 绿 + APK 出包 + 真机要点列给用户。
