SRC=$(wildcard source/**.d)

esq: $(SRC)
	dub build --build=release


test: integration_test unit_test

.PHONY: unit_test
unit_test: esq-test-library

esq-test-library: $(SRC)
	dub test

.PHONY: integration_test
integration_test: esq
	./test_suite/run.sh

.PHONY: format
format:
	dub run dfmt -- source/*.d

.PHONY: check_format
check_format:
	./test_suite/check_format.sh

.PHONY: install
install: esq
	install esq /usr/local/bin

clean:
	rm -f esq
	rm -f esq-test-library
	find test_suite \( -name actual.err -or -name actual.out  \) -delete
	find test_suite  -type d -empty -delete

