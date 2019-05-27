import std.stdio;

enum TokenType
{
    ALTER,
    ASC,
    BY,
    COMMA,
    COUNT,
    DESC,
    FROM,
    HOST,
    INDEX,
    LIMIT,
    LPAREN,
    NUMERIC,
    ON,
    DISTINCT,
    OPAND,
    OPEQ,
    OPNEQ,
    OPOR,
    ORDER,
    RPAREN,
    SELECT,
    STAR,
    STRING,
    WHERE,
}

struct Token
{
    TokenType typ;
    ulong startPos;
    string text;

    auto endPos()
    {
        return startPos + text.length;
    }

    // the following are specific to certain token types
    @nogc string stripQuotes()
    {
        assert(this.typ == TokenType.STRING);
        if (this.text[0] == '"' || this.text[0] == '\'')
        {
            return this.text[1 .. this.text.length - 1];
        }
        return this.text;
    }

    @nogc bool numericIsNegative()
    in(this.typ == TokenType.NUMERIC, "cannot call numericIsNegative on non-NUMERIC")
    {
        return this.text[0] == '-';
    }

    @nogc bool numericIsDecimal()
    {
        foreach (const c; this.text)
        {
            if (c == '.')
            {
                return true;
            }
        }
        return false;
    }
}

// AutoFixes are automatic corrections to the character stream
// that the lexer can make to get past the lexing phase.
struct AutoFix
{
    string message;
    ulong pos;

    @nogc bool empty()
    {
        return this.message == "" && this.pos == 0;
    }
}

immutable TokenType[string] literalTokens;
static this()
{
    literalTokens["("] = TokenType.LPAREN;
    literalTokens[")"] = TokenType.RPAREN;
    literalTokens["!="] = TokenType.OPNEQ;
    literalTokens["*"] = TokenType.STAR;
    literalTokens[","] = TokenType.COMMA;
    literalTokens["="] = TokenType.OPEQ;
    literalTokens["alter"] = TokenType.ALTER;
    literalTokens["and"] = TokenType.OPAND;
    literalTokens["asc"] = TokenType.ASC;
    literalTokens["by"] = TokenType.BY;
    literalTokens["count"] = TokenType.COUNT;
    literalTokens["desc"] = TokenType.DESC;
    literalTokens["distinct"] = TokenType.DISTINCT;
    literalTokens["from"] = TokenType.FROM;
    literalTokens["index"] = TokenType.INDEX;
    literalTokens["limit"] = TokenType.LIMIT;
    literalTokens["on"] = TokenType.ON;
    literalTokens["or"] = TokenType.OPOR;
    literalTokens["order"] = TokenType.ORDER;
    literalTokens["select"] = TokenType.SELECT;
    literalTokens["where"] = TokenType.WHERE;
    literalTokens["host"] = TokenType.HOST;
}

class TokenStream
{

    // the current position of the next token that will be consumed
    private ulong currentPos;

    // the current position where we should continue peeking
    private ulong peekPos;

    // the current set of tokens that have already been parsed.
    // TODO: this should be a more efficient DS
    private Token[] peek;

    // all AutoFixes for this lex.
    // TODO: use a more efficient datastructure that caps the number
    // of fixes
    private AutoFix[] fixes;

    private string source;

    // todo: instead of string, should be a "source" class which has information
    // about file location, stdin, etc.
    this(string source)
    {
        this.source = source;
        this.currentPos = 0;
        this.peek = [];
    }

    @nogc bool isEOF()
    {
        return this.peekPos >= source.length && this.peek.length == 0;
    }

    public Token consume()
    {
        peekOne();
        auto next = this.peek[0];
        this.peek = this.peek[1 .. $];
        this.currentPos = next.endPos;
        return next;
    }

    public Token peekOne()
    {
        if (this.peek.length > 0)
        {
            return this.peek[0];
        }
        else
        {
            peekOneMore();
            return this.peek[0];
        }
    }

    public bool canPeekN(int n)
    {
        for (int i = 0; i < n + 1; i++)
        {
            peekOneMore();
        }
        return this.peek.length > n;
    }

    // this will panic if canPeekN(n) is not true
    // at the time of calling
    public Token peekN(int n)
    {
        canPeekN(n);
        return this.peek[n];
    }

    public const(AutoFix[]) getAutoFixes()
    {
        const AutoFix[] f = this.fixes;
        return f;
    }

