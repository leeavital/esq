import parser;
import lexer;

import std.outbuffer;
import std.conv;
import std.format;

enum Target
{
    curl
}

string emitResult(Target t, ParseResult input)
{
    assert(t == Target.curl);

    auto buf = new OutBuffer();

    final switch (input.typ)
    {
    case Type.SELECT:
        auto hasBody = shouldWriteQueryBody(input.expr.select);

        buf.write(format("curl%s %s/%s/_search?pretty=true", hasBody
                ? " -XPOST" : "", getHost(input), input.expr.select.from));

        if (hasBody)
        {
            buf.write(` -H "Content-Type: application/json" -d `);
            buf.write(`'{ `); // start main request
            bool shouldLeadingComma = writeSize(input.expr.select, buf);
            shouldLeadingComma = writeSourceFilter(shouldLeadingComma,
                    input.expr.select.fieldNames, buf) || shouldLeadingComma;
            shouldLeadingComma = writeOrder(shouldLeadingComma,
                    input.expr.select.orderFields, input.expr.select.orderDirections, buf)
                || shouldLeadingComma;
            shouldLeadingComma = writeQuery(shouldLeadingComma, input.expr.select, buf)
                || shouldLeadingComma;
            buf.write(" }'"); // close main request
        }
        break;
    case Type.ALTER_INDEX:
        import std.stdio;

        auto alter = input.expr.alter;
        buf.write(format(`curl -XPUT '%s/%s/_settings?pretty=true' -H "Content-Type: application/json" -d `,
                getHost(input), alter.index));
        buf.write("'{ ");
        for (int i = 0; i < alter.keys.length; i++)
        {
            if (i != 0)
            {
                buf.write(", ");
            }
            buf.write(format(`"%s" : %s `, alter.keys[i], numOrStringAsJson(alter.values[i])));
        }
        buf.write("}'");
    }
    return buf.toString();
}

private bool writeOrder(bool shouldLeadingComma, string[] fields, Order[] directions, OutBuffer buf)
{
    if (fields.length == 0)
    {
        return false; // TODO: we can actually return shouldLeadingComma here with some cleanup
    }

    if (shouldLeadingComma)
    {
        buf.write(" ,");
    }

    buf.write(`"sort" : [ `);
    for (int i = 0; i < fields.length; i++)
    {
        buf.write(format(`{ "%s" : { "order" : %s } }`, fields[i], orderToJSON(directions[i])));
        if (i + 1 < fields.length)
        {
            buf.write(" , ");
        }
    }
    buf.write(" ]");
    return true;
}

private bool writeQuery(bool leadingComma, ESelect select, OutBuffer buf)
{
    if (!select.where.hasValue)
    {
        return false;
    }

    if (leadingComma)
    {
        buf.write(" , ");
    }

    buf.write(`"query": `);
    writeWhere(false, buf, select.where);

    return true;
}

private void writeWhere(bool shouldLeadingComma, OutBuffer buf, EWhere where)
{
    if (shouldLeadingComma)
    {
        buf.write(" , ");
    }

    if (where.peek!(EWhereSimple*))
    {
        auto simple = where.get!(EWhereSimple*);
        writeWhereSimple(buf, simple);
    }
    else // is complex
    {
        auto complex = where.get!(EWhereComplex*);
        buf.write(`{ "bool" : { `);
        buf.write(format(`"%s" : [ `, boolOpToESOp(complex.operator)));
        auto leadingComma = false;
        foreach (EWhere c; complex.operands)
        {
            writeWhere(leadingComma, buf, c);
            leadingComma = true;
        }
        buf.write(format(" ]")); // close operations
        buf.write(" }"); // close bool
        buf.write(" }"); // close object
    }
}

private void writeWhereSimple(OutBuffer buf, EWhereSimple* simple)
{
    final switch (simple.operator)
    {
      case ComparisonOp.Equal:
        assert(simple.operator == ComparisonOp.Equal);
        buf.write(`{ "term": { `);
        buf.write(format(`"%s" : `, simple.field));
        buf.write(numOrStringAsJson(simple.test));
        buf.write(` }`); // close term
        buf.write(` }`); // close object
        break;
      case ComparisonOp.NotEqual:
        EWhereSimple copy = *simple;
        copy.operator = ComparisonOp.Equal;
        EWhereComplex negated = EWhereComplex(BoolOp.not, [ EWhere(&copy) ] );
        writeWhere(false, buf, EWhere(&negated));
        break;
    }
}

private bool writeSourceFilter(bool shouldLeadingComma, string[] fields, OutBuffer buf)
{
    if (fields.length == 0)
    {
        return false;
    }

    if (shouldLeadingComma)
    {
        buf.write(" , ");
    }

    buf.write(`"_source" : [ `);
    for (int i = 0; i < fields.length; i++)
    {
        auto name = fields[i];
        buf.write(format(`"%s"`, name));
        if (i != fields.length - 1)
        {
            buf.write(" , ");
        }
    }
    buf.write(` ]`);
    return true;
}

private bool writeSize(ESelect select, OutBuffer buf)
{
    if (select.lowerLimit > 0)
    {
        buf.write(format(`"size": %d`, select.lowerLimit));
        return true;
    }
    return false;
}

@nogc private bool shouldWriteQueryBody(ESelect e)
{
    return e.lowerLimit > 0 || e.where.hasValue || e.orderFields.length > 0
        || e.fieldNames.length > 0;
}

@nogc private string orderToJSON(Order order)
{
    final switch (order)
    {
    case Order.Asc:
        return `"asc"`;
    case Order.Desc:
        return `"desc"`;
    }
}

private string numOrStringAsJson(Token t)
{

    switch (t.typ)
    {
    case TokenType.NUMERIC:
        return t.text;
    case TokenType.STRING:
        return format(`"%s"`, t.stripQuotes());
    default:
        assert(0);
    }
}

@nogc private string boolOpToESOp(BoolOp o)
{
    final switch (o)
    {
    case BoolOp.and:
        return "must";
    case BoolOp.or:
        return "should";
    case BoolOp.not:
        return "must_not";
    }
}

string getHost(ParseResult pr)
{
    import std.algorithm.searching : startsWith;

    if (pr.host != "")
    {
        if (pr.host.startsWith("http://") || pr.host.startsWith("https://"))
        {
            return pr.host;
        }
        return "http://" ~ pr.host;
    }
    return "http://localhost:9200";
}

unittest
{
    import std.stdio;

    string[] errors = [];
    void check(string input, string output)
    {
        auto p = ParseResult();
        p.host = input;
        auto s = getHost(p);
        if (s != output)
        {
            errors ~= format("expected getHost(%s) to be %s, but was %s", input, output, s);
        }
    }

    check("", "http://localhost:9200");
    check("localhost:1000", "http://localhost:1000");
    check("https://my.cool.host", "https://my.cool.host");

    if (errors.length > 0)
    {
        writefln("%s", errors);
        assert(0);
    }
}

unittest
{
    import std.stdio;

    auto e = Expr();
    e.select.from = "idx";
    e.select.lowerLimit = 10;
    EWhereSimple where = EWhereSimple(ComparisonOp.Equal, "foo",
            Token(TokenType.NUMERIC, 200, "10"));
    e.select.where = &where;
    const s = emitResult(Target.curl, ParseResult(Type.SELECT, e, []));
    auto expected = `curl -XPOST http://localhost:9200/idx/_search?pretty=true -H "Content-Type: application/json" -d '{ "size": 10 , "query": { "term": { "foo" : 10 } } }'`;
    if (s != expected)
    {
        writefln("expected emit to be %s but was %s", expected, s);
        assert(0);
    }
}
