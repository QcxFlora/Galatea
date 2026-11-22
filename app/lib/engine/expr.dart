/// 与 Rust `galatea-core/src/expr.rs` 同语义的小表达式语言。
///
/// 优先级：`||` → `&&` → 比较 → `+ -` → `* / %` → 一元 → 原子
/// 原子：数字 / '字符串' / "字符串" / 「字符串」 / 变量名（支持中文）/ true / false / null
library;

sealed class Expr {}

class ELit extends Expr {
  final Object? value;
  ELit(this.value);
}

class EVar extends Expr {
  final String name;
  EVar(this.name);
}

class EUnary extends Expr {
  final String op;
  final Expr inner;
  EUnary(this.op, this.inner);
}

class EBin extends Expr {
  final String op;
  final Expr left;
  final Expr right;
  EBin(this.op, this.left, this.right);
}

// ---------------------------------------------------------------- 语义工具

bool truthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  if (v is List) return v.isNotEmpty;
  if (v is Map) return v.isNotEmpty;
  return true;
}

num toNum(Object? v) {
  if (v is num) return v;
  if (v is bool) return v ? 1 : 0;
  if (v is String) return num.tryParse(v.trim()) ?? 0;
  return 0;
}

bool looseEq(Object? a, Object? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  if (a is num && b is num) return (a - b).abs() < 1e-9;
  return false;
}

int compare(Object? a, Object? b) {
  if (a is num && b is num) {
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
  }
  if (a is String && b is String) {
    if (a == b) return 0;
    return a.compareTo(b);
  }
  final x = toNum(a);
  final y = toNum(b);
  if (x < y) return -1;
  if (x > y) return 1;
  return 0;
}

String display(Object? v) {
  if (v == null) return '';
  if (v is num) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    return v.toString();
  }
  return '$v';
}

// ---------------------------------------------------------------- 求值

Object? evalExprTree(Expr e, Object? Function(String name) get) {
  if (e is ELit) return e.value;
  if (e is EVar) return get(e.name);
  if (e is EUnary) {
    final v = evalExprTree(e.inner, get);
    if (e.op == '!') return !truthy(v);
    return -toNum(v);
  }
  if (e is EBin) {
    switch (e.op) {
      case '&&':
        if (!truthy(evalExprTree(e.left, get))) return false;
        return truthy(evalExprTree(e.right, get));
      case '||':
        if (truthy(evalExprTree(e.left, get))) return true;
        return truthy(evalExprTree(e.right, get));
      case '==':
        return looseEq(evalExprTree(e.left, get), evalExprTree(e.right, get));
      case '!=':
        return !looseEq(evalExprTree(e.left, get), evalExprTree(e.right, get));
      case '+':
        final a = evalExprTree(e.left, get);
        final b = evalExprTree(e.right, get);
        if (a is String || b is String) return '${display(a)}${display(b)}';
        return toNum(a) + toNum(b);
      case '-':
        return toNum(evalExprTree(e.left, get)) -
            toNum(evalExprTree(e.right, get));
      case '*':
        return toNum(evalExprTree(e.left, get)) *
            toNum(evalExprTree(e.right, get));
      case '/':
        final d = toNum(evalExprTree(e.right, get));
        if (d == 0) return 0;
        return toNum(evalExprTree(e.left, get)) / d;
      case '%':
        final d = toNum(evalExprTree(e.right, get));
        if (d == 0) return 0;
        return toNum(evalExprTree(e.left, get)) % d;
      case '<':
        return compare(evalExprTree(e.left, get),
                evalExprTree(e.right, get)) <
            0;
      case '<=':
        return compare(evalExprTree(e.left, get),
                evalExprTree(e.right, get)) <=
            0;
      case '>':
        return compare(evalExprTree(e.left, get),
                evalExprTree(e.right, get)) >
            0;
      case '>=':
        return compare(evalExprTree(e.left, get),
                evalExprTree(e.right, get)) >=
            0;
    }
  }
  return null;
}

/// 收集表达式里用到的变量名
List<String> exprVars(Expr e) {
  final out = <String>[];
  void walk(Expr x) {
    if (x is EVar) {
      out.add(x.name);
    } else if (x is EUnary) {
      walk(x.inner);
    } else if (x is EBin) {
      walk(x.left);
      walk(x.right);
    }
  }

  walk(e);
  return out;
}

bool exprIsConst(Expr e) {
  if (e is ELit) return true;
  if (e is EVar) return false;
  if (e is EUnary) return exprIsConst(e.inner);
  if (e is EBin) return exprIsConst(e.left) && exprIsConst(e.right);
  return false;
}

/// 解析；空串视为恒真。语法错误返回 null（编辑器会标红）。
Expr? parseExpr(String src) {
  final s = src.trim();
  if (s.isEmpty) return ELit(true);
  final toks = _tokenize(s);
  if (toks == null) return null;
  final p = _ExprParser(toks);
  final e = p.expr(0);
  if (e == null || p.i != toks.length) return null;
  return e;
}

/// 便捷求值：语法错误时返回 null
Object? evalExpr(String src, Object? Function(String name) get) {
  final e = parseExpr(src);
  if (e == null) return null;
  return evalExprTree(e, get);
}

