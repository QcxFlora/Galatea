//! galatea 命令行：校验、终端试玩、格式化、生成模板。
//!
//! ```text
//! galatea new  作品.json           生成一个最小可玩模板
//! galatea lint 作品.json           体检（CI 用；有错误时退出码 1）
//! galatea play 作品.json           直接在终端里试玩
//! galatea fmt  作品.json           规范化格式（排序、缩进）
//! galatea stat 作品.json           统计字数 / 节点 / 结局 / 覆盖率
//! ```

use galatea_core::graph::{Character, Node, Story};
use galatea_core::json::Json;
use galatea_core::lint::{self, Level};
use galatea_core::gal;
use galatea_core::script::{Script, Value as ScriptValue};
use std::collections::BTreeMap;
use galatea_core::vm::{Event, Vm};
use std::io::{self, BufRead, Write};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        usage();
        std::process::exit(2);
    }
    if args[0] == "--version" || args[0] == "-V" || args[0] == "version" {
        println!("galatea {}  (.gal v1)", galatea_core::VERSION);
        return;
    }
    let cmd = args[0].clone();
    let file = args.get(1).cloned().unwrap_or_default();
    let rest: Vec<String> = args.iter().skip(2).cloned().collect();
    let result = match cmd.as_str() {
        "lint" | "check" => cmd_lint(&file),
        "play" | "run" => cmd_play(&file),
        "fmt" | "format" => cmd_fmt(&file),
        "new" | "init" => cmd_new(&file, rest.first().cloned().unwrap_or_else(|| "未命名".into())),
        "stat" | "stats" => cmd_stat(&file),
        "script" | "sc" => cmd_script(&file, &rest),
        "pack" | "p" => cmd_pack(&file, &rest),
        "unpack" | "u" => cmd_unpack(&file, &rest),
        "info" | "i" => cmd_info(&file),
        "export-godot" | "eg" => cmd_export_godot(&file, &rest),
        "help" | "-h" | "--help" => {
            usage();
            Ok(())
        }
        other => {
            eprintln!("未知命令 `{}`", other);
            usage();
            std::process::exit(2);
        }
    };
    if let Err(e) = result {
        eprintln!("失败：{}", e);
        std::process::exit(1);
    }
}

fn usage() {
    println!("galatea —— 思维导图式 Galgame 引擎");
    println!();
    println!("  galatea new  <文件> [标题]   生成最小模板");
    println!("  galatea lint <文件>          体检（有错误时退出码 1）");
    println!("  galatea play <文件>          终端试玩（回车继续 / 数字选择 / u 撤销 / q 退出）");
    println!("  galatea fmt  <文件>          规范化格式");
    println!("  galatea stat <文件>          统计");
    println!("  galatea script <脚本.rs> [函数] [参数…]   跑自定义脚本");
    println!("  galatea pack   <剧本.json> [-o 作品.gal]  打包成 .gal（压缩）");
    println!("  galatea unpack <作品.gal>  [-o 目录]      解开 .gal");
    println!("  galatea info   <作品.gal>                 查看包内容与压缩率");
    println!("         --sample <起> <止> <步数>            采样一条动画曲线");
}

fn load(file: &str) -> Result<Story, String> {
    let bytes = std::fs::read(file).map_err(|e| format!("读不到 {}：{}", file, e))?;
    let src = if bytes.starts_with(gal::MAGIC) {
        let arc = gal::parse(&bytes)?;
        String::from_utf8(arc.read("story.gala.json")?)
            .map_err(|e| format!(".gal 里的剧本不是 UTF-8：{}", e))?
    } else {
        String::from_utf8(bytes).map_err(|e| format!("{} 不是 UTF-8：{}", file, e))?
    };
    // 池化过的剧本会自动还原（普通 JSON 原样通过）
    let doc = galatea_core::json::parse(&src)?;
    let plain = galatea_core::compact::unpack(&doc)?;
    Story::from_json(&plain)
}

