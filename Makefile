SRC=$(wildcard source/**.d)

esq: $(SRC)
	dub build --build=release


test: integration_test unit_test

.PHONY: unit_test
unit_test:
	dub test

.PHONY: integration_test
integration_test: esq
	./test_suite/run.sh

.PHONY: format
format:
	dub run dfmt -- source/*.d

.PHONY: install
install: esq
	install esq /usr/local/bin
