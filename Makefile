.PHONY: build clean test

build:
	forge build

clean:
	rm -rf out

test:
	forge test
	@forge test --json 2>/dev/null | python3 scripts/extract_gas.py