fn cmd_lint(file: &str) -> Result<(), String> {
    let story = load(file)?;
    let issues = lint::lint(&story);
    let (e, w, i) = lint::summary(&issues);
    println!(
        "《{}》  节点 {}  变量 {}  角色 {}",
        story.meta.title,
        story.nodes.len(),
        story.vars.len(),
        story.characters.len()
    );
    for it in &issues {
        let mark = match it.level {
            Level::Error => "✗",
            Level::Warning => "!",
            Level::Info => "·",
        };
        match &it.node {
            Some(n) => println!("  {} [{}] {}  ({})", mark, it.level.tag(), it.msg, n),
            None => println!("  {} [{}] {}", mark, it.level.tag(), it.msg),
        }
    }
    println!();
    println!("{} 个错误 / {} 个警告 / {} 个提示", e, w, i);
    if e > 0 {
        std::process::exit(1);
    }
    Ok(())
}

fn cmd_fmt(file: &str) -> Result<(), String> {
    let story = load(file)?;
    std::fs::write(file, story.to_json_string_pretty())
        .map_err(|e| format!("写不回 {}：{}", file, e))?;
    println!("已规范化 {}", file);
    Ok(())
}

fn cmd_new(file: &str, title: String) -> Result<(), String> {
    let mut s = Story::new(&title, "opening");
    s.meta.author = "你".into();
    s.characters.insert(
        "hero".into(),
        Character {
            name: "我".into(),
            color: Some("#9ecbff".into()),
            avatar: None,
        },
    );
    s.characters.insert(
        "yuki".into(),
        Character {
            name: "雪".into(),
            color: Some("#c3a6ff".into()),
            avatar: None,
        },
    );
    s.vars.insert("好感".into(), Json::Num(0.0));

    s.add_node(Node {
        id: "opening".into(),
        x: 0.0,
        y: 0.0,
        title: None,
        kind: galatea_core::NodeKind::Say {
            text: "……你终于来了。".into(),
            next: Some("ask".into()),
            cast: vec!["yuki".into()],
            art: Vec::new(),
            bg: Vec::new(),
        },
    });
    s.add_node(Node {
        id: "ask".into(),
        x: 0.0,
        y: 140.0,
        title: Some("要说什么？".into()),
        kind: galatea_core::NodeKind::Choice {
            prompt: "怎么回答？".into(),
            options: vec![
                galatea_core::Choice {
                    text: "我一直在等这句话。".into(),
                    to: "good".into(),
                    cond: String::new(),
                    effects: vec![galatea_core::Effect::new("好感", galatea_core::Op::Add, "1")],
                    once: false,
                },
                galatea_core::Choice {
                    text: "……你是谁？".into(),
                    to: "bad".into(),
                    cond: String::new(),
                    effects: vec![],
                    once: false,
                },
            ],
        },
    });
    s.add_node(Node {
        id: "good".into(),
        x: -180.0,
        y: 300.0,
        title: None,
        kind: galatea_core::NodeKind::Say {
            text: "那就好。".into(),
            next: Some("end_good".into()),
            cast: vec!["yuki".into()],
            art: Vec::new(),
            bg: Vec::new(),
        },
    });
    s.add_node(Node {
        id: "bad".into(),
        x: 200.0,
        y: 300.0,
        title: None,
        kind: galatea_core::NodeKind::Say {
            text: "她的眼神暗了下去。".into(),
            next: Some("end_bad".into()),
            cast: Vec::new(),
            art: Vec::new(),
            bg: Vec::new(),
        },
    });
    s.add_node(Story::mk_end("end_good", -180.0, 440.0, "good", "结局：如约"));
    s.add_node(Story::mk_end("end_bad", 200.0, 440.0, "bad", "结局：陌生人"));

    std::fs::write(file, s.to_json_string_pretty())
        .map_err(|e| format!("写不了 {}：{}", file, e))?;
    println!("已生成 {}（试着 `galatea play {}`）", file, file);
    Ok(())
}

