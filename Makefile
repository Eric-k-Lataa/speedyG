# speedyG — punto de entrada único de construcción y verificación.
# Uso: make [build|test|verify|fmt|clippy|clean]
# Requiere Linux, bash y el toolchain fijado en rust-toolchain.toml.

CARGO ?= cargo

.PHONY: all build test fmt clippy verify clean

all: build

# Binarios de entrega: target/release/speedyG (daemon) y target/release/speedyg (cliente)
build:
	$(CARGO) build --release --locked

test:
	$(CARGO) test --locked

fmt:
	$(CARGO) fmt --check

clippy:
	$(CARGO) clippy --locked -- -D warnings

# Verificación completa: fmt, clippy -D warnings, test y run-all.sh.
# run-all.sh usa los binarios de target/debug, por eso se compilan aquí.
verify: fmt clippy test
	$(CARGO) build --locked --bins
	bash verif/scripts/run-all.sh

clean:
	$(CARGO) clean
