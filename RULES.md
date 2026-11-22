# 写代码的纪律（给人和 AI 的硬约束）

> 这份文件是**合同**，不是建议。违反即回滚，不讨论"先这样以后再改"。

## 第 0 条 · 一句话

**要么能跑，要么编译不过 / 启动就崩。不允许「能跑但是坏的」。**

---

## 第 1 条 · 禁止静默降级

以下写法**一律不允许**，见到即视为缺陷：

```dart
// ❌ 库没加载到就显示占位框
if (engine == null) return const Placeholder();

// ❌ 解码失败就画个灰块
errorBuilder: (_, __, ___) => const SizedBox.shrink(),

// ❌ 出错就退回去用文件名
catch (_) { return fallbackName; }
```

```rust
// ❌ 脚本编译失败就当没这个节点
let Ok(script) = Script::compile(...) else { return next; };
```

**正确做法**：

| 场景 | 该怎么做 |
|---|---|
| 依赖库缺失 | `throw StateError('找不到 libgalatea_3d.so，请先 cargo ndk 编译')`，启动即崩 |
| 资源解码失败 | `throw FormatException('立绘 amiya.webp 解码失败')`，并在画面里报出来 |
| 剧本损坏 | 条目显示为 **红字「损坏」**，点开显示具体错误；不允许悄悄用文件名顶上 |
| 可选能力 | 用**显式开关**（`--features` / 构造参数 / 编译期常量）。关闭时功能不存在，开启时必须是真实现 |

理由：静默降级会把"坏"伪装成"好"。等系统长到 200 个功能，没人能分清哪个是真的能用。

---

## 第 2 条 · 禁止空捕获

```dart
// ❌ 全部禁止
catch (_) {}
catch (_) { continue; }
on Exception catch (_) {}
```

```rust
// ❌ 同样禁止
let _ = something_that_may_fail();
if let Ok(x) = risky() { } else { /* 什么也不做 */ }
```

**允许的三种例外**（必须同时满足）：

1. 明确写出捕获类型：`on FormatException catch (e)`
2. 把错误**转成更强的错误**再抛：`throw StateError('读取 $path 失败：$e')`
3. 或者：打日志 + 记一次计数 + 当行注明 `// swallow-ok: <为什么可以忽略>`

---

## 第 3 条 · 占位符不许进主路径

```dart
// ❌ 这个函数被调用，但里面什么都没做
void _updateSomething() {
  // TODO
}
```

**未实现就抛**：

```dart
void _updateSomething() => throw UnimplementedError('_updateSomething 还没实现（issue #12）');
```

这样一调就炸，炸了就知道哪没写。悄悄返回 `null` / 空 Widget 是作弊。

---

## 第 4 条 · 错误必须可见

- **启动期**：红屏 + 堆栈（Flutter 默认行为，不要 try-catch 包住 main）
- **运行期**：日志里能看到完整错误链，进程非零退出
- **用户可见处**：任何"降级显示"必须带**明确的错误标识**（红字 / 角标 / 可点开详情），不能长得跟正常一样

---

## 第 5 条 · CI 强制检查

```bash
# 1. 空捕获
grep -rnE 'catch\s*\(\s*_\s*\)\s*\{\s*\}' app/lib && exit 1
grep -rnE 'catch\s*\(\s*_\s*\)\s*\{\s*continue' app/lib && exit 1
grep -rnE 'let _ = ' crates --include='*.rs' && exit 1

# 2. 降级话术
grep -rniE '(优雅降级|静默降级|作为兜底|fallback to|best effort)' app/lib crates && exit 1

# 3. 占位实现
grep -rnE '(TODO|FIXME|XXX|占位)' app/lib crates --include='*.dart' --include='*.rs' | grep -v '^\s*//' && exit 1

# 4. 静态分析
dart analyze --fatal-infos --fatal-warnings
cargo clippy --all-targets -- -D warnings
```

第 5 条的脚本落在 `.github/workflows/ci.yml`，**红了就合不了**。

---

## 第 6 条 · 验收标准

功能清单里每一条，只能有三种状态：

| 状态 | 要求 |
|---|---|
| ✅ 能用 | 有测试覆盖，或有一条人工验证记录（截图/命令输出） |
| ❌ 不能用 | 编译失败、启动崩、或测试红。**明确地坏** |
| ⬜ 没做 | 代码里不存在，功能清单里标"未做" |

**不存在第四种状态。** "写了但没通"一律算 ❌，不允许出现在 ✅ 一栏。

---

## 第 7 条 · 删掉"自保"代码

清单（见到就删）：

- `?? const SizedBox.shrink()`
- `errorBuilder: (...) => SizedBox.shrink()`
- `if (x == null) return;`（在初始化路径上）
- `orElse: () => ''`（在协议/数据解析里）
- `unwrap_or_default()`（在关键数据上）
- `#[allow(dead_code)]` 给没接通的模块
- `// TODO: 以后接上`

只有**明确标注为"用户可选的软失败"**的地方保留，且必须在 UI 上看得见。

---

## 附：给 AI 的直白指令

> 你写代码时不许给自己留退路。
> 依赖缺失就 `throw`，别写"优雅降级成占位框"。
> 解析失败就报错，别 `catch (_) {}` 然后继续。
> 功能没做完就 `throw UnimplementedError`，别返回空值假装成功。
> 你要让"坏"这件事**立刻、明显、刺眼**地暴露出来，
> 而不是藏在"能跑"的外壳下。
>
> 如果某个能力确实依赖外部环境（比如原生库、系统权限），
> 就用**显式开关 + 启动时硬校验**：
> 开关打开 → 依赖缺失 → 直接崩，并在崩溃信息里写清怎么修。