import 'dart:math' as math;

import '../../../../core/constants/widget_playful.dart';

/// Safe arithmetic expression evaluator (recursive descent, no eval).
///
/// Grammar: expr = term (('+'|'-') term)*; term = unary (('*'|'/'|'%') unary)*;
/// unary = '-' unary | power; power = atom ('^' unary)?; atom = number |
/// ident | ident '(' args ')' | '(' expr ')'.
class CalcExpr {
  CalcExpr._(this._root);

  final _Node _root;

  /// Parses [src]; throws [FormatException] when invalid.
  factory CalcExpr.parse(String src) {
    if (src.length > PlayfulLimits.exprMaxLength) {
      throw const FormatException('too long');
    }
    final p = _Parser(src);
    final n = p.parse();
    return CalcExpr._(n);
  }

  /// Evaluates with [vars]; null for NaN, infinity or unknown names.
  double? eval(Map<String, double> vars) {
    try {
      final v = _root.eval(vars);
      if (v.isNaN || v.isInfinite) return null;
      return v;
    } on FormatException {
      return null;
    }
  }

  /// Names referenced that are not functions or constants.
  Set<String> get identifiers => _root.idents();
}

const _constants = <String, double>{'pi': math.pi, 'e': math.e};

abstract class _Node {
  double eval(Map<String, double> v);
  Set<String> idents() => {};
}

class _Num extends _Node {
  _Num(this.v);
  final double v;
  @override
  double eval(Map<String, double> vars) => v;
}

class _Id extends _Node {
  _Id(this.name);
  final String name;
  @override
  double eval(Map<String, double> vars) {
    final v = vars[name] ?? _constants[name];
    if (v == null) throw const FormatException('unknown');
    return v;
  }

  @override
  Set<String> idents() => _constants.containsKey(name) ? {} : {name};
}

class _Neg extends _Node {
  _Neg(this.a);
  final _Node a;
  @override
  double eval(Map<String, double> v) => -a.eval(v);
  @override
  Set<String> idents() => a.idents();
}

class _Bin extends _Node {
  _Bin(this.op, this.a, this.b);
  final String op;
  final _Node a, b;
  @override
  double eval(Map<String, double> v) {
    final x = a.eval(v), y = b.eval(v);
    switch (op) {
      case '+':
        return x + y;
      case '-':
        return x - y;
      case '*':
        return x * y;
      case '/':
        return y == 0 ? double.nan : x / y;
      case '%':
        return y == 0 ? double.nan : x % y;
      default:
        return math.pow(x, y).toDouble();
    }
  }

  @override
  Set<String> idents() => {...a.idents(), ...b.idents()};
}

class _Call extends _Node {
  _Call(this.name, this.args);
  final String name;
  final List<_Node> args;

  @override
  double eval(Map<String, double> v) {
    final a = [for (final n in args) n.eval(v)];
    double one() {
      if (a.length != 1) throw const FormatException('arity');
      return a[0];
    }

    switch (name) {
      case 'min':
        if (a.isEmpty) throw const FormatException('arity');
        return a.reduce(math.min);
      case 'max':
        if (a.isEmpty) throw const FormatException('arity');
        return a.reduce(math.max);
      case 'abs':
        return one().abs();
      case 'round':
        return one().roundToDouble();
      case 'floor':
        return one().floorToDouble();
      case 'ceil':
        return one().ceilToDouble();
      case 'sqrt':
        return math.sqrt(one());
      case 'log':
        return math.log(one()) / math.ln10;
      case 'ln':
        return math.log(one());
      case 'exp':
        return math.exp(one());
      case 'sin':
        return math.sin(one());
      case 'cos':
        return math.cos(one());
      case 'tan':
        return math.tan(one());
      case 'pow':
        if (a.length != 2) throw const FormatException('arity');
        return math.pow(a[0], a[1]).toDouble();
      default:
        throw const FormatException('unknown function');
    }
  }

  @override
  Set<String> idents() => {for (final n in args) ...n.idents()};
}

const _functions = {
  'min', 'max', 'abs', 'round', 'floor', 'ceil', 'sqrt', 'pow', //
  'log', 'ln', 'exp', 'sin', 'cos', 'tan',
};

class _Parser {
  _Parser(this.s);
  final String s;
  int i = 0;
  int depth = 0;

  _Node parse() {
    final n = _expr();
    _ws();
    if (i != s.length) throw const FormatException('trailing');
    return n;
  }

  void _ws() {
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
  }

  bool _eat(String c) {
    _ws();
    if (i < s.length && s[i] == c) {
      i++;
      return true;
    }
    return false;
  }

  _Node _expr() {
    if (++depth > PlayfulLimits.exprMaxDepth) {
      throw const FormatException('deep');
    }
    var n = _term();
    while (true) {
      if (_eat('+')) {
        n = _Bin('+', n, _term());
      } else if (_eat('-')) {
        n = _Bin('-', n, _term());
      } else {
        break;
      }
    }
    depth--;
    return n;
  }

  _Node _term() {
    var n = _unary();
    while (true) {
      if (_eat('*')) {
        n = _Bin('*', n, _unary());
      } else if (_eat('/')) {
        n = _Bin('/', n, _unary());
      } else if (_eat('%')) {
        n = _Bin('%', n, _unary());
      } else {
        break;
      }
    }
    return n;
  }

  _Node _unary() {
    if (_eat('-')) return _Neg(_unary());
    if (_eat('+')) return _unary();
    return _power();
  }

  _Node _power() {
    final base = _atom();
    if (_eat('^')) return _Bin('^', base, _unary());
    return base;
  }

  _Node _atom() {
    _ws();
    if (i >= s.length) throw const FormatException('eof');
    final c = s[i];
    if (c == '(') {
      i++;
      final n = _expr();
      if (!_eat(')')) throw const FormatException('paren');
      return n;
    }
    if (_isDigit(c) || c == '.') {
      final st = i;
      while (i < s.length && (_isDigit(s[i]) || s[i] == '.')) {
        i++;
      }
      final v = double.tryParse(s.substring(st, i));
      if (v == null) throw const FormatException('number');
      return _Num(v);
    }
    if (_isAlpha(c)) {
      final st = i;
      while (i < s.length && (_isAlpha(s[i]) || _isDigit(s[i]))) {
        i++;
      }
      final name = s.substring(st, i).toLowerCase();
      if (_eat('(')) {
        if (!_functions.contains(name)) {
          throw const FormatException('function');
        }
        final args = <_Node>[];
        if (!_eat(')')) {
          do {
            args.add(_expr());
          } while (_eat(','));
          if (!_eat(')')) throw const FormatException('paren');
        }
        return _Call(name, args);
      }
      return _Id(name);
    }
    throw FormatException('unexpected $c');
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  static bool _isAlpha(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95;
  }
}
