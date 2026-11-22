// Galatea 自定义脚本示例 —— 自己搓动画、自己搓首界面
//
// 语法是 Rust 的一个安全子集（fn / let / if / else / while / return），
// 由引擎内置解释器执行：没有 IO、没有 unsafe、跑不出剧本之外。
// 可用内置函数：
//   数学     sin cos sqrt abs floor round pow min max clamp lerp random
//   弹簧     spring(p, response, damping)   与 UI 同一个弹簧参数
//   缓动     ease(t)  ease_out(t)  bump(t, amplitude)
//   演出     set(name, value)  emit(channel, value)  get(name)

// ── 首界面：标题从下方弹入，返回 Y 偏移（像素）
//    t 是 0..1 的进度，动画时长由节点上的 duration 决定
fn title_entry(t) {
    let s = spring(t, 0.25, 0.45);      // Bouncy：会冲过头再弹回来
    return (1.0 - s) * 120.0;
}

// ── 标题淡入
fn title_fade(t) {
    return ease_out(clamp(t / 0.6, 0.0, 1.0));
}

// ── 呼吸光晕：0..1 正弦循环
fn halo(t) {
    return 0.5 + 0.5 * sin(t * 6.2832);
}

// ── 卡片依次进入：第 i 张卡片的 Y 偏移
fn card_entry(t, index) {
    let delay = index * 0.08;
    let p = clamp((t - delay) / 0.4, 0.0, 1.0);
    return (1.0 - spring(p, 0.25, 0.45)) * 60.0;
}

// ── 一次性开场演出：改剧情状态 + 抛出若干演出指令
fn opening() {
    set("看过开场", true);
    emit("bgm", "rain_theme");
    emit("cameraY", 40.0);

    // 三次渐强的弹动，累加成一个节奏
    let beat = 0;
    let i = 0;
    while i < 3 {
        beat = beat + spring(i * 0.35, 0.29, 0.75);
        i = i + 1;
    }
    emit("beat", beat);
    return beat;
}

// ── 按好感度决定名字牌的颜色强度（读剧情变量）
fn nameplate(t) {
    let aff = get("aff");
    return clamp(aff / 5.0, 0.2, 1.0) * ease_out(t);
}