fn cmd_stat(file: &str) -> Result<(), String> {
    let story = load(file)?;
    let mut say_nodes = 0;
    let mut chars = 0;
    let mut ends = 0;
    let mut choices = 0;
    let mut options = 0;
    for n in &story.nodes {
        match &n.kind {
            galatea_core::NodeKind::Say { text, .. } => {
                say_nodes += 1;
                chars += text.chars().count();
            }
            galatea_core::NodeKind::End { .. } => ends += 1,
            galatea_core::NodeKind::Choice { options: os, .. } => {
                choices += 1;
                options += os.len();
            }
            _ => {}
        }
    }
    let issues = lint::lint(&story);
    let (e, w, _) = lint::summary(&issues);
    // 用 VM 全空跑一遍，看看最多能读到多少节点
    let mut vm = Vm::new(story.clone());
    let mut guard = 0;
    loop {
        guard += 1;
        if guard > 10_000 {
            break;
        }
        match vm.step() {
            Event::Choices { options, .. } => {
                if vm.choose(0).is_err() {
                    break;
                }
                let _ = options.len();
            }
            Event::Say { .. } => {}
            Event::Script { .. } => {}
            Event::Ending { .. } | Event::Halt { .. } => break,
        }
    }
    let (seen, total) = vm.progress();
    println!("《{}》", story.meta.title);
    println!("  节点        {}", story.nodes.len());
    println!("  台词        {} 句 / {} 字", say_nodes, chars);
    println!("  选择节点    {} 个（共 {} 个选项）", choices, options);
    println!("  结局        {} 个", ends);
    println!("  变量        {}", story.vars.len());
    println!("  角色        {}", story.characters.len());
    println!("  主线路过    {}/{} 个节点", seen, total);
    println!("  体检        {} 错误 / {} 警告", e, w);
    Ok(())
}

fn cmd_play(file: &str) -> Result<(), String> {
    let story = load(file)?;
    let title = story.meta.title.clone();
    let mut vm = Vm::new(story);
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();

    println!("═══ {} ═══", title);
    println!("（回车继续，数字选择，u 撤销，s 存档，l 读档，q 退出）\n");

    loop {
        match vm.step() {
            Event::Say {
                speaker_name,
                text,
                ..
            } => {
                let text = interpolate(&vm, &text);
                if speaker_name.is_empty() {
                    println!("  {}", text);
                } else {
                    println!("【{}】{}", speaker_name, text);
                }
                print!("> ");
                io::stdout().flush().ok();
                let line = match lines.next() {
                    Some(Ok(l)) => l,
                    _ => break,
                };
                match line.trim() {
                    "q" | "quit" | "exit" => break,
                    "u" | "undo" => {
                        if vm.undo() {
                            println!("（已回退）\n");
                        } else {
                            println!("（没有可以回退的了）\n");
                        }
                    }
                    "s" | "save" => {
                        std::fs::write("save.json", vm.save()).ok();
                        println!("（已存到 save.json）\n");
                    }
                    "l" | "load" => match std::fs::read_to_string("save.json") {
                        Ok(src) => match galatea_core::json::parse(&src) {
                            Ok(j) => {
                                vm.load(&j).ok();
                                println!("（已读档）\n");
                            }
                            Err(e) => println!("（存档坏了：{}）\n", e),
                        },
                        Err(_) => println!("（没有存档）\n"),
                    },
                    _ => println!(),
                }
            }
            Event::Choices { prompt, options, .. } => {
                if !prompt.is_empty() {
                    println!("\n  —— {} ——", prompt);
                }
                for (i, o) in options.iter().enumerate() {
                    println!("  [{}] {}", i + 1, o.text);
                }
                print!("? ");
                io::stdout().flush().ok();
                let line = match lines.next() {
                    Some(Ok(l)) => l,
                    _ => break,
                };
                let t = line.trim();
                if t == "q" {
                    break;
                }
                if t == "u" {
                    vm.undo();
                    continue;
                }
                match t.parse::<usize>() {
                    Ok(n) if n >= 1 && n <= options.len() => {
                        if let Err(e) = vm.choose(n - 1) {
                            println!("（{}）", e);
                        }
                        println!();
                    }
                    _ => println!("（请输入 1..{}）", options.len()),
                }
            }
            Event::Ending { ending, text, .. } => {
                println!("\n★ 结局 [{}] {}", ending, text);
                let (seen, total) = vm.progress();
                println!("（本次路过 {}/{} 个节点）", seen, total);
                break;
            }
            Event::Script { entry, ret, emits, .. } => {
                println!("  ⚙ 脚本 {} → 返回 {:?}", entry, ret);
                for (k, v) in emits {
                    println!("     ↳ emit {} = {}", k, v.to_string());
                }
                print!("> ");
                io::stdout().flush().ok();
                match lines.next() {
                    Some(Ok(l)) if l.trim() == "q" => break,
                    _ => println!(),
                }
            }
            Event::Halt { reason } => {
                println!("\n（停下：{}）", reason);
                break;
            }
        }
    }
    Ok(())
}

