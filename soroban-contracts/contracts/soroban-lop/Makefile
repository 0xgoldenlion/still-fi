default: build

all: test

test: build
	$(MAKE) -C ../soroban-dutch-auction || break;
	cargo test

build:
	stellar contract build
	@ls -l target/wasm32-unknown-unknown/release/*.wasm

fmt:
	cargo fmt --all

clean:
	cargo clean