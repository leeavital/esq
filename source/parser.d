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
  TokenAndError[] errors;
}

struct TokenAndError {
  Token token;
  string error;
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

    ParseResult parseResult;

    auto token = this.tokens.peekOne();
    if (token.typ == TokenType.SELECT) {
      this.tokens.consume();
      ESelect eselect;
      parseSelect(&parseResult, &eselect);
      Expr e = {eselect};
      parseResult.typ = Type.SELECT;
      parseResult.expr = e;
      return parseResult;
    }

    assert(0);
  }

  void parseSelect(ParseResult *pr, ESelect* e) {
    while (!this.tokens.isEOF()) {
      if (peekNIsType(0, TokenType.STRING)) {
        auto t = this.tokens.consume();
        e.fieldNames ~= t.stripQuotes();
      }
      else if (peekNIsType(0, TokenType.FROM)) {
          if (peekNIsType(1, TokenType.STRING)) {
            this.tokens.consume(); // consume from
            auto idx = this.tokens.consume().stripQuotes(); // consume index name
            e.from = idx;
          } else {
            pr.errors ~= TokenAndError(this.tokens.consume(), "Expected an index name after FROM");
          }
      } else {
        auto badToken = this.tokens.consume();
        pr.errors ~= TokenAndError(badToken, "expected from, where, or field names in select statement");
      }
    }
  }

  // TODO: handle the case where we can't peek to N because of EOF
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

unittest {
  auto p = parserFromString("select select");
  auto e = p.parse();
  assert(e.errors.length == 1);
  assert(e.errors[0] == TokenAndError(Token(TokenType.SELECT, 7, "select"), "expected from, where, or field names in select statement"));
}
