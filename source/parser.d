import std.stdio;
import tokens;

enum Type {
  SELECT
}

///  expression types
struct ESelect {
  string[] fieldNames;
  string from;
}

union Expr {
  ESelect select;
}

struct ParseResult {
  Type typ;
  Expr expr;
}

class Parser {
  private TokenStream tokens;

  this(TokenStream tokens) {
    this.tokens = tokens;
  }

  ParseResult parse() {
    if (this.tokens.isEOF()) {
      throw new Error("cannot parse EOF");
    }

    auto token = this.tokens.peekOne();
    if (token.typ == TokenType.SELECT) {
      this.tokens.consume();
      ESelect eselect;
      parseSelect(&eselect);
      Expr e = {eselect};
      return ParseResult(Type.SELECT, e);
    }

    assert(0);
  }

  void parseSelect(ESelect* e) {
    while (!this.tokens.isEOF()) {
      if (peekNIsType(0, TokenType.STRING)) {
        auto t = this.tokens.consume();
        e.fieldNames ~= t.stripQuotes();
      }
      else if(peekNIsType(0, TokenType.FROM) && peekNIsType(1, TokenType.STRING)) {
        this.tokens.consume(); // consume FROM
        auto txt = this.tokens.consume().stripQuotes();
        e.from = txt; // TODO: if 'from' is already set?
      }
    }
  }

  bool peekNIsType(int n, TokenType t) {
    return this.tokens.peekN(n).typ == t;
  }
}

Parser parserFromString(string s) {
  auto t = new TokenStream(s);
  return new Parser(t);
}

unittest {
  auto p = parserFromString("select 'p' from 'process'");
  auto e = p.parse();
  assert(e.typ == Type.SELECT);
  assert(e.expr.select.from == "process");
}