bool evalCond(String src, Object? Function(String name) get) {
  if (src.trim().isEmpty) return true;
  final v = evalExpr(src, get);
  return truthy(v);
}

// ---------------------------------------------------------------- 词法

class _Token {
  final String kind; // num / str / ident / sym
  final String text;
  final num? number;
  const _Token(this.kind, this.text, [this.number]);
}

bool _isDigit(String c) {
  if (c.isEmpty) return false;
  final u = c.codeUnitAt(0);
  return u >= 48 && u <= 57;
}

bool _isIdentChar(String c) {
  if (c.isEmpty) return false;
  final u = c.codeUnitAt(0);
  if (u > 127) return true; // 中文等一律当标识符字符
  if (c == '_') return true;
  return (u >= 48 && u <= 57) ||
      (u >= 65 && u <= 90) ||
      (u >= 97 && u <= 122);
}

List<_Token>? _tokenize(String src) {
  final cs = src.runes.map((r) => String.fromCharCode(r)).toList();
  final out = <_Token>[];
  var i = 0;
  while (i < cs.length) {
    final c = cs[i];
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if (_isDigit(c) ||
        (c == '.' && i + 1 < cs.length && _isDigit(cs[i + 1]))) {
      final start = i;
      while (i < cs.length && (_isDigit(cs[i]) || cs[i] == '.')) {
        i++;
      }
      final text = cs.sublist(start, i).join();
      final n = num.tryParse(text);
      if (n == null) return null;
      out.add(_Token('num', text, n));
      continue;
    }
    if (c == '"' || c == '\'' || c == '「') {
      final close = c == '「' ? '」' : c;
      i++;
      final buf = StringBuffer();
      var closed = false;
      while (i < cs.length) {
        if (cs[i] == '\\' && i + 1 < cs.length) {
          final e = cs[i + 1];
          buf.write(e == 'n' ? '\n' : (e == 't' ? '\t' : e));
          i += 2;
        } else if (cs[i] == close) {
          i++;
          closed = true;
          break;
        } else {
          buf.write(cs[i]);
          i++;
        }
      }
      if (!closed) return null;
      out.add(_Token('str', buf.toString()));
      continue;
    }
    if (_isIdentChar(c)) {
      final start = i;
      while (i < cs.length && (_isIdentChar(cs[i]) || cs[i] == '.')) {
        i++;
      }
      out.add(_Token('ident', cs.sublist(start, i).join()));
      continue;
    }
    final two = (i + 1 < cs.length) ? '$c${cs[i + 1]}' : '';
    if (two == '&&' ||
        two == '||' ||
        two == '==' ||
        two == '!=' ||
        two == '<=' ||
        two == '>=') {
      out.add(_Token('sym', two));
      i += 2;
      continue;
    }
    if ('<>+-*/%!()'.contains(c)) {
      out.add(_Token('sym', c));
      i++;
      continue;
    }
    return null;
  }
  return out;
}

// ---------------------------------------------------------------- 语法

int? _precOf(String s) {
  switch (s) {
    case '||':
      return 1;
    case '&&':
      return 2;
    case '==':
    case '!=':
    case '<':
    case '<=':
    case '>':
    case '>=':
      return 3;
    case '+':
    case '-':
      return 4;
    case '*':
    case '/':
    case '%':
      return 5;
    default:
      return null;
  }
}

class _ExprParser {
  final List<_Token> t;
  int i = 0;

  _ExprParser(this.t);

  Expr? expr(int minPrec) {
    var lhs = unary();
    if (lhs == null) return null;
    while (true) {
      if (i >= t.length) break;
      final tok = t[i];
      if (tok.kind != 'sym') break;
      final p = _precOf(tok.text);
      if (p == null || p < minPrec) break;
      i++;
      final rhs = expr(p + 1);
      if (rhs == null) return null;
      lhs = EBin(tok.text, lhs, rhs);
    }
    return lhs;
  }

  Expr? unary() {
    if (i < t.length &&
        t[i].kind == 'sym' &&
        (t[i].text == '!' || t[i].text == '-')) {
      final op = t[i].text;
      i++;
      final inner = unary();
      if (inner == null) return null;
      return EUnary(op, inner);
    }
    return atom();
  }

  Expr? atom() {
    if (i >= t.length) return null;
    final tok = t[i];
    i++;
    switch (tok.kind) {
      case 'num':
        return ELit(tok.number);
      case 'str':
        return ELit(tok.text);
      case 'ident':
        switch (tok.text) {
          case 'true':
          case '真':
            return ELit(true);
          case 'false':
          case '假':
            return ELit(false);
          case 'null':
          case 'none':
          case 'nil':
            return ELit(null);
          default:
            return EVar(tok.text);
        }
      case 'sym':
        if (tok.text == '(') {
          final e = expr(0);
          if (e == null) return null;
          if (i < t.length && t[i].kind == 'sym' && t[i].text == ')') {
            i++;
            return e;
          }
          return null;
        }
        return null;
      default:
        return null;
    }
  }
}