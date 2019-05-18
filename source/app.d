import std.stdio;
import lexer;
import parser;
import emit;
import std.array;
import std.format;

int main(string[] args)
{
    if (args.length != 2)
    {
        usage();
        return 1;
    }

    auto q = args[1];
    auto t = new TokenStream(q);
    auto p = new Parser(t);

    if (t.isEOF())
    {
        usage();
        return 1;
    }

    auto result = p.parse();

    if (result.errors.length > 0)
    {
        import errors;

        foreach (const e; result.errors)
        {
            formatError(stderr, q, e);
        }
        return 1;
    }

    auto curlOut = emitResult(Target.curl, result);
    writeln(curlOut);
    return 0;

}

void usage()
{
    import std.string;

    auto u = `
    esq -- a swiss army knife for elasticsearch

    esq is meant to be installed on a local machine, and outputs curl commands which
    can be piped, or easily copied into a remote session.

    github.com/leeavital/esq/

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
