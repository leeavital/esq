import std.stdio;

import tokens;
import parser;
import std.array;

void main(string[] args)
{
  auto q = args[1..$].join(" ");
  auto t = new TokenStream(q);
  auto p = new Parser(t);

  auto result = p.parse();

  switch (result.typ) {
    case Type.SELECT:
      writefln("curl -XPOST http://localhost:9200/%s/_search", result.expr.select.from);
      break;
    default:
      assert(0);
  }
}
