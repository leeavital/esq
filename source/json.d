import std.container;

@nogc struct JsonWriter
{
    Array!char buffer;
    bool[100] hasField;
    int fieldI = 0;

    string toString()
    {
        import std.conv;

        char[] c = new char[this.buffer.length + 4];
        int i = 0;
        c[0] = '{';
        c[1] = ' ';
        i = 2;
        foreach (const v; this.buffer)
        {
            c[i++] = v;
        }
        c[i++] = ' ';
        c[i] = '}';
        return c.idup;
    }

    @nogc JsonWriter startObject(string name)
    {
        writeCommaIfNeeded();
        hasField[++fieldI] = false;
        this.append(`"`).append(name).append(`"`);
        return this.append(" : { ");
    }

    @nogc JsonWriter startObject()
    {
        writeCommaIfNeeded();
        hasField[++fieldI] = false;
        return this.append("{ ");
    }

    @nogc JsonWriter startArray(string name)
    {
        writeCommaIfNeeded();
        hasField[++fieldI] = false;
        this.append(`"`).append(name).append(`"`);
        return this.append(" : [ ");
    }

    @nogc JsonWriter field(string name, int v)
    {
        import std.conv : toChars;

        writeCommaIfNeeded();
        appendWithQuotes(name);
        this.append(" : ");

        auto ch = v.toChars();
        foreach (const c; ch)
        {
            this.buffer.insertBack(c);
        }
        return this;
    }

    @nogc JsonWriter field(string name, string v)
    {
        writeCommaIfNeeded();
        appendWithQuotes(name);
        this.append(" : ");
        return appendWithQuotes(v);
    }

    @nogc literalField(string name, string v)
    {
        writeCommaIfNeeded();
        appendWithQuotes(name);
        this.append(" : ");
        return append(v);
    }

    @nogc JsonWriter value(string v)
    {
        writeCommaIfNeeded();
        return appendWithQuotes(v);
    }

    @nogc JsonWriter literalValue(string v)
    {
        writeCommaIfNeeded();
        return append(v);
    }

    @nogc JsonWriter endObject()
    {
        hasField[fieldI--] = false;
        return this.append(" }");
    }

    @nogc JsonWriter endArray()
    {
        hasField[fieldI--] = false;
        return this.append(" ]");
    }

    @nogc private JsonWriter appendWithQuotes(string value)
    {
        return this.append(`"`).append(value).append(`"`);
    }

    @nogc private void writeCommaIfNeeded()
    {
        auto shouldComma = this.hasField[fieldI];
        if (shouldComma)
        {
            this.append(" , ");
        }
        this.hasField[fieldI] = true;
    }

    @nogc private JsonWriter append(string s)
    {
        foreach (const c; s)
        {
            this.buffer.insertBack(c);
        }
        return this;
    }
}
