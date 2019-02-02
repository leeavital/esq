test:
	dub test

run:
	dub build
	./esq 'SELECT FROM "mytable"'
