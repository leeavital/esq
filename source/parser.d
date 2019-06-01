import std.stdio;
import lexer;
import std.variant;

enum Type
{
    SELECT,
    ALTER_INDEX
}

///  expression types

// Top level expression type
union Expr
{
    ESelect select;
    EAlter alter;
}

struct ESelect
{
    string[] fieldNames;
    string from;
    uint lowerLimit;
    EWhere where;
    Aggregation aggregation;

    // orderFields and orderDirections are the same length. Elements of order directions
    // will be either ASC or DESC
    string[] orderFields;
    Order[] orderDirections;
}

struct EAlter
{
    string index;
    string[] keys;
    Token[] values;
}

enum ComparisonOp
{
    Equal,
    NotEqual
}

enum Aggregation
{
    None = 0,
    Distinct = 1,
    CountDistinct = 2
}

enum Order
{
    Asc,
    Desc
}

enum BoolOp
{
    and,
    or,
    not
}

alias EWhere = Algebraic!(EWhereSimple*, EWhereComplex*);

// a single "x" = y statement
struct EWhereSimple
{
    ComparisonOp operator;
    string field;
    Token test; // either a numberic or a string
}

struct EWhereComplex
{
    BoolOp operator;
    EWhere[] operands;
}

struct ParseResult
{
    Type typ;
    Expr expr;
    TokenAndError[] errors;
    string host;
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

