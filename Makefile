.PHONY: build clean test

build:
	forge build

clean:
	rm -rf out

test:
	forge test
	@forge snapshot --no-match-test "Fuzz"
