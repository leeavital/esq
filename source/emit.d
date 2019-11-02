import expr_ast;
import json;
import lexer;
import parser;

import std.conv;
import std.format;
import std.outbuffer;

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
            writeAggregations(&wr, input.expr.select.aggregation,
                    input.expr.select.fieldNames, input.expr.select.lowerLimit);

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
    if (select.where == Expr())
    {
        return;
    }

    jwriter.startObject("query");
    writeWhere(jwriter, select.where);
    jwriter.endObject();
}

@nogc private void writeAggregations(JsonWriter* jwriter, Aggregation agg,
        string[] fieldNames, int limit)
{

    if (agg == Aggregation.None)
    {
        return;
    }

    string aggName;
    final switch (agg)
    {
    case Aggregation.None:
        assert(0);
    case Aggregation.Distinct:
        aggName = "terms";
        break;
    case Aggregation.CountDistinct:
        aggName = "cardinality";
        break;
    }

    foreach (const fn; fieldNames)
    {
        jwriter.startObject("aggregations");
        jwriter.startObject(fn); // agg label
        jwriter.startObject(aggName); // aggType
        jwriter.field("field", fn);
        if (limit > 0)
        {
            jwriter.field("size", limit);
        }
        jwriter.endObject();
    }

    foreach (const fn; fieldNames)
    {
        jwriter.endObject();
        jwriter.endObject();
    }
}

private void writeWhere(JsonWriter* buf, Expr expr)
{
    final switch (expr.t)
    {
    case ExprType.Binary:
        auto lhs = expr.binary.left;
        auto rhs = expr.binary.right;
        auto op = expr.binary.operator;

        assert(lhs.t == ExprType.String);
        auto fieldName = lhs.str.value;

        final switch (op)
        {
        case ComparisonOp.Equal:
            buf.startObject("term");
            writeFieldExpr(buf, fieldName, rhs);
            buf.endObject(); // end term
            return;
        case ComparisonOp.Lt:
            goto case;
        case ComparisonOp.Lte:
            goto case;
        case ComparisonOp.Gt:
            goto case;
        case ComparisonOp.Gte:
            auto comparison = comparisonToName[op];
            buf.startObject("range");
            buf.startObject(fieldName);
            writeFieldExpr(buf, comparison, rhs);
            buf.endObject(); // end field
            buf.endObject(); // end range
            return;
        case ComparisonOp.NotEqual:
            auto negated = binaryExpr(*lhs, ComparisonOp.Equal, *rhs);
            writeWhere(buf, boolExpr(BoolOp.not, [negated]));
            return;
        case ComparisonOp.In:
            buf.startObject("terms");
            buf.startArray(fieldName);
            import std.stdio;

            assert(rhs.t == ExprType.List);
            foreach (const re; rhs.list.exprs)
            {
                final switch (re.t)
                {
                case ExprType.String:
                    buf.value(re.str.value);
                    break;
                case ExprType.Number:
                    buf.literalValue(re.num.value);
                    break;
                case ExprType.Binary, ExprType.Boolean, ExprType.Function,
                        ExprType.List:
                        assert(0);
                }

            }
            buf.endArray();
            buf.endObject();
            return;
        }
    case ExprType.Boolean:
        auto boolExp = expr.boolE;
        buf.startObject("bool");
        buf.startArray(boolOpToESOp(boolExp.op));

        foreach (Expr e; boolExp.operands)
        {
            buf.startObject();
            writeWhere(buf, e);
            buf.endObject();
        }
        buf.endArray(); // end operator
        buf.endObject(); // end bool object

        return;
    case ExprType.Function:
        import std.string;

        auto func = expr.func;
        if (func.fname.toLower() == "exists")
        {
            buf.startObject("exists");
            buf.field("field", func.args[0].str.value);
            buf.endObject();
        }
        else if (func.fname.toLower() == "match")
        {
            buf.startObject("match");
            buf.startObject(func.args[0].str.value);
            buf.field("query", func.args[1].str.value);
            buf.endObject();
            buf.endObject();
        }
        else
        {
            buf.field("not implemented", 0);
        }
        return;
    case ExprType.Number:
        assert(0);
    case ExprType.String:
        assert(0);
    case ExprType.List:
        assert(0);
    }
}

@nogc writeFieldExpr(JsonWriter* buf, string fieldName, const Expr* expr)
{
    final switch (expr.t)
    {
    case ExprType.String:
        buf.field(fieldName, expr.str.value);
        break;
    case ExprType.Number:
        buf.literalField(fieldName, expr.num.value);
        break;
    case ExprType.Binary, ExprType.Boolean, ExprType.Function, ExprType.List:
        assert(0);
    }
}

immutable string[ComparisonOp] comparisonToName;
static this()
{
    comparisonToName[ComparisonOp.Gte] = "gte";
    comparisonToName[ComparisonOp.Lte] = "lte";
    comparisonToName[ComparisonOp.Gt] = "gt";
    comparisonToName[ComparisonOp.Lt] = "lt";
}

@nogc private bool writeSourceFilter(JsonWriter* jwriter, Aggregation agg, string[] fields)
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
    return e.lowerLimit > 0 || e.where != Expr() || e.orderFields.length > 0
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