    // if possible, peek the next token
    private void peekOneMore()
    {
        if (this.isEOF() || this.peekPos >= this.source.length)
        {
            return;
        }

        if (this.source[peekPos] == ' ')
        {
            // special case -- if we detect whitespace, ignore
            this.peekPos++;
            this.peekOneMore();
            return;
        }

        Token nextToken = Token();
        AutoFix fix;

        if (peekLiteralToken(&nextToken))
        { /* do nothing  */ }
        else if (peekQuotedString(&nextToken, &fix))
        { /* do nothing */ }
        else if (this.peekNumeric(&nextToken))
        { /* do nothing */ }
        else
        {
            this.peekUnquotedString(&nextToken); // bail out and treat the bare strings as symbols
        }

        if (nextToken == Token())
        {
            import std.stdio;

            writefln("failed on input %s", this.source[this.peekPos .. $]);
            // TODO: think about how to skip lexing for bad stuff
            assert(0);
        }

        this.peekPos = nextToken.endPos();
        this.peek = this.peek ~ nextToken;

        if (!fix.empty())
        {
            writefln("added to fixes");
            this.fixes ~= fix;
        }
    }

    @nogc bool peekLiteralToken(Token* tok)
    {
        import std.ascii;

        enum CharacterClass
        {
            num,
            alph,
            none,
            white,
            punct
        }

        CharacterClass getCharacterClass(ulong i)
        {
            if (i >= this.source.length)
                return CharacterClass.none;
            else if (isDigit(this.source[i]))
                return CharacterClass.num;
            else if (isWhite(this.source[i]))
                return CharacterClass.white;
            else if (isPunctuation(this.source[i]))
                return CharacterClass.punct;
            return CharacterClass.alph;
        }

        // we need to take the longest matching literal (e.g. take ORDER over OR)
        ulong longestMatch = 0;
        foreach (const str, typ; literalTokens)
        {
            bool doesCharMatch = this.peekChars(str);
            ulong wouldBeNextCharI = this.peekPos + str.length;
            bool doesStrContinue = getCharacterClass(wouldBeNextCharI) == getCharacterClass(
                    wouldBeNextCharI - 1);
            if (doesCharMatch && str.length > longestMatch && (!doesStrContinue
                    || getCharacterClass(wouldBeNextCharI - 1) == CharacterClass.punct))
            {
                longestMatch = str.length;
                tok.typ = typ;
                tok.startPos = this.peekPos;
                tok.text = this.source[this.peekPos .. this.peekPos + longestMatch];
            }
        }
        return longestMatch > 0;
    }

    @nogc private bool peekQuotedString(Token* tok, AutoFix* fix)
    {
        if (!(this.peekChars("\"") || this.peekChars("'")))
        {
            return false;
        }

        auto delim = this.source[this.peekPos];
        assert(delim == '\'' || delim == '"');
        ulong n = this.peekPos + 1;
        while (this.source[n] != delim)
        {
            n++; // TODO: handle escaped strings
            if (n == this.source.length)
            {
                // `source` ends in an unterminated string, we
                // can recover by inserting one automatically
                n--;
                fix.pos = n;
                fix.message = "unterminated string; inserting closing quote";
                break;
            }
        }
        n++; // account for the last delim

        if (n == this.source.length)
        {
            tok.text = this.source[this.peekPos .. $];
        }
        else
        {
            tok.text = this.source[this.peekPos .. n];
        }

        tok.startPos = this.peekPos;
        tok.typ = TokenType.STRING;
        return true;
    }

    @nogc bool peekUnquotedString(Token* tok)
    {
        import std.ascii;

        if (this.source[this.peekPos] == ' ')
        {
            return false;
        }

        bool isValidSymChar(ulong n)
        {
            auto c = this.source[n];
            return isAlphaNum(c) || c == '_' || c == '.';
        }

        auto n = this.peekPos;
        while (n != this.source.length && isValidSymChar(n))
        {
            n++;
        }

        tok.text = this.source[this.peekPos .. n];
        tok.startPos = this.peekPos;
        tok.typ = TokenType.STRING;
        return true;
    }

