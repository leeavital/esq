import parser;
import tokens;

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

        buf.write(format("curl %shttp://localhost:9200/%s/_search?pretty=true",
                hasBody ? "-XPOST " : "", input.expr.select.from));

        if (hasBody)
        {
            buf.write(` -H "Content-Type: application/json" -d `);
            buf.write(`'{ `); // start main request
            bool shouldLeadingComma = writeSize(input.expr.select, buf);
            shouldLeadingComma = writeOrder(shouldLeadingComma,
                    input.expr.select.orderFields, input.expr.select.orderDirections, buf)
                || shouldLeadingComma;
            shouldLeadingComma = writeQuery(shouldLeadingComma, input.expr.select, buf)
                || shouldLeadingComma;
            buf.write(" }'"); // close main request
        }
        break;
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

    buf.write(`"order" : [ `);
    for (int i = 0; i < fields.length; i++)
    {
        buf.write(format(`{ "%s" : %s }`, fields[i], orderToJSON(directions[i])));
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
    if (select.where == EWhere())
    {
        return false;
    }

    if (leadingComma)
    {
        buf.write(" , ");
    }

    buf.write(`"query": { `);
    buf.write(`"term": { `);
    buf.write(format(`"%s" : `, select.where.field));
    switch (select.where.test.typ)
    {
    case TokenType.NUMERIC:
        buf.write(select.where.test.text);
        break;
    case TokenType.STRING:
        buf.write(format(`"%s"`, select.where.test.stripQuotes()));
        break;
    default:
        assert(0);
    }
    buf.write(` }`); // close term
    buf.write(` }`); // close query

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
    return e.lowerLimit > 0 || e.where != EWhere() || e.orderFields.length > 0;
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

unittest
{
    import std.stdio;

    auto e = Expr();
    e.select.from = "idx";
    e.select.lowerLimit = 10;
    e.select.where = EWhere(BoolOp.Equal, "foo", Token(TokenType.NUMERIC, 200, "10"));
    const s = emitResult(Target.curl, ParseResult(Type.SELECT, e, []));

    auto expected = `curl -XPOST http://localhost:9200/idx/_search?pretty=true -H "Content-Type: application/json" -d '{ "size": 10 , "query": { "term": { "foo" : 10 } } }'`;
    if (s != expected)
    {
        writefln("expected emit to be %s but was %s", expected, s);
        assert(0);
    }
}
