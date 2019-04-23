import parser;
import lexer;

import std.outbuffer;
import std.conv;
import std.format;
import json;

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

            JsonWriter wr;
            writeSize(&wr, input.expr.select);
            writeSourceFilter(&wr, input.expr.select.aggregation, input.expr.select.fieldNames);
            writeOrder(&wr, input.expr.select.orderFields, input.expr.select.orderDirections);
            writeQuery(&wr, input.expr.select);
            writeAggregations(&wr, input.expr.select.aggregation, input.expr.select.fieldNames);

            buf.write("'");
            buf.write(wr.toString());
            buf.write("'");
        }
        break;
    case Type.ALTER_INDEX:
        import std.stdio;

        auto alter = input.expr.alter;
        buf.write(format(`curl -XPUT '%s/%s/_settings?pretty=true' -H "Content-Type: application/json" -d `,
                getHost(input), alter.index));

        JsonWriter wr;
        for (int i = 0; i < alter.keys.length; i++)
        {
            auto value = alter.values[i];
            switch (value.typ)
            {
            case TokenType.STRING:
                wr.field(alter.keys[i], value.stripQuotes());
                break;
            case TokenType.NUMERIC:
                wr.literalField(alter.keys[i], value.text);
                break;
            default:
                assert(0);
            }
        }
        buf.write("'");
        buf.write(wr.toString());
        buf.write("'");
    }
    return buf.toString();
}

@nogc private void writeOrder(JsonWriter* jwriter, string[] fields, Order[] directions)
{
    if (fields.length == 0)
    {
        return;
    }

    jwriter.startArray("sort");
    for (int i = 0; i < fields.length; i++)
    {
        auto name = fields[i];
        auto direction = orderToJSON(directions[i]);

        jwriter.startObject();
        jwriter.startObject(name);
        jwriter.field("order", direction);
        jwriter.endObject();
        jwriter.endObject();
    }
    jwriter.endArray();
}

private void writeQuery(JsonWriter* jwriter, ESelect select)
{
    if (!select.where.hasValue)
    {
        return;
    }

    jwriter.startObject("query");
    writeWhere(jwriter, select.where);
    jwriter.endObject();
}

@nogc private void writeAggregations(JsonWriter* jwriter, Aggregation agg, string[] fieldNames)
{
    final switch (agg)
    {
    case Aggregation.None:
        return;
    case Aggregation.Distinct:
        jwriter.startObject("aggs");
        jwriter.startObject(fieldNames[0]); // name of the aggregation
        jwriter.startObject("terms");
        jwriter.field("field", fieldNames[0]);
        jwriter.endObject();
        jwriter.endObject();
        jwriter.endObject();
        return;
    case Aggregation.CountDistinct:
        jwriter.startObject("aggs");
        jwriter.startObject(fieldNames[0]); // name of the aggregation
        jwriter.startObject("cardinality");
        jwriter.field("field", fieldNames[0]);
        jwriter.endObject();
        jwriter.endObject();
        jwriter.endObject();
        return;
    }
}

private void writeWhere(JsonWriter* buf, EWhere where)
{
    if (where.peek!(EWhereSimple*))
    {
        auto simple = where.get!(EWhereSimple*);
        writeWhereSimple(buf, simple);
    }
    else // is complex
    {
        auto complex = where.get!(EWhereComplex*);
        buf.startObject("bool");
        buf.startArray(boolOpToESOp(complex.operator));
        foreach (EWhere c; complex.operands)
        {
            buf.startObject();
            writeWhere(buf, c);
            buf.endObject();
        }
        buf.endArray();
        buf.endObject();
    }
}

private void writeWhereSimple(JsonWriter* jwriter, EWhereSimple* simple)
{
    final switch (simple.operator)
    {
    case ComparisonOp.Equal:
        assert(simple.operator == ComparisonOp.Equal);
        jwriter.startObject("term");
        switch (simple.test.typ)
        {
        case TokenType.STRING:
            jwriter.field(simple.field, simple.test.stripQuotes());
            break;
        case TokenType.NUMERIC:
            jwriter.literalField(simple.field, simple.test.text);
            break;
        default:
            assert(0);
        }
        jwriter.endObject();
        break;
    case ComparisonOp.NotEqual:
        EWhereSimple copy = *simple;
        copy.operator = ComparisonOp.Equal;
        EWhereComplex negated = EWhereComplex(BoolOp.not, [EWhere(&copy)]);
        writeWhere(jwriter, EWhere( & negated));
    }
}

@nogc private bool writeSourceFilter(JsonWriter * jwriter, Aggregation agg, string[] fields)
{
    if (fields.length == 0 || agg != Aggregation.None)
    {
        return false;
    }

    jwriter.startArray("_source");
    for (int i = 0; i < fields.length; i++)
    {
        auto name = fields[i];
        jwriter.value(name);
    }
    jwriter.endArray();
    return true;
}

@nogc private bool writeSize(JsonWriter* jwriter, ESelect select)
{
    if (select.lowerLimit > 0)
    {
        jwriter.field("size", select.lowerLimit);
        return true;
    }
    return false;
}

@nogc private bool shouldWriteQueryBody(ESelect e)
{
    return e.lowerLimit > 0 || e.where.hasValue || e.orderFields.length > 0
        || e.fieldNames.length > 0 || e.aggregation != Aggregation.None;
}

@nogc private string orderToJSON(Order order)
{
    final switch (order)
    {
    case Order.Asc:
        return `asc`;
    case Order.Desc:
        return `desc`;
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
    auto expected = `curl -XPOST http://localhost:9200/idx/_search?pretty=true -H "Content-Type: application/json" -d '{ "size" : 10 , "query" : { "term" : { "foo" : 10 } } }'`;
    if (s != expected)
    {
        writefln("expected emit to be:\n%s \nbut was:\n%s", expected, s);
        assert(0);
    }
}
