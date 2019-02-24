import parser;
import std.stdio;

// we could get really fancy here and deal with multi-line sources, but
// those are pretty unlikely to show up, so I'll just assume that all
// 'sources' are one line, and are short enough to print fully.
// Ideally, we'd only print the line on which the error appeared, and
// also only print 40 or so chars on each side so the errors stay nice
// and readable.
void formatError(File f, const string source, const TokenAndError terr)
{
    f.write(source);
    f.write("\n");
    auto tok = terr.token;
    for (int i = 0; i < tok.startPos; i++)
    {
        f.write(" ");
    }
    for (int i = 0; i < tok.text.length; i++)
    {
        f.write("^");
    }
    f.write("\n");
    f.write(terr.error);
    f.write("\n");
}