fn cmd_script(file: &str, args: &[String]) -> Result<(), String> {
    let path = std::path::Path::new(file);
    let script = Script::from_file(path)?;
    let get = |_: &str| ScriptValue::Null;

    if args.is_empty() {
        println!("{}：{} 个函数", script.name, script.program.functions.len());
        for f in &script.program.functions {
            println!("  fn {}({})", f.name, f.params.join(", "));
        }
        println!();
        println!("用法：galatea script <文件> <函数> [参数…]");
        println!("      galatea script <文件> <函数> --sample 0 1 20");
        return Ok(());
    }

    let fname = &args[0];

    if args.len() >= 2 && args[1] == "--sample" {
        let from: f64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(0.0);
        let to: f64 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(1.0);
        let steps: usize = args.get(4).and_then(|s| s.parse().ok()).unwrap_or(16);
        println!("采样 {}(t)：{} → {}，{} 步", fname, from, to, steps);
        for i in 0..=steps {
            let t = from + (to - from) * (i as f64 / steps.max(1) as f64);
            let r = script.call(fname, vec![ScriptValue::Num(t)], &get)?;
            let v = r.ret.unwrap_or(ScriptValue::Num(0.0)).num();
            let width = ((v.abs() * 1.6) as usize).min(40);
            let pad = 40usize.saturating_sub(width);
            println!("  t={:6.3} v={:8.4} {}{}", t, v, " ".repeat(pad), "#".repeat(width));
        }
        return Ok(());
    }

    let mut call_args = Vec::new();
    for a in &args[1..] {
        if let Ok(n) = a.parse::<f64>() {
            call_args.push(ScriptValue::Num(n));
        } else if a == "true" {
            call_args.push(ScriptValue::Bool(true));
        } else if a == "false" {
            call_args.push(ScriptValue::Bool(false));
        } else {
            call_args.push(ScriptValue::Str(a.clone()));
        }
    }

    let r = script.call(fname, call_args, &get)?;
    match &r.ret {
        Some(ScriptValue::Num(n)) => println!("返回：{}", n),
        Some(ScriptValue::Str(s)) => println!("返回：\"{}\"", s),
        Some(v) => println!("返回：{:?}", v),
        None => println!("返回：空"),
    }
    for (k, v) in &r.vars {
        println!("set {} = {:?} → {:?}", k, v, v.to_json().to_string());
    }
    for (k, v) in &r.emits {
        println!("emit {} = {:?}", k, v);
    }
    println!("（执行 {} 步）", r.steps);
    Ok(())
}

