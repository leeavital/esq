enum BoolOp
{
    and,
    or,
    not
}

enum ComparisonOp
{
    Equal,
    NotEqual,
    Lt,
    Lte,
    Gt,
    Gte,
}

struct BinaryExpr
{
    Expr* left;
    ComparisonOp operator;
    Expr* right;
}

struct FuncCallExpr
{
    string fname;
    Expr[] args;
}

struct StringExpr
{
    string value;
}

struct NumExpr
{
    string value;
}

struct BoolExpr
{
    BoolOp op;
    Expr[] operands;
}

enum ExprType
{
    Binary,
    Boolean,
    Function,
    String,
    Number
}

Expr binaryExpr(Expr l, ComparisonOp op, Expr r)
{

    auto lH = new Expr();
    auto rH = new Expr();

    *lH = l;
    *rH = r;

    Expr e = {ExprType.Binary};
    e.binary = BinaryExpr(lH, op, rH);
    return e;
}

@nogc Expr stringExpr(string s)
{
    Expr e = {ExprType.String};
    e.str = StringExpr(s);
    return e;
}

@nogc Expr numExpr(string s)
{
    Expr e = {ExprType.Number};
    e.num = NumExpr(s);
    return e;
}

@nogc Expr fcallExpr(string fname, Expr[] args)
{
    Expr e = {ExprType.Function};
    e.func = FuncCallExpr(fname, args);
    return e;
}

@nogc Expr boolExpr(BoolOp op, Expr[] operands)
{
    Expr e = {ExprType.Boolean};
    e.boolE = BoolExpr(op, operands);
    return e;
}

struct Expr
{
    ExprType t;

    union
    {
        BinaryExpr binary;
        BoolExpr boolE;
        FuncCallExpr func;
        StringExpr str;
        NumExpr num;
    }

    @nogc bool isA(ExprType t1)
    {
        return this.t == t1;
    }

    string toString()
    {
        final switch (this.t)
        {
        case ExprType.Function:
            auto f = this.func;
            auto ss = f.fname ~ "(";
            for (int i = 0; i < f.args.length; i++)
            {
                if (i != 0)
                {
                    ss ~= ", ";
                }
                ss ~= f.args[i].toString();
            }

            ss ~= ")";
            return ss;
        case ExprType.Boolean:
            auto ss = "";
            auto b = this.boolE;

            string opString;
            final switch (b.op)
            {
            case BoolOp.or:
                opString = "or";
                break;
            case BoolOp.and:
                opString = "and";
                break;
            case BoolOp.not:
                opString = "not";
                break;
            }

            for (int i = 0; i < b.operands.length; i++)
            {
                if (i != 0)
                {
                    ss ~= " " ~ opString ~ " ";
                }
                ss ~= b.operands[i].toString();
            }
            return ss;
        case ExprType.Binary:
            import std.conv;

            auto b = this.binary;
            return b.left.toString() ~ b.operator.to!string ~ b.right.toString();
        case ExprType.String:
            return "str[" ~ this.str.value ~ "]";
        case ExprType.Number:
            return "num[" ~ this.num.value ~ "]";
        }
    }
}

unittest
{
    Expr e = stringExpr("e");
    Expr e2 = numExpr("1");
    Expr e3 = binaryExpr(e, ComparisonOp.Equal, e2);
    Expr e4 = fcallExpr("foo", [e, e2, e3]);
    Expr e5 = boolExpr(BoolOp.or, [e, e2, e3]);
    assert(e.isA(ExprType.String));
    assert(e2.isA(ExprType.Number));
    assert(e3.isA(ExprType.Binary));
    assert(e4.isA(ExprType.Function));
    assert(e5.isA(ExprType.Boolean));
}
