import std.stdio;


enum TokenType {
 SELECT, FROM, STAR, LPAREN, RPAREN, STRING
}

struct Token {
  TokenType typ;
  ulong startPos;
  string text;

  auto endPos() {
    return startPos + text.length;
  }

  string stripQuotes() {
    return this.text[1..this.text.length - 1];
  }
}

class TokenStream {

  // the current position of the next token that will be consumed
  private ulong currentPos;

  // the current position where we should continue peeking
  private ulong peekPos;

  // the current set of tokens that have already been parsed.
  // TODO: this should be a more efficient DS
  private Token[] peek;

  private string source;

  // todo: instead of string, should be a "source" class which has information
  // about file location, stdin, etc.
  this(string source) {
    this.source = source;
    this.currentPos = 0;
    this.peek = [];
  }

  @nogc
  bool isEOF() {
    return this.peekPos >= source.length && this.peek.length == 0;
  }

  public Token consume() {
    peekOne();
    auto next = this.peek[0];
    this.peek = this.peek[1..$];
    this.currentPos = next.endPos + 1;
    return next;
  }


  public Token peekOne() {
    if (this.peek.length > 0) {
      return this.peek[0];
    } else {
      peekOneMore();
      return this.peek[0];
    }
  }

  public Token peekN(int n) {
    for (int i = 0; i < n+1 ; i++) {
      peekOneMore();
    }
    return this.peek[n];
  }

  // if possible, peek the next token
  private void peekOneMore() {
    if (this.isEOF() || this.peekPos >= this.source.length) {
      return;
    }

    if (this.source[peekPos] == ' ') {
      // special case -- if we detect whitespace, ignore
      this.peekPos++;
      this.peekOneMore();
      return;
    }

    Token nextToken = Token();
    if(this.peekChars("select")) {
      auto text = this.source[this.peekPos..this.peekPos + "select".length];
      nextToken = Token(TokenType.SELECT, this.peekPos, text);
    } else if(this.peekChars("from")) {
      auto text = this.source[this.peekPos..this.peekPos + "from".length];
      nextToken = Token(TokenType.FROM, this.peekPos, text);
    } else if (this.peekChars("*")) {
      nextToken = Token(TokenType.STAR, this.peekPos, "*");
    } else if (this.peekChars("(")) {
      nextToken = Token(TokenType.LPAREN, this.peekPos, "(");
    }else if (this.peekChars(")")) {
      nextToken = Token(TokenType.RPAREN, this.peekPos, ")");
    } else if (this.peekChars("\"") || this.peekChars("'")) {
      auto str = peekQuotedString();
      nextToken = Token(TokenType.STRING, this.peekPos, str);
    }

    if (nextToken == Token()) {
      import std.stdio;
      writefln("failed on input %s", this.source[this.peekPos..$]);
      assert(0);
    }

    this.peekPos = nextToken.endPos() + 1;
    this.peek = this.peek ~ nextToken;
  }

  private string peekQuotedString() {
    auto delim = this.source[this.peekPos];
    assert(delim == '\'' || delim == '"');
    ulong n = this.peekPos + 1;
    while (this.source[n] != delim) {
      n++; // TODO: handle escaped strings
    }
    n++; // account for the last delim

    if (n == this.source.length) {
      return this.source[this.peekPos..$];
    } else {
      return this.source[this.peekPos..n];
    }
  }

  @nogc
  private bool peekChars(string txt) {
    import std.uni : icmp;
    if (this.source.length - this.peekPos < txt.length) {
      return false;
    }
    return icmp(this.source[this.peekPos..this.peekPos+txt.length], txt) == 0;
  }
}

// EOF unittest
unittest {
  auto t = new TokenStream("");
  assert(t.isEOF());
}

/// peekN can be used to peek N characters ahead
unittest {
  auto t = new TokenStream("select from from");
  assert(t.peekN(0).typ == TokenType.SELECT);
  assert(t.peekN(1).typ == TokenType.FROM);
}

unittest {
  import std.stdio;
  void check(string full, string[] expected) {
    auto t = new TokenStream(full);
    string[] actual = [];
    ulong[] positions = [];
    while (!t.isEOF()) {
      auto token = t.consume();
      actual = actual ~ [token.text];
      positions ~= [token.startPos, token.endPos()];
    }

    if (actual != expected) {
      writefln("got %s expected %s", actual, expected);
      assert(0);
    }

    for (int i = 1; i < positions.length; i++) {
      assert(positions[i-1] < positions[i]);
    }
  }

  check("select * select", ["select", "*", "select"]);
  check("from", ["from"]);
  check("select from select", ["select", "from", "select"]);
  check(`select "foo"`, ["select", `"foo"`]);
  check("'x' 'y'", ["'x'", "'y'"]);
  check("''", ["''"]);
  check(`select "xyz" from`, ["select", `"xyz"`, "from"]);
  check(`SELECT "xyz" FROM "foo"`, ["SELECT", `"xyz"`, "FROM", `"foo"`]);
}