/// 把台词里的 `{变量名}` 替换成当前值
fn interpolate(vm: &Vm, text: &str) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(start) = rest.find('{') {
        out.push_str(&rest[..start]);
        let tail = &rest[start..];
        match tail.find('}') {
            Some(end) => {
                let name = &tail[1..end];
                out.push_str(&vm.var(name.trim()).as_display());
                rest = &tail[end + 1..];
            }
            None => {
                out.push_str(tail);
                rest = "";
            }
        }
    }
    out.push_str(rest);
    out
}

fn human(n: u64) -> String {
    if n >= 1024 * 1024 {
        format!("{:.1}MB", n as f64 / 1048576.0)
    } else if n >= 1024 {
        format!("{:.1}KB", n as f64 / 1024.0)
    } else {
        format!("{}B", n)
    }
}

fn cmd_pack(story_path: &str, args: &[String]) -> Result<(), String> {
    let path = std::path::Path::new(story_path);
    let json = std::fs::read_to_string(path)
        .map_err(|e| format!("读不到 {}：{}", story_path, e))?;
    let dir = path.parent().unwrap_or_else(|| std::path::Path::new("."));

    // 剧本统一走「字符串池化」编码：重复的说话人 / 资源路径 / 字段值
    // 只存进池子一次，其余位置写 {"$s":索引} 引用。
    // 这是 .gal 唯一的剧本编码，不再保留「原始 JSON」分支。
    let pooled = galatea_core::compact::pack_str(&json)?;
    println!(
        "   剧本编码：池化 {}B → 压缩后 {}B",
        pooled.len(),
        gal::deflate_len(pooled.as_bytes())
    );
    let chosen = pooled;

    let mut files: BTreeMap<String, Vec<u8>> = BTreeMap::new();
    files.insert("story.gala.json".to_string(), chosen.into_bytes());

    // 资源可能在剧本目录、app/、web/ 或当前目录下，挨个找
    let candidates: Vec<std::path::PathBuf> = vec![
        dir.to_path_buf(),
        dir.join("..").join("app"),
        dir.join("..").join("web"),
        std::path::PathBuf::from("."),
        std::path::PathBuf::from(".."),
    ];
    let mut missing = Vec::new();
    for rel in gal::collect_assets(&json) {
        let mut found = None;
        for base in &candidates {
            let p = base.join(&rel);
            if p.is_file() {
                found = Some(p);
                break;
            }
        }
        match found.and_then(|p| std::fs::read(p).ok()) {
            Some(b) => {
                // 用剧本里的相对路径做条目名，解包后路径一致
                files.insert(rel, b);
            }
            None => missing.push(rel),
        }
    }

    let bytes = gal::pack(&files)?;
    let out = args
        .iter()
        .position(|a| a == "-o" || a == "--out")
        .and_then(|i| args.get(i + 1).cloned())
        .unwrap_or_else(|| path.with_extension("gal").to_string_lossy().to_string());
    std::fs::write(&out, &bytes).map_err(|e| format!("写不了 {}：{}", out, e))?;

    let raw_total: usize = files.values().map(|v| v.len()).sum();
    println!("📦 打包完成：{}", out);
    println!("   条目 {} 个 · 原始 {} → 压缩后 {}", files.len(), human(raw_total as u64), human(bytes.len() as u64));
    if raw_total > 0 {
        println!("   压缩率 {:.1}%（省下 {}）", bytes.len() as f64 / raw_total as f64 * 100.0, human((raw_total.saturating_sub(bytes.len())) as u64));
    }
    for (name, data) in &files {
        println!("     {:<44} {:>10}", name, human(data.len() as u64));
    }
    if !missing.is_empty() {
        println!("   ⚠ 剧本里有 {} 个资源在磁盘上找不到（未打包）：", missing.len());
        for m in missing.iter().take(8) {
            println!("     - {}", m);
        }
    }
    println!();
    println!("   试玩：galatea play {}", out);
    Ok(())
}

