.PHONY: build clean test

build:
	forge build

clean:
	rm -rf out

test:
	forge test

src/Demo.flat.sol: src/Demo.sol src/FVMPay.sol
	forge flatten $< > $@
