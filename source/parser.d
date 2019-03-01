import std.stdio;
import tokens;

enum Type
{
    SELECT
}

///  expression types

// Top level expression type
union Expr
{
    ESelect select;
}

struct ESelect
{
    string[] fieldNames;
    string from;
    uint lowerLimit;
    EWhere where;

    // orderFields and orderDirections are the same length. Elements of order directions
    // will be either ASC or DESC
    string[] orderFields;
    Order[] orderDirections;
}

enum BoolOp
{
    Equal
}

enum Order
{
    Asc,
    Desc
}

struct EWhere
{
    BoolOp operator;
    string field;
    Token test; // either a numberic or a string
}

struct ParseResult
{
    Type typ;
    Expr expr;
    TokenAndError[] errors;
}

struct TokenAndError
{
    Token token;
    string error;
}

class Parser
{
    private TokenStream tokens;

    this(TokenStream tokens)
    {
        this.tokens = tokens;
    }

    ParseResult parse()
    {
        if (this.tokens.isEOF())
        {
            throw new Error("cannot parse EOF");
        }

        ParseResult parseResult;

        auto token = this.tokens.peekOne();
        if (token.typ == TokenType.SELECT)
        {
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

    void parseSelect(ParseResult* pr, ESelect* e)
    {
        auto didSeeWhere = false;

        while (!this.tokens.isEOF())
        {
            if (peekNIsType(0, TokenType.STRING))
            {
                auto t = this.tokens.consume();
                e.fieldNames ~= t.stripQuotes();
            }
            else if (peekNIsType(0, TokenType.FROM))
            {
                if (peekNIsType(1, TokenType.STRING))
                {
                    this.tokens.consume(); // consume from
                    auto idx = this.tokens.consume().stripQuotes(); // consume index name
                    e.from = idx;
                }
                else
                {
                    pr.errors ~= TokenAndError(this.tokens.consume(),
                            "Expected an index name after FROM");
                }
            }
            else if (peekNIsType(0, TokenType.WHERE))
            {
                auto t = this.tokens.consume();
                if (didSeeWhere)
                {
                    // error, but re-parse the WHERE statement into a temporary var
                    pr.errors ~= TokenAndError(t, "cannot have more than one WHERE clause");
                    auto w = EWhere();
                    parseWhere(pr, &w); // is there better syntax for this?
                }
                else
                {
                    parseWhere(pr, &e.where);
                    didSeeWhere = true;
                }
            }
            else if (peekNIsType(0, TokenType.LIMIT))
            {
                this.tokens.consume(); // consume limit
                auto t = this.tokens.consume();
                if (t.typ != TokenType.NUMERIC)
                {
                    pr.errors ~= TokenAndError(t, "expected numeric after LIMIT");
                }
                else if (t.numericIsNegative())
                {
                    pr.errors ~= TokenAndError(t, "cannot have a negative number as LIMIT");
                }
                else if (t.numericIsDecimal())
                {
                    pr.errors ~= TokenAndError(t, "cannot use a non-int number as LIMIT");
                }
                else
                {
                    import std.conv;

                    e.lowerLimit = t.text.to!uint;
                }
            }
            else if (peekNIsType(0, TokenType.ORDER) && peekNIsType(1, TokenType.BY))
            {
                this.tokens.consume();
                auto by = this.tokens.consume();

                // TOOD: extract into its own function
                if (this.tokens.isEOF())
                {
                    pr.errors ~= TokenAndError(by, "expected symbol after ORDER BY but got EOF");
                }
                else
                {
                    string[] fields;
                    Order[] directions;
                    parseOrderBy(pr, fields, directions);
                    e.orderFields = fields;
                    e.orderDirections = directions;

                }
            }
            else
            {
                auto badToken = this.tokens.consume();
                pr.errors ~= TokenAndError(badToken,
                        "expected from, where, or field names in select statement");
            }
        }
    }

    void parseWhere(ParseResult* pr, EWhere* where)
    {
        // TODO: only parsing one level, support arbitrary boolean expressions
        if (peekNIsType(0, TokenType.STRING))
        {
            auto sym = this.tokens.consume();
            if (peekNIsType(0, TokenType.OPEQ))
            {
                auto op = this.tokens.consume();
                if (peekNIsType(0, TokenType.NUMERIC) || peekNIsType(0, TokenType.STRING))
                {
                    auto lhs = this.tokens.consume();
                    where.operator = parseOp(op);
                    where.field = sym.stripQuotes();
                    where.test = lhs;
                }
                else if (this.tokens.isEOF())
                {
                    pr.errors ~= TokenAndError(op, "unterminated boolean expression");
                }
                else
                {
                    pr.errors ~= TokenAndError(this.tokens.consume(),
                            "expected string or number after operator");
                }
            }
            else if (this.tokens.isEOF())
            {
                pr.errors ~= TokenAndError(sym, "unterminated boolean statement");
            }
            else
            {
                pr.errors ~= TokenAndError(this.tokens.consume(),
                        "expected boolean operator after symbol in WHERE");
            }
        }
    }

    void parseOrderBy(ParseResult* pr, out string[] fields, out Order[] directions)
    {
        while (true)
        {
            if (!this.peekNIsType(0, TokenType.STRING))
            {
                pr.errors ~= TokenAndError(this.tokens.consume(),
                        "expected symbol name after ORDER BY");
                return;
            }

            auto field = this.tokens.consume();
            auto order = Order.Asc;
            if (peekNIsType(0, TokenType.ASC))
            {
                this.tokens.consume();
            }
            else if (peekNIsType(0, TokenType.DESC))
            {
                this.tokens.consume();
                order = Order.Desc;
            }
            fields ~= field.stripQuotes();
            directions ~= order;

            if (peekNIsType(0, TokenType.COMMA))
            {
                // if we see a comma, we have fields to include in the ORDER BY clause
                this.tokens.consume();
            }
            else
            {
                return;
            }
        }
    }

    // precondition: token must be one of the bool op tokens
    @nogc BoolOp parseOp(Token tok)
    {
        switch (tok.typ)
        {
        case TokenType.OPEQ:
            return BoolOp.Equal;
        default:
            assert(0);
        }
    }

    bool peekNIsType(int n, TokenType t)
    {
        return this.tokens.canPeekN(n) && this.tokens.peekN(n).typ == t;
    }
}

Parser parserFromString(string s)
{
    auto t = new TokenStream(s);
    return new Parser(t);
}

unittest
{
    auto p = parserFromString("select 'p' from 'process'");
    auto e = p.parse();
    assert(e.typ == Type.SELECT);
    assert(e.expr.select.from == "process");
}

unittest
{
    auto p = parserFromString("select 'p' from 'process' LIMIT 10");
    auto e = p.parse();
    assert(e.typ == Type.SELECT);
    assert(e.expr.select.from == "process");
    assert(e.expr.select.lowerLimit == 10);
}

unittest
{
    auto p = parserFromString("select select");
    auto e = p.parse();
    assert(e.errors.length == 1);
    assert(e.errors[0] == TokenAndError(Token(TokenType.SELECT, 7, "select"),
            "expected from, where, or field names in select statement"));
}

unittest
{
    auto p = parserFromString("select from 'foo' where 'p' = 3");
    auto e = p.parse();
    assert(e.errors.length == 0);
    assert(e.expr.select.where.field == "p");
    assert(e.expr.select.where.operator == BoolOp.Equal);
    assert(e.expr.select.where.test.text == "3");
    assert(e.expr.select.where.test.typ == TokenType.NUMERIC);
}

unittest
{
    auto p = parserFromString("select from 'foo' order by 'bar' DESC");
    auto e = p.parse();
    assert(e.errors.length == 0);
    assert(e.expr.select.orderFields == ["bar"]);
    assert(e.expr.select.orderDirections == [Order.Desc]);
}