fn cmd_unpack(gal_path: &str, args: &[String]) -> Result<(), String> {
    let bytes = std::fs::read(gal_path).map_err(|e| format!("读不到 {}：{}", gal_path, e))?;
    let arc = gal::parse(&bytes)?;
    let out = args
        .iter()
        .position(|a| a == "-o" || a == "--out")
        .and_then(|i| args.get(i + 1).cloned())
        .unwrap_or_else(|| {
            gal_path
                .trim_end_matches(".gal")
                .to_string()
        });
    let dir = std::path::Path::new(&out);
    for e in &arc.entries {
        let p = dir.join(&e.name);
        if let Some(parent) = p.parent() {
            std::fs::create_dir_all(parent).map_err(|x| x.to_string())?;
        }
        let data = arc.read(&e.name)?;
        std::fs::write(&p, &data).map_err(|x| format!("写不了 {}：{}", p.display(), x))?;
    }
    println!("📂 已解开 {} 个条目 → {}", arc.entries.len(), out);
    Ok(())
}

fn cmd_info(gal_path: &str) -> Result<(), String> {
    let bytes = std::fs::read(gal_path).map_err(|e| format!("读不到 {}：{}", gal_path, e))?;
    let arc = gal::parse(&bytes)?;
    println!("📦 {}  ({} 个条目)", gal_path, arc.entries.len());
    println!("   文件大小 {} · 内容原始 {} · 压缩率 {:.1}%",
        human(bytes.len() as u64),
        human(arc.total_raw()),
        arc.total_packed() as f64 / arc.total_raw().max(1) as f64 * 100.0);
    println!();
    println!("   {:<44} {:>9} {:>9} {:>7}  {}", "名称", "原始", "压缩后", "比例", "方式");
    for e in &arc.entries {
        println!("   {:<44} {:>9} {:>9} {:>6.1}%  {}",
            e.name,
            human(e.usize),
            human(e.csize),
            e.ratio() * 100.0,
            if e.method == 1 { "deflate" } else { "原样" });
    }
    Ok(())
}


// ── 导出 Godot 项目 ──────────────────────────────────────────
// Godot 引擎本体由作者自行安装（https://godotengine.org/download）。
// Galatea 只负责：剧情/变量/动画在本体算好 → 打包 .gal → 连同引用的 .gd
// 一起生成一个可直接打开的 Godot 项目。运行时是纯 GDScript，零扩展依赖。
const RT_GALATEA: &str = include_str!("../../../../godot/runtime/galatea.gd");
const RT_MAIN: &str = include_str!("../../../../godot/runtime/main.gd");

const MAIN_TSCN: &str = r#"[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/main.gd" id="1"]

