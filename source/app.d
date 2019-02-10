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
    import errors;
    foreach(const e ; result.errors) {
      formatError(stderr, q, e);
    }
    return 1;
  }

  switch (result.typ) {
    case Type.SELECT:
      string json = getPayload(result.expr.select);
      auto payload = "";
      if (json != "") {
        payload = format(`-H "Content-Type: application/json" -d '%s'`, json);
      }
      writefln("curl -XPOST http://localhost:9200/%s/_search?pretty=true %s", result.expr.select.from, payload);
      break;
    default:
      assert(0);
  }

  return 0;
}

string getPayload(ESelect s) {
  import std.stdio;

  // TODO: this whole thing should be in its own module that is less if-elsey.
  // TODO: using s.where.test.text is not safe for json embedding because it might be single-quote wrapped

  auto json = "";
  if (s.lowerLimit != 0) {
    if (s.where == EWhere.init) {
        json = format(`{"size": %d}`, s.lowerLimit);
    } else {
        json = format(`{"size": %d, "query": {"term": {"%s", %s}}}`, s.lowerLimit, s.where.field, s.where.test.text);
    }
  } else if (s.where != EWhere.init) {
      json = format(`{"query": {"term": {"%s", %s}}}`, s.where.field, s.where.test.text);
  }
  return json;
}

void usage() {
  import std.string;
  auto u = `
    esq -- a swiss army knife for elasticsearch

    esq is meant to be installed on a local machine, and outputs curl commands which
    can be piped, or easily copied into a remote session.

    For example:

      esq 'SELECT FROM "testindex" LIMIT 10

    Will output a query to select 10 items from the index "testindex".

      curl -XPOST http://localhost:9200/testindex/_search?pretty=true -H "Content-Type: application/json" -d '{"size": 10}'

    You can pipe the output directly into a vagrant session:

      esq 'SELECT FROM "testindex" LIMIT 10 | vagrant ssh

    Or kubernetes shell:

      esq 'SELECT FROM "testindex" LIMIT 10 | kubectl exec -it my-pod-name /bin/bash

    Or vanilla SSH session:

      esq 'SELECT FROM "testindex" LIMIT 10 | ssh my-elasticsearch-host
    `;

  write(outdent(u));

}
