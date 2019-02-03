import std.stdio;

import tokens;
import parser;
import std.array;
import std.format;

int main(string[] args)
{
  auto q = args[1..$].join(" ");
  auto t = new TokenStream(q);
  auto p = new Parser(t);

  if (t.isEOF()) {
    usage();
    return 1;
  }

  auto result = p.parse();

  if (result.errors.length > 0) {
    foreach(const e ; result.errors) {
      import errors;
      formatError(stderr, q, e);
    }
    return 1;
  }

  switch (result.typ) {
    case Type.SELECT:
      string payload = "";
      if (result.expr.select.lowerLimit > 0) {
        payload = format(`-H "Content-Type: application/json" -d '{"size": %d}'`, result.expr.select.lowerLimit);
      }
      writefln("curl -XPOST http://localhost:9200/%s/_search?pretty=true %s", result.expr.select.from, payload);
      break;
    default:
      assert(0);
  }

  return 0;
}

void usage() {
  writefln("TODO: usage here");
}
