type Token =
  { kind: "num"; value: number } | { kind: "id"; name: string } | { kind: "op"; op: string };

type Scope = Readonly<Record<string, number>>;

const FUNCTIONS: Record<string, (...args: number[]) => number> = {
  min: Math.min,
  max: Math.max,
  abs: Math.abs,
  round: Math.round,
  floor: Math.floor,
  ceil: Math.ceil,
  sqrt: Math.sqrt,
  pow: Math.pow,
  log: Math.log10,
  ln: Math.log,
  exp: Math.exp,
  sin: Math.sin,
  cos: Math.cos,
  tan: Math.tan,
};

const CONSTANTS: Record<string, number> = { pi: Math.PI, e: Math.E };

function tokenize(source: string): Token[] | null {
  const tokens: Token[] = [];
  const pattern = /\s*(?:(\d+\.?\d*|\.\d+)|([a-z_][a-z0-9_]*)|([-+*/^%(),]))/iy;
  let rest = source.trimEnd();
  while (rest.length > 0) {
    const match = pattern.exec(rest);
    if (!match) return null;
    if (match[1] !== undefined) tokens.push({ kind: "num", value: Number(match[1]) });
    else if (match[2] !== undefined) tokens.push({ kind: "id", name: match[2].toLowerCase() });
    else if (match[3] !== undefined) tokens.push({ kind: "op", op: match[3] });
    rest = rest.slice(match[0].length);
    pattern.lastIndex = 0;
  }
  return tokens;
}

class Parser {
  private position = 0;

  constructor(
    private readonly tokens: Token[],
    private readonly scope: Scope,
  ) {}

  run(): number | null {
    const value = this.additive();
    return this.position === this.tokens.length && Number.isFinite(value) ? value : null;
  }

  private peekOp(...ops: string[]): string | null {
    const token = this.tokens[this.position];
    return token?.kind === "op" && ops.includes(token.op) ? token.op : null;
  }

  private additive(): number {
    let left = this.multiplicative();
    for (let op = this.peekOp("+", "-"); op; op = this.peekOp("+", "-")) {
      this.position++;
      const right = this.multiplicative();
      left = op === "+" ? left + right : left - right;
    }
    return left;
  }

  private multiplicative(): number {
    let left = this.unary();
    for (let op = this.peekOp("*", "/", "%"); op; op = this.peekOp("*", "/", "%")) {
      this.position++;
      const right = this.unary();
      left = op === "*" ? left * right : op === "/" ? left / right : left % right;
    }
    return left;
  }

  private unary(): number {
    if (this.peekOp("-")) {
      this.position++;
      return -this.unary();
    }
    if (this.peekOp("+")) {
      this.position++;
      return this.unary();
    }
    return this.power();
  }

  private power(): number {
    const base = this.primary();
    if (this.peekOp("^")) {
      this.position++;
      return Math.pow(base, this.unary());
    }
    return base;
  }

  private primary(): number {
    const token = this.tokens[this.position++];
    if (!token) return NaN;
    if (token.kind === "num") return token.value;
    if (token.kind === "op") {
      if (token.op !== "(") return NaN;
      const inner = this.additive();
      if (!this.peekOp(")")) return NaN;
      this.position++;
      return inner;
    }
    if (this.peekOp("(")) {
      const fn = FUNCTIONS[token.name];
      if (!fn) return NaN;
      this.position++;
      const args: number[] = [];
      if (!this.peekOp(")")) {
        args.push(this.additive());
        while (this.peekOp(",")) {
          this.position++;
          args.push(this.additive());
        }
      }
      if (!this.peekOp(")")) return NaN;
      this.position++;
      return fn(...args);
    }
    return this.scope[token.name] ?? CONSTANTS[token.name] ?? NaN;
  }
}

export function evaluate(source: string, scope: Scope): number | null {
  const tokens = tokenize(source);
  return tokens && tokens.length > 0 ? new Parser(tokens, scope).run() : null;
}