    @nogc private bool peekNumeric(Token* t)
    {
        import std.ascii;

        bool negative;

        ulong n; // where we will start scanning
        bool isNegative = canPeekNChars(2) && this.source[this.peekPos] == '-'
            && isDigit(this.source[this.peekPos + 1]);
        bool isPositive = canPeekNChars(1) && isDigit(this.source[this.peekPos]);

        if (isNegative)
        {
            n = this.peekPos + 2;
        }
        else if (isPositive)
        {
            n = this.peekPos + 1;
        }
        else
        {
            return false;
        }

        // find the next space
        while (true)
        {
            if (n >= this.source.length)
            {
                break;
            }

            char c = this.source[n];
            if (c == '.' || isDigit(c))
            {
                n++;
            }
            else
            {
                break;
            }
        }

        // TODO: make sure 1 or zero decimal points
        t.typ = TokenType.NUMERIC;
        t.startPos = this.peekPos;
        t.text = this.source[this.peekPos .. n];

        return true;
    }

    @nogc private bool peekChars(string txt)
    {
        import std.uni : icmp;

        if (this.source.length - this.peekPos < txt.length)
        {
            return false;
        }
        return icmp(this.source[this.peekPos .. this.peekPos + txt.length], txt) == 0;
    }

    @nogc private bool canPeekNChars(int n)
    {
        return n <= (this.source.length - this.peekPos);
    }
}

// EOF unittest
unittest
{
    auto t = new TokenStream("");
    assert(t.isEOF());
}

/// peekN can be used to peek N characters ahead
unittest
{
    auto t = new TokenStream("select from from");
    assert(t.peekN(0).typ == TokenType.SELECT);
    assert(t.peekN(1).typ == TokenType.FROM);
}

unittest
{
    import std.stdio;
    import std.format;

    string[] messages;
    void check(string full, string[] expected)
    {
        auto t = new TokenStream(full);
        string[] actual = [];
        Token[] tokens;
        auto limit = 0;
        while (!t.isEOF() && ++limit < 100)
        {
            auto token = t.consume();
            actual = actual ~ [token.text];
            tokens ~= token;
        }

        if (actual != expected)
        {
            messages ~= format("when tokenizing <%s> got %s expected %s", full, actual, expected);
        }

        auto arePositionsInLine = true;
        for (int i = 1; i < tokens.length; i++)
        {
            auto prev = tokens[i - 1];
            auto curr = tokens[i];
            auto inline = prev.startPos < curr.startPos && prev.endPos <= curr.startPos;
            if (!inline)
            {
                messages ~= format("tokens positions were out of order %s  --> %s", prev, curr);
            }
        }
    }

    void finish()
    {
        foreach (const m; messages)
        {
            writeln(m);
        }
        if (messages.length > 0)
        {
            assert(0);
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
    check(`SELECT 123`, ["SELECT", "123"]);
    check(`SELECT -123`, ["SELECT", "-123"]);
    check(`SELECT 1.2`, ["SELECT", "1.2"]);
    check(`SELECT -1.2`, ["SELECT", "-1.2"]);
    check(`SELECT -14.3 4002 FROM 40`, ["SELECT", "-14.3", "4002", "FROM", "40"]);
    check(`SELECT LIMIT FROM`, ["SELECT", "LIMIT", "FROM"]);
    check(`SELECT LIMIT WHERE 10`, ["SELECT", "LIMIT", "WHERE", "10"]);
    check(`SELECT = WHERE =`, ["SELECT", "=", "WHERE", "="]);
    check(`WHERE "foo" =1`, ["WHERE", `"foo"`, `=`, `1`]);
    check(`WHERE "foo"=1`, ["WHERE", `"foo"`, `=`, `1`]);
    check(`WHERE "foo" = 1`, ["WHERE", `"foo"`, `=`, `1`]);
    check(`ALTER WHERE BY ORDER`, ["ALTER", "WHERE", "BY", "ORDER"]);
    check(`ASC, DESC ,`, ["ASC", ",", "DESC", ","]);
    check(`WHERE "foo" OR 1 AND`, [`WHERE`, `"foo"`, `OR`, `1`, `AND`]);
    check(`SELECT WHERE foo = 2`, [`SELECT`, `WHERE`, `foo`, `=`, `2`]);
    check(`foo=`, [`foo`, `=`]);
    check(`foo`, [`foo`]);
    check(`orby`, [`orby`]);
    check(`WHERE x != foo`, [`WHERE`, `x`, `!=`, `foo`]);
    check(`DISTINCT`, ["DISTINCT"]);
    check(`"foo`, [`"foo`]);
    finish();
}
