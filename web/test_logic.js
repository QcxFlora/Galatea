// Galatea Web 核心逻辑冒烟测试（node 运行，无 DOM）
// 提取 <script> 前半部分纯逻辑，验证与 Rust galatea-core 行为一致
const fs = require('fs');
const html = fs.readFileSync(__dirname + '/index.html', 'utf8');
const m = html.match(/<script>([\s\S]*)<\/script>/);
const src = m[1];
const cut = src.indexOf('/* \u2500──── 6.');
if (cut < 0) throw new Error('找不到分割点');
const head = src.slice(0, cut);

const api = new Function('STORY', head + `
  return {setStory: s => { STORY = s; },
          parseExpr, evalExpr, evalCond, truthy, tokenize,
          vmNew, vmStep, vmChoose, vmGet, vmSet, vmUndo, vmSave, vmLoad,
          lintStory, nodeById, blankStory, nodePorts, portTarget, setPort};
`);
const demo = JSON.parse(fs.readFileSync(__dirname + '/../samples/rain.json', 'utf8'));
const T = api(demo);

let pass = 0, fail = 0;
function eq(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (ok) { pass++; } else { fail++; console.log(`  ✗ ${name}\n    got  ${JSON.stringify(got)}\n    want ${JSON.stringify(want)}`); }
}
function stepUntil(vm, pred) {
  let e, guard = 0;
  do { e = T.vmStep(vm); if (++guard > 60) throw new Error('stepUntil 死循环'); } while (!pred(e));
  return e;
}

// ── 表达式 ──
console.log('◆ 表达式引擎');
eq('四则优先级', T.evalExpr('1 + 2 * 3 == 7', () => null), true);
eq('括号', T.evalExpr('(1 + 2) * 3 == 9', () => null), true);
eq('逻辑', T.evalExpr('!(1 > 2) || 0', () => null), true);
eq('字符串拼接', T.evalExpr('"你好，" + 名字', n => n === '名字' ? '雪' : null), '你好，雪');
eq('中文变量比较', T.evalExpr('好感 >= 3', n => n === '好感' ? 3 : null), true);
eq('空条件恒真', T.evalCond('', () => null), true);
eq('语法错误→null', T.parseExpr('aff >'), null);
eq('未闭合字符串', T.parseExpr('"abc'), null);
eq('点号路径', T.evalExpr('a.b > 2', n => n === 'a.b' ? 5 : null), true);

// ── VM：demo 主线 ──
console.log('◆ VM（示例剧本《雨声与自动门》）');
let vm = T.vmNew(demo);
let e = T.vmStep(vm);
eq('第一句是旁白', e.k, 'say');
eq('开场白', e.text && e.text.slice(0, 5), '雨下得很大');
e = stepUntil(vm, x => x.k === 'choices');
eq('第一个选择', e.k, 'choices');
eq('两个选项', e.options.length, 2);
e = T.vmChoose(vm, 0); // 在店里等
eq('等待台词', e.k, 'say');
eq('aff+1', T.vmGet(vm, 'aff'), 1);
e = stepUntil(vm, x => x.k === 'choices');
eq('第二个选择', e.k, 'choices');
eq('条件过滤后仍有 2 项', e.options.length, 2);
e = T.vmChoose(vm, 0); // 「你有心事？」（条件 aff>=1 满足）→ say n_ask
eq('她说出转学', e.k, 'say');
e = T.vmStep(vm); // n_set + n_branch 自动推进 → say n_truth
eq('set 后继续', e.k, 'say');
e = T.vmStep(vm); // n_call 子图调用自动 → say n_flash
eq('子图闪回', e.k, 'say');
e = T.vmStep(vm); // n_return 自动 → n_end_farewell
eq('返回后到结局', e.k, 'ending');
eq('结局代号', e.ending, 'farewell');
eq('know=true', T.vmGet(vm, 'know'), true);
e = T.vmStep(vm);
eq('结束后 halt', e.k, 'halt');

// ── 撤销 ──
console.log('◆ 撤销');
vm = T.vmNew(demo);
stepUntil(vm, x => x.k === 'choices');
T.vmChoose(vm, 0);
eq('撤销前 aff', T.vmGet(vm, 'aff'), 1);
eq('撤销成功', T.vmUndo(vm), true);
eq('撤销后 aff 归零', T.vmGet(vm, 'aff'), 0);
stepUntil(vm, x => x.k === 'choices');
eq('回到选择点', true, true);

// ── 存读档 ──
console.log('◆ 存读档');
vm = T.vmNew(demo);
stepUntil(vm, x => x.k === 'choices');
T.vmChoose(vm, 0);
const snap = T.vmSave(vm);
const vm2 = T.vmNew(demo);
T.vmLoad(vm2, snap);
eq('读档恢复变量', T.vmGet(vm2, 'aff'), 1);
eq('读档后继续是选择', T.vmStep(vm2).k, 'choices');

// ── lint ──
console.log('◆ lint');
eq('demo 剧本零错误', T.lintStory(demo).filter(i => i.lv === 'err').length, 0);
const bad = T.blankStory('t');
bad.nodes = [
  {id:'a', type:'say', x:0, y:0, text:'hi', next:'ghost'},
  {id:'b', type:'say', x:0, y:100, text:'孤岛'},
];
bad.meta.start = 'a';
T.setStory(bad);
const issues = T.lintStory(bad);
T.setStory(demo);
eq('断线检测', issues.some(i => i.msg.includes('不存在')), true);
eq('孤岛检测', issues.some(i => i.lv === 'warn' && i.node === 'b'), true);
eq('无结局检测', issues.some(i => i.msg.includes('走不到任何结局')), true);

// ── 端口编辑 ──
console.log('◆ 端口');
const n = T.nodeById('n_choice1');
eq('opt0 → n_wait', T.portTarget(n, 'opt0'), 'n_wait');
T.setPort(n, 'opt0', null);
eq('断开 opt0', T.portTarget(n, 'opt0'), null);
T.setPort(n, 'opt0', 'n_wait');
eq('重连 opt0', T.portTarget(n, 'opt0'), 'n_wait');

console.log(`\n${'─'.repeat(40)}\n${pass} 通过 / ${fail} 失败`);
process.exit(fail ? 1 : 0);