        if (peekNIsType(0, TokenType.SELECT))
        {
            this.tokens.consume();
            ESelect eselect;
            parseSelect(&parseResult, &eselect);
            Expr e = {eselect};
            parseResult.typ = Type.SELECT;
            parseResult.expr = e;
            return parseResult;
        }
        else if (peekNIsType(0, TokenType.ALTER) && peekNIsType(1, TokenType.INDEX))
        {
            this.tokens.consume();
            this.tokens.consume();
            parseAlter(&parseResult, &parseResult.expr.alter);
            parseResult.typ = Type.ALTER_INDEX;
            return parseResult;
        }
        else
        {
            parseResult.errors ~= TokenAndError(this.tokens.consume(),
                    "expected SELECT or ALTER INDEX at start of expression");
            // don't bother parsing more
            return parseResult;
        }
    }

    void parseSelect(ParseResult* pr, ESelect* e)
    {
        auto didSeeWhere = false;

        parseFieldList(pr, e);

        while (!this.tokens.isEOF())
        {
            if (peekNIsType(0, TokenType.FROM))
            {
                if (peekNIsType(1, TokenType.STRING))
                {
                    this.tokens.consume(); // consume from
                    auto idx = this.tokens.consume().stripQuotes(); // consume index name
                    e.from = idx;
                }
                else if (peekNIsType(1, TokenType.STAR))
                {
                    this.tokens.consume(); // consume SELECT
                    this.tokens.consume(); // consume STAR
                    e.from = "*";
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
                    parseWhere(pr); // call the parser anyway, to get errors
                }
                else
                {
                    e.where = parseWhere(pr);
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
            else if (peekNIsType(0, TokenType.ON) && peekNIsType(1,
                    TokenType.HOST) && peekNIsType(2, TokenType.STRING))
            {
                this.tokens.consume(); //ON
                this.tokens.consume(); //HOST
                pr.host = this.tokens.consume().stripQuotes();
            }
            else
            {
                auto badToken = this.tokens.consume();
                pr.errors ~= TokenAndError(badToken,
                        "expected from, where, on, or field names in select statement");
            }
        }
    }

    void parseFieldList(ParseResult* pr, ESelect* e)
    {
        if (peekNIsType(0, TokenType.STAR))
        {
            this.tokens.consume();
            e.fieldNames = [];
            return;
        }

        if (peekNIsType(0, TokenType.COUNT) || peekNIsType(1, TokenType.DISTINCT))
        {
            this.tokens.consume();
            this.tokens.consume();
            e.aggregation = Aggregation.CountDistinct;
        }
        else if (peekNIsType(0, TokenType.DISTINCT))
        {
            this.tokens.consume();
            e.aggregation = Aggregation.Distinct;
        }

        while (!this.tokens.isEOF())
        {
            if (!peekNIsType(0, TokenType.STRING))
            {
                return;
            }

            auto t = this.tokens.consume();
            e.fieldNames ~= t.stripQuotes();

            if (peekNIsType(0, TokenType.COMMA))
            {
                this.tokens.consume();
                continue;
            }

            if (peekNIsType(0, TokenType.STRING))
            {
                pr.errors ~= TokenAndError(t, "missing a comma following field name");
                continue;
            }
        }
    }

    EWhere parseWhere(ParseResult* pr)
    {
        // parse a simple where
        EWhere[] terms = [parseWhere_1(pr)];

        while (this.peekNIsType(0, TokenType.OPOR))
        {
            this.tokens.consume();
            auto next = parseWhere_1(pr);
            terms ~= next;
        }

        if (terms.length == 1)
        {
            return terms[0];
        }
        else
        {
            EWhere e = new EWhereComplex(BoolOp.or, terms);
            return e;
        }
    }

    EWhere parseWhere_1(ParseResult* pr)
    {
        EWhere first = parseWhere_2(pr);
        EWhere[] exprs = [first];
        while (peekNIsType(0, TokenType.OPAND))
        {
            this.tokens.consume();
            EWhere next = parseWhere_2(pr);
            exprs ~= next;
        }

        if (exprs.length == 1)
        {
            return exprs[0];
        }
        else
        {
            EWhere combined;
            combined = new EWhereComplex(BoolOp.and, exprs);
            return combined;
        }
    }

    EWhere parseWhere_2(ParseResult* pr)
    {
        if (peekNIsType(0, TokenType.LPAREN))
        {
            auto lparen = this.tokens.consume();
            EWhere w = parseWhere(pr);
            if (this.tokens.isEOF())
            {
                pr.errors ~= TokenAndError(lparen, "unterminated parenthesis");
                return w;
            }
            else if (peekNIsType(0, TokenType.RPAREN))
            {
                this.tokens.consume();
                return w;
            }
            else
            {
                pr.errors ~= TokenAndError(this.tokens.consume(),
                        "expected right paren to close lparen expression");
                return w;
            }
        }
        else
        {
            return parseWhere_3(pr);
        }
    }

    EWhere parseWhere_3(ParseResult* pr)
    {
        EWhereSimple* where = new EWhereSimple();

        // TODO: only parsing one level, support arbitrary boolean expressions
        if (peekNIsType(0, TokenType.STRING))
        {
            auto sym = this.tokens.consume();
            if (peekNIsType(0, TokenType.OPEQ) || peekNIsType(0, TokenType.OPNEQ))
            {
                auto op = this.tokens.consume();
                if (peekNIsOnOf(0, TokenType.NUMERIC, TokenType.STRING))
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

        EWhere e = where;
        return e;
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

    void parseAlter(ParseResult* pr, EAlter* a)
    {
        if (peekNIsType(0, TokenType.STRING))
        {
            a.index = this.tokens.consume().stripQuotes();
        }
        else
        {
            pr.errors ~= TokenAndError(this.tokens.consume(), "expected index name");
        }

        while (!this.tokens.isEOF())
        {
            if (peekNIsType(0, TokenType.ON) && peekNIsType(1, TokenType.HOST)
                    && peekNIsType(2, TokenType.STRING))
            {
                this.tokens.consume(); //ON
                this.tokens.consume(); //HOST
                pr.host = this.tokens.consume().stripQuotes();
                continue;
            }

            if (!peekNIsType(0, TokenType.STRING))
            {
                pr.errors ~= TokenAndError(this.tokens.consume(),
                        "expected field name in ALTER statement");
                continue;
            }

            if (!peekNIsType(1, TokenType.OPEQ))
            {
                auto field = this.tokens.consume(); // consume STRING
                if (this.tokens.isEOF())
                {
                    pr.errors ~= TokenAndError(field, "expected '=' after field name");
                }
                else
                {
                    pr.errors ~= TokenAndError(this.tokens.consume(),
                            "expected '=' after field name");
                }
                continue;
            }

            if (!peekNIsType(2, TokenType.STRING) && !peekNIsType(2, TokenType.NUMERIC))
            {
                this.tokens.consume(); // Symbox
                auto eq = this.tokens.consume(); //Equal
                if (this.tokens.isEOF())
                {
                    pr.errors ~= TokenAndError(eq,
                            "expected number or string to follow '=' in ALTER statement");
                }
                else
                {
                    pr.errors ~= TokenAndError(this.tokens.consume(),
                            "expected number or string to follow '=' in ALTER statement");
                }
                continue;
            }
            auto field = this.tokens.consume().stripQuotes();
            this.tokens.consume(); // =
            auto value = this.tokens.consume();
            a.keys ~= field;
            a.values ~= value;

            if (this.tokens.isEOF())
            {
                return;
            }
            else if (peekNIsType(0, TokenType.COMMA))
            {
                this.tokens.consume();
            }
            else
            {
                pr.errors ~= TokenAndError(value, "expected comma after value");
            }
        }
    }

    // precondition: token must be one of the bool op tokens
    @nogc ComparisonOp parseOp(Token tok)
    {
        switch (tok.typ)
        {
        case TokenType.OPEQ:
            return ComparisonOp.Equal;
        case TokenType.OPNEQ:
            return ComparisonOp.NotEqual;
        default:
            assert(0);
        }
    }

    bool peekNIsType(int n, TokenType t)
    {
        return this.tokens.canPeekN(n) && this.tokens.peekN(n).typ == t;
    }

    bool peekNIsOnOf(int n, TokenType[] ts...)
    {
        if (!this.tokens.canPeekN(n))
        {
            return false;
        }

        for (auto i = 0; i < ts.length; i++)
        {
            if (this.peekNIsType(n, ts[i]))
            {
                return true;
            }
        }

        return false;
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
            "expected from, where, on, or field names in select statement"));
}

unittest
{
    auto p = parserFromString("select from 'foo' where 'p' = 3");
    auto e = p.parse();
    assert(e.errors.length == 0);
    assert(e.expr.select.where.get!(EWhereSimple*).field == "p");
    assert(e.expr.select.where.get!(EWhereSimple*).operator == ComparisonOp.Equal);
    assert(e.expr.select.where.get!(EWhereSimple*).test.text == "3");
    assert(e.expr.select.where.get!(EWhereSimple*).test.typ == TokenType.NUMERIC);
}

unittest
{
    auto p = parserFromString("select from 'foo' order by 'bar' DESC");
    auto e = p.parse();
    assert(e.errors.length == 0);
    assert(e.expr.select.orderFields == ["bar"]);
    assert(e.expr.select.orderDirections == [Order.Desc]);
}
