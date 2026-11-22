/// 播放器：把一张剧情图跑成一部 Galgame。
/// 编辑器里的"试玩"和将来导出的独立游戏，用的都是这一套 UI + 同一个 VM。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../engine/vm.dart';
import '../models/graph.dart';
import '../storage/store.dart';
import '../theme.dart';

class PlayerPage extends StatefulWidget {
  final Story story;
  const PlayerPage({super.key, required this.story});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late Vm vm;
  VmEvent? event;
  String shown = '';
  Timer? _typer;
  Timer? _autoTimer;
  bool _auto = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    vm = Vm(widget.story);
    _advance();
  }

  @override
  void dispose() {
    _typer?.cancel();
    _autoTimer?.cancel();
    super.dispose();
  }

  void _advance() {
    final e = vm.step();
    _apply(e);
  }

  void _apply(VmEvent e) {
    _typer?.cancel();
    setState(() {
      event = e;
      shown = '';
    });
    if (e is SayEvent) {
      final full = _interpolate(e.text);
      var i = 0;
      _typer = Timer.periodic(const Duration(milliseconds: 24), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        i++;
        if (i >= full.length) {
          t.cancel();
          setState(() => shown = full);
          _scheduleAuto();
        } else {
          setState(() => shown = full.substring(0, i));
        }
      });
    } else if (e is EndingEvent) {
      setState(() => shown = e.text);
    }
  }

  /// 台词里的 {变量} 替换成当前值
  String _interpolate(String text) {
    return text.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) {
      final v = vm.varValue(m.group(1)!.trim());
      if (v == null) return '';
      if (v is num && v == v.roundToDouble()) return v.toInt().toString();
      return '$v';
    });
  }

  void _scheduleAuto() {
    _autoTimer?.cancel();
    if (!_auto) return;
    _autoTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      final e = event;
      if (e is SayEvent) _advance();
    });
  }

  void _tapText() {
    final e = event;
    if (e is SayEvent) {
      final full = _interpolate(e.text);
      if (shown.length < full.length) {
        _typer?.cancel();
        setState(() => shown = full);
        _scheduleAuto();
        return;
      }
    }
    _advance();
  }

  void _choose(int i) {
    final e = vm.choose(i);
    _apply(e);
  }

  void _undo() {
    if (vm.undo()) {
      _advance();
    } else {
      _toast('已经是最开头了');
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final d = await ProjectStore.dir();
      final f = File('${d.path}/${widget.story.title}.save.json');
      await f.writeAsString(jsonEncode(vm.saveJson()), flush: true);
      _toast('已存档');
    } catch (e) {
      _toast('存档失败：$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final d = await ProjectStore.dir();
      final f = File('${d.path}/${widget.story.title}.save.json');
      if (!await f.exists()) {
        _toast('还没有存档');
      } else {
        final raw = jsonDecode(await f.readAsString());
        if (raw is Map) {
          vm.loadJson(Map<String, dynamic>.from(raw));
          _advance();
          _toast('已读档');
        }
      }
    } catch (e) {
      _toast('读档失败：$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GColors.panel,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('回想',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (vm.log.isEmpty)
              const Text('还没有读过任何台词',
                  style: TextStyle(color: GColors.dim)),
            for (final line in vm.log)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(line,
                    style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = event;
    final say = e is SayEvent ? e : null;
    final choices = e is ChoicesEvent ? e : null;
    final ending = e is EndingEvent ? e : null;
    final halt = e is HaltEvent ? e : null;
    final (seen, total) = vm.progress();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _background(say)),
          if (say?.portrait != null)
            Positioned(
              right: 20,
              bottom: 190,
              child: _portrait(say!.portrait!),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    ),
                    Expanded(
                      child: Text(
                        widget.story.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    Text('$seen/$total',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                    IconButton(
                      tooltip: '自动',
                      onPressed: () {
                        setState(() => _auto = !_auto);
                        _scheduleAuto();
                      },
                      icon: Icon(
                        _auto ? Icons.pause_circle : Icons.play_circle_outline,
                        color: _auto ? GColors.accent : Colors.white54,
                      ),
                    ),
                    IconButton(
                      tooltip: '回退',
                      onPressed: _undo,
                      icon: const Icon(Icons.undo, color: Colors.white54),
                    ),
                    IconButton(
                      tooltip: '回想',
                      onPressed: _showHistory,
                      icon: const Icon(Icons.history, color: Colors.white54),
                    ),
                    IconButton(
                      tooltip: '存档',
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_outlined, color: Colors.white54),
                    ),
                    IconButton(
                      tooltip: '读档',
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.folder_open, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: choices != null
                    ? _choiceList(choices)
                    : (ending != null
                        ? _endingCard(ending)
                        : (halt != null
                            ? _haltCard(halt)
                            : _dialogue(say))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _background(SayEvent? say) {
    final tint = say?.color != null ? _parseColor(say!.color!) : null;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(const Color(0xFF101522), tint ?? Colors.black, 0.22)!,
            const Color(0xFF05070C),
          ],
        ),
      ),
      child: say?.bg == null
          ? null
          : Image.asset(say!.bg!, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
              return const SizedBox.shrink();
            }),
    );
  }

  Widget _portrait(String path) {
    return Image.asset(
      path,
      height: 320,
      errorBuilder: (_, __, ___) => Container(
        width: 150,
        height: 320,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              GColors.accent.withOpacity(0.25),
              Colors.transparent,
            ],
          ),
        ),
        child: const Center(
          child: Text('立绘\n（资源未接入）',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _dialogue(SayEvent? say) {
    final name = say?.speakerName ?? '';
    final color = say?.color != null
        ? (_parseColor(say!.color!) ?? GColors.accent)
        : GColors.dim;
    return GestureDetector(
      onTap: _tapText,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 150),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: BoxDecoration(
          color: const Color(0xEE0D1119),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (name.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withOpacity(0.6)),
                ),
                child: Text(name,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            Text(
              shown.isEmpty ? ' ' : shown,
              style: const TextStyle(
                  fontSize: 15.5, height: 1.7, color: GColors.text),
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('▼',
                  style: TextStyle(fontSize: 10, color: Colors.white24)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceList(ChoicesEvent e) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (e.prompt.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(e.prompt,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.5)),
          ),
        for (var i = 0; i < e.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _choose(i),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xEE141A26),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: GColors.accent2.withOpacity(0.55)),
                ),
                child: Text(
                  e.options[i].text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14.5, color: GColors.text),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _endingCard(EndingEvent e) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xEE0D1119),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GColors.warn.withOpacity(0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('★ 结局',
              style: TextStyle(color: GColors.warn, fontSize: 13)),
          const SizedBox(height: 6),
          Text(e.ending,
              style: const TextStyle(
                  color: GColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(e.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: GColors.text, fontSize: 14, height: 1.6)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () {
                  vm.restart();
                  _advance();
                },
                child: const Text('再来一次'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('回到编辑器'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _haltCard(HaltEvent e) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xEE0D1119),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GColors.err.withOpacity(0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(e.reason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: GColors.err, fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('回去修剧本'),
          ),
        ],
      ),
    );
  }
}

Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(v);
}