[node name="Galatea" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
"#;

fn project_godot(title: &str) -> String {
    format!(r#"; Galatea 导出的 Godot 项目。用你自己安装的 Godot 4.2+ 打开即可运行。
config_version=5

[application]

config/name="{title}"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.2", "GL Compatibility")

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/handheld/orientation=0

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=1
"#)
}

fn cmd_export_godot(file: &str, args: &[String]) -> Result<(), String> {
    use std::path::Path;
    let opt = |keys: &[&str]| -> Option<String> {
        args.iter().position(|a| keys.contains(&a.as_str()))
            .and_then(|i| args.get(i + 1).cloned())
    };
    let out = opt(&["-o", "--out"]).unwrap_or_else(|| "godot-export".into());
    let scripts_root = opt(&["--scripts", "-s"]).unwrap_or_else(|| ".".into());
    let dir = Path::new(&out);
    std::fs::create_dir_all(dir).map_err(|e| format!("建不了目录 {}：{}", out, e))?;

    let story = load(file)?;
    let title = story.meta.title.clone();

    // 1) 剧情包：.gal 原样拷；.json 先打包（.gal 是唯一交付格式）
    let pkg_path = dir.join("story.gal");
    let pkg_bytes = if file.ends_with(".gal") {
        std::fs::read(file).map_err(|e| format!("读不到 {}：{}", file, e))?
    } else {
        let src = std::fs::read_to_string(file).map_err(|e| format!("读不到 {}：{}", file, e))?;
        let doc = galatea_core::json::parse(&src)?;
        let mut files = std::collections::BTreeMap::new();
        files.insert("doc".to_string(), galatea_core::compact::pack_str(&src)?.into_bytes());
        let _ = doc;
        gal::pack(&files)?
    };
    std::fs::write(&pkg_path, &pkg_bytes).map_err(|e| format!("写不了 story.gal：{}", e))?;

    // 2) 运行时 + 场景 + 工程配置
    let put = |rel: &str, data: &[u8]| -> Result<(), String> {
        let p = dir.join(rel);
        if let Some(par) = p.parent() {
            std::fs::create_dir_all(par).map_err(|e| e.to_string())?;
        }
        std::fs::write(&p, data).map_err(|e| format!("写不了 {}：{}", rel, e))
    };
    put("runtime/galatea.gd", RT_GALATEA.as_bytes())?;
    put("scenes/main.gd", RT_MAIN.as_bytes())?;
    put("scenes/main.tscn", MAIN_TSCN.as_bytes())?;
    put("project.godot", project_godot(&title).as_bytes())?;

    // 3) 素材：包里除 doc / 字符串池以外的条目，按原相对路径落盘
    let arc = gal::parse(&pkg_bytes)?;
    let mut assets = 0usize;
    for e in &arc.entries {
        // doc / 字符串池是剧情数据（已在 story.gal 里），.json 是打包时的源稿，都不是素材
        if e.name == "doc" || e.name.starts_with("$gal/") || e.name.ends_with(".json") { continue; }
        put(&e.name, &arc.read(&e.name)?)?;
        assets += 1;
    }

    // 4) 脚本引用：逐个校验存在，缺了就报错（绝不静默跳过）
    let mut scripts = 0usize;
    for n in &story.nodes {
        let (engine, src_rel) = match &n.kind {
            galatea_core::graph::NodeKind::Script { engine, src, .. } => (engine, src),
            _ => continue,
        };
        if !matches!(engine, galatea_core::graph::ScriptEngine::Godot) { continue; }
        let rel = match src_rel {
            Some(s) if !s.trim().is_empty() => s.clone(),
            _ => return Err(format!("节点 `{}` 是 godot 脚本块但没填引用路径。\n  \
                怎么修：在编辑器里给它指定一个 .gd 文件（相对项目根，如 scripts/minigame.gd）", n.id)),
        };
        // 引用路径可能写成 res://scripts/x.gd（Godot 风格），落盘时剥掉前缀
        let rel_local = rel.trim_start_matches("res://").to_string();
        let from = Path::new(&scripts_root).join(&rel_local);
        if !from.is_file() {
            return Err(format!("节点 `{}` 引用的脚本不存在：{}\n  \
                怎么修：把 .gd 放到该路径，或用 --scripts <目录> 指定脚本根目录",
                n.id, from.display()));
        }
        let data = std::fs::read(&from).map_err(|e| format!("读不了 {}：{}", from.display(), e))?;
        put(&rel_local, &data)?;
        scripts += 1;
    }

    println!("🎮 已导出 Godot 项目 → {}", out);
    println!("   剧情包 story.gal   素材 {} 个   引用脚本 {} 个", assets, scripts);
    println!("   下一步：用 Godot 4.2+ 打开 {}/project.godot，F5 运行，或「项目→导出」出游戏。", out);
    if scripts == 0 {
        println!("   （没有 godot 脚本块 —— 纯剧情，开箱即跑）");
    }
    Ok(())
}
