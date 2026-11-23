import 'dart:convert';

import 'package:galatea_studio/engine/expr.dart';
import 'package:galatea_studio/engine/vm.dart';
import 'package:galatea_studio/models/graph.dart';
import 'package:flutter_test/flutter_test.dart';

Story buildSample() {
  final s = Story(title: '测试');
  s.characters['yuki'] = Character(name: '雪', color: '#7AA2F7');
  s.vars['aff'] = 0;
  s.nodes.addAll([
    StoryNode(id: 's1', type: NodeType.say, casts: ['yuki'], text: '早上好。', next: 'c1'),
    StoryNode(
      id: 'c1',
      type: NodeType.choice,
      prompt: '怎么回答？',
      options: [
        Choice(text: '早上好', to: 's2', effects: [Effect(target: 'aff', op: EffectOp.add, expr: '1')]),
        Choice(text: '……', to: 's3'),
      ],
    ),
    StoryNode(id: 's2', type: NodeType.say, text: '今天也很早呢。', next: 'e1'),
    StoryNode(id: 's3', type: NodeType.say, text: '沉默。', next: 'e1'),
    StoryNode(id: 'e1', type: NodeType.end, ending: 'good', endText: '完'),
  ]);
  s.start = 's1';
  return s;
}

void main() {
  group('表达式', () {
    test('四则与逻辑', () {
      expect(evalExpr('1 + 2 * 3 == 7', (_) => null), true);
      expect(evalExpr('(1 + 2) * 3 == 9', (_) => null), true);
      expect(evalExpr('!(1 > 2) || 0', (_) => null), true);
    });
    test('中文变量与字符串拼接', () {
      expect(evalExpr('"你好，" + 名字', (n) => n == '名字' ? '雪' : null), '你好，雪');
      expect(evalExpr('好感 >= 3', (n) => n == '好感' ? 3 : null), true);
    });
    test('语法错误返回 null', () {
      expect(parseExpr('aff >'), isNull);
      expect(parseExpr('(1 + 2'), isNull);
      expect(parseExpr('"未闭合'), isNull);
    });
    test('变量收集', () {
      final e = parseExpr('a == 1 && b.c > 2')!;
      expect(exprVars(e), ['a', 'b.c']);
    });
  });

  group('VM', () {
    test('分支完成度: 断头分支不算完成', () {
      final s = Story(title: 't', start: 'a');
      s.nodes.addAll([
        StoryNode(id: 'a', type: NodeType.say, text: '起', next: 'good'),
        StoryNode(id: 'good', type: NodeType.say, text: '好', next: 'e'),
        StoryNode(id: 'dead', type: NodeType.say, text: '断'),
        StoryNode(id: 'e', type: NodeType.end, ending: 'g'),
      ]);
      final r = s.reachesEnd();
      expect(r.contains('a'), true);
      expect(r.contains('good'), true);
      expect(r.contains('dead'), false);
      expect(s.completion(), (3, 4));
    });
    test('完成度标记往返 + 进度', () {
      final s = Story(title: 't');
      s.nodes.addAll([
        StoryNode(id: 'a', type: NodeType.say, text: '一'),
        StoryNode(id: 'b', type: NodeType.say, text: '二'),
        StoryNode(id: 'e', type: NodeType.end, ending: 'g'),
      ]);
      s.setStatus('a', 'done');
      s.setStatus('b', 'wip');
      expect(s.progress(), (1, 1, 1));
      final s2 = Story.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(s2.toJson(), s.toJson());
      expect(s2.progress(), (1, 1, 1));
      s2.setStatus('a', 'todo');
      expect(s2.status.containsKey('a'), false);
      expect(s2.progress(), (2, 1, 0));
    });
    test('图块/音频块 JSON 往返', () {
      final s = Story(title: 't');
      s.nodes.addAll([
        StoryNode(id: 'img', type: NodeType.image, tag: 'bg1', asset: 'assets/bg.webp', text: '雨夜'),
        StoryNode(id: 'aud', type: NodeType.audio, tag: 'bgm1', asset: 'assets/r.ogg',
            audioKind: 'bgm', audioLoop: true, audioVolume: 0.8, next: 'a'),
        StoryNode(id: 'a', type: NodeType.say, text: 'hi', next: 'e'),
        StoryNode(id: 'e', type: NodeType.end, ending: 'g', endText: '完'),
      ]);
      final s2 = Story.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(s2.toJson(), s.toJson());
      expect(s2.nodeById('img')!.type, NodeType.image);
      expect(s2.nodeById('aud')!.audioVolume, 0.8);
    });
    test('图块解析 art/bg + 音频块发 AudioEvent', () {
      final s = Story(title: 't', start: 'say1');
      s.nodes.addAll([
        StoryNode(id: 'img', type: NodeType.image, tag: 'k', asset: 'assets/x.webp'),
        StoryNode(id: 'say1', type: NodeType.say, text: 'hi', next: 'aud', arts: ['img'], bgs: ['img']),
        StoryNode(id: 'aud', type: NodeType.audio, tag: 'b', asset: 'assets/r.ogg',
            audioKind: 'bgm', audioLoop: true, audioVolume: 0.5, next: 'end'),
        StoryNode(id: 'end', type: NodeType.end, ending: 'g', endText: '完'),
      ]);
      final vm = Vm(s);
      final e1 = vm.step();
      expect(e1, isA<SayEvent>());
      expect((e1 as SayEvent).portrait, 'assets/x.webp');
      expect(e1.bg, 'assets/x.webp');
      final e2 = vm.step();
      expect(e2, isA<AudioEvent>());
      expect((e2 as AudioEvent).path, 'assets/r.ogg');
      expect(e2.kind, 'bgm');
      expect(e2.volume, 0.5);
    });
    test('主线流程', () {
      final vm = Vm(buildSample());
      final e1 = vm.step();
      expect(e1, isA<SayEvent>());
      expect((e1 as SayEvent).speakerName, '雪');
      final e2 = vm.step();
      expect(e2, isA<ChoicesEvent>());
      expect((e2 as ChoicesEvent).options.length, 2);
      final e3 = vm.choose(0);
      expect(e3, isA<SayEvent>());
      expect(vm.varValue('aff'), 1);
      expect(vm.step(), isA<EndingEvent>());
      expect(vm.step(), isA<HaltEvent>());
    });
    test('撤销回滚变量', () {
      final vm = Vm(buildSample());
      vm.step();
      vm.step();
      vm.choose(0);
      expect(vm.varValue('aff'), 1);
      expect(vm.undo(), true);
      expect(vm.varValue('aff'), 0);
    });
    test('存读档', () {
      final vm = Vm(buildSample());
      vm.step();
      vm.step();
      vm.choose(0);
      final snap = vm.saveJson();
      final vm2 = Vm(buildSample());
      vm2.loadJson(Map<String, dynamic>.from(snap));
      expect(vm2.varValue('aff'), 1);
      expect(vm2.step(), isA<EndingEvent>());
    });
  });

  group('模型', () {
    test('JSON 往返', () {
      final s = buildSample();
      final s2 = Story.fromJson(
          Map<String, dynamic>.from(jsonDecode(s.toPrettyJson()) as Map));
      expect(s2.nodes.length, s.nodes.length);
      expect(s2.start, 's1');
      expect(s2.toPrettyJson(), s.toPrettyJson());
    });
    test('端口与断线', () {
      final s = buildSample();
      expect(s.nodeById('c1')!.portTarget('opt0'), 's2');
      s.removeNode('s2');
      expect(s.nodeById('c1')!.portTarget('opt0'), isNull);
    });
  });
}