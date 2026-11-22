# speedyG — punto de entrada único de construcción y verificación.
# Uso: make [build|test|verify|fmt|clippy|clean]
# Requiere Linux, bash y el toolchain fijado en rust-toolchain.toml.

CARGO ?= cargo

.PHONY: all build test fmt clippy run-all verify clean

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

# Casos de verificación. run-all.sh usa los binarios de target/debug,
# por eso se compilan aquí.
run-all:
	$(CARGO) build --locked --bins
	bash verif/scripts/run-all.sh

# Verificación completa: fmt, clippy -D warnings, test y run-all.sh.
verify: fmt clippy test run-all

clean:
	$(CARGO) clean
