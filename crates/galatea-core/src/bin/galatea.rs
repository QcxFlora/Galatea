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
use galatea_core::vm::{Event, Vm};
use std::io::{self, BufRead, Write};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        usage();
        std::process::exit(2);
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
}

fn load(file: &str) -> Result<Story, String> {
    let src = std::fs::read_to_string(file).map_err(|e| format!("读不到 {}：{}", file, e))?;
    Story::from_json_str(&src)
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
            speaker: Some("yuki".into()),
            text: "……你终于来了。".into(),
            bg: None,
            portrait: None,
            next: Some("ask".into()),
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
            speaker: Some("yuki".into()),
            text: "那就好。".into(),
            bg: None,
            portrait: None,
            next: Some("end_good".into()),
        },
    });
    s.add_node(Node {
        id: "bad".into(),
        x: 200.0,
        y: 300.0,
        title: None,
        kind: galatea_core::NodeKind::Say {
            speaker: None,
            text: "她的眼神暗了下去。".into(),
            bg: None,
            portrait: None,
            next: Some("end_bad".into()),
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
            Event::Halt { reason } => {
                println!("\n（停下：{}）", reason);
                break;
            }
        }
    }
    Ok(())
}