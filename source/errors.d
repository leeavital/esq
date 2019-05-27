import parser;
import lexer;
import std.stdio;
import lexer;

// we could get really fancy here and deal with multi-line sources, but
// those are pretty unlikely to show up, so I'll just assume that all
// 'sources' are one line, and are short enough to print fully.
// Ideally, we'd only print the line on which the error appeared, and
// also only print 40 or so chars on each side so the errors stay nice
// and readable.
void formatError(T)(File f, const string source, const T terr)
{
    alias R = RangeAndMessage!T;

    f.write(source);
    f.write("\n");
    for (ulong i = 0; i < R.startPos(terr); i++)
    {
        f.write(" ");
    }
    for (ulong i = R.startPos(terr); i < R.endPos(terr); i++)
    {
        f.write("^");
    }
    f.write("\n");
    f.write(R.text(terr));
    f.write("\n");
}

template RangeAndMessage(T : TokenAndError)
{
    ulong startPos(TokenAndError t)
    {
        return t.token.startPos;
    }

    ulong endPos(TokenAndError t)
    {
        return t.token.startPos + t.token.text.length;
    }

    string text(TokenAndError t)
    {
        return t.error;
    }
}

template RangeAndMessage(T : AutoFix)
{
    ulong startPos(AutoFix t)
    {
        return t.pos;
    }

    ulong endPos(AutoFix t)
    {
        return t.pos + 1;
    }

    string text(AutoFix t)
    {
        return t.message;
    }
}
