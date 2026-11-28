#!/bin/bash
# verif/scripts/TC-014.sh
#
# TC-014 — Construcción reproducible desde un clon limpio
#
# Clona el repositorio (commit HEAD, o TC014_REF si se define) en un directorio
# temporal, y construye y verifica ahí con los comandos documentados de make.
# Solo se incluye lo que está commiteado: los cambios sin commit NO se prueban.
#
# Uso:
#   bash verif/scripts/TC-014.sh
#   TC014_REF=v1.0.0-rc1 bash verif/scripts/TC-014.sh   # etiqueta o commit concreto
#   TC014_KEEP_CLONE=1  bash verif/scripts/TC-014.sh    # conserva el clon para depurar
#
# No usa los binarios de target/debug ni se invoca desde run-all.sh: tarda varios
# minutos (compila SQLite embebido) y run-all.sh dentro del clon se llamaría a sí
# mismo. Requiere red para descargar dependencias y, si no está, el toolchain.
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RNF-01: compilar y ejecutar en Linux declarado
#   - RNF-02: construcción reproducible desde clon limpio
#   - RNF-03: sin privilegios de root
#   - RNF-19: compilar sin advertencias
#   - RNF-20: pruebas con un único comando documentado
#
# Resultados en:
#   verif/results/TC-014/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

setup_run_env "TC-014"

REF="${TC014_REF:-}"
CLONE="$(mktemp -d "/tmp/speedyg-TC-014-clone-XXXXXX")"
unset CARGO_TARGET_DIR   # el clon debe usar su propio target/

# Ejecuta un comando en el clon, guarda su salida y devuelve su código.
# Uso: run_in_clone <nombre-log> <comando...>
run_in_clone() {
    local name="$1"; shift
    (cd "$CLONE" && "$@") > "$RUN_DIR/$name.log" 2>&1
    local rc=$?
    echo "$name: rc=$rc ($*)" >> "$RUN_DIR/commands.txt"
    return $rc
}

: > "$RUN_DIR/commands.txt"

# ── RNF-01 / RNF-03: entorno ─────────────────────────────────────────────────
OS_NAME="$(uname -s)"
check "[RNF-01] Sistema operativo es Linux (uname -s = $OS_NAME)" \
    "$([[ "$OS_NAME" == "Linux" ]] && echo 0 || echo 1)"

UID_NOW="$(id -u)"
echo "id -u = $UID_NOW" > "$RUN_DIR/id.txt"
check "[RNF-03] La construcción no se ejecuta como root (id -u = $UID_NOW)" \
    "$([[ "$UID_NOW" -ne 0 ]] && echo 0 || echo 1)"

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
    echo "[INFO] Hay cambios sin commit en $REPO_ROOT; el clon NO los incluye." | tee -a "$LOG"
fi

# ── Clon limpio ──────────────────────────────────────────────────────────────
git clone --quiet --no-hardlinks "$REPO_ROOT" "$CLONE" > "$RUN_DIR/clone.log" 2>&1
CLONE_RC=$?
if [[ $CLONE_RC -eq 0 && -n "$REF" ]]; then
    git -C "$CLONE" checkout --quiet "$REF" >> "$RUN_DIR/clone.log" 2>&1
    CLONE_RC=$?
fi
check "[RNF-02] Clon limpio creado (ref: ${REF:-HEAD})" "$CLONE_RC"
if [[ $CLONE_RC -ne 0 ]]; then
    rm -rf "$CLONE"
    finish_run
fi

CLONE_COMMIT="$(git -C "$CLONE" rev-parse HEAD)"
CLONE_DESCRIBE="$(git -C "$CLONE" describe --tags --always 2>/dev/null || echo n/a)"
{
    echo "clone_dir=$CLONE"
    echo "ref=${REF:-HEAD}"
    echo "commit=$CLONE_COMMIT"
    echo "describe=$CLONE_DESCRIBE"
} > "$RUN_DIR/clone-info.txt"
echo "[INFO] Commit probado: $CLONE_COMMIT ($CLONE_DESCRIBE)" | tee -a "$LOG"

# ── RNF-02: archivos de reproducibilidad versionados ─────────────────────────
check "[RNF-02] rust-toolchain.toml versionado" \
    "$(git -C "$CLONE" ls-files --error-unmatch rust-toolchain.toml >/dev/null 2>&1 && echo 0 || echo 1)"
check "[RNF-02] Cargo.lock versionado" \
    "$(git -C "$CLONE" ls-files --error-unmatch Cargo.lock >/dev/null 2>&1 && echo 0 || echo 1)"

# ── Sin binarios ni artefactos versionados ───────────────────────────────────
TRACKED_TARGET="$(git -C "$CLONE" ls-files | grep -E '^target/' || true)"
TRACKED_ELF="$(
    cd "$CLONE" && git ls-files | while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        [[ "$(head -c4 "$f" | od -An -tx1 | tr -d ' \n')" == "7f454c46" ]] && echo "$f"
    done
)"
{
    echo "tracked_target=${TRACKED_TARGET:-ninguno}"
    echo "tracked_elf=${TRACKED_ELF:-ninguno}"
} > "$RUN_DIR/tracked-artifacts.txt"
check "[RNF-02] Sin target/ versionado" \
    "$([[ -z "$TRACKED_TARGET" ]] && echo 0 || echo 1)"
check "[RNF-02] Sin binarios ELF versionados" \
    "$([[ -z "$TRACKED_ELF" ]] && echo 0 || echo 1)"

# ── RNF-20: un único comando documentado ─────────────────────────────────────
run_in_clone make-n-verify make -n verify
check "[RNF-20] 'make verify' definido en el Makefile del clon" "$?"
check "[RNF-20] README documenta 'make verify'" \
    "$(grep -q 'make verify' "$CLONE/README.md" && echo 0 || echo 1)"

# ── RNF-02 / RNF-19: construcción ────────────────────────────────────────────
echo "[INFO] make build (puede tardar varios minutos)..." | tee -a "$LOG"
run_in_clone build make build
BUILD_RC=$?
check "[RNF-02] make build (cargo build --release --locked) termina con éxito" "$BUILD_RC"

WARN_COUNT="$(grep -cE '^warning' "$RUN_DIR/build.log" || true)"
echo "warnings_en_build=$WARN_COUNT" > "$RUN_DIR/warnings.txt"
check "[RNF-19] Build sin advertencias (warnings: $WARN_COUNT)" \
    "$([[ "${WARN_COUNT:-0}" -eq 0 ]] && echo 0 || echo 1)"

for bin in speedyG speedyg; do
    check "[RNF-02] target/release/$bin existe y es ejecutable" \
        "$([[ -x "$CLONE/target/release/$bin" ]] && echo 0 || echo 1)"
done
ls -l "$CLONE"/target/release/speedyG "$CLONE"/target/release/speedyg \
    > "$RUN_DIR/binaries.txt" 2>&1 || true

check "[RNF-02] Cargo.lock no cambió durante el build (reproducible con --locked)" \
    "$(git -C "$CLONE" diff --quiet -- Cargo.lock && echo 0 || echo 1)"

# ── Entorno del clon: distribución, toolchain, dependencias y commit ─────────
# Se consulta desde el clon (rust-toolchain.toml aplica ahí), no desde el repo original.
PINNED_CHANNEL="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$CLONE/rust-toolchain.toml" | tr -d '\r')"
CLONE_RUSTC="$(cd "$CLONE" && rustc --version 2>/dev/null || echo n/a)"
{
    echo "== distribucion (/etc/os-release) =="
    if [[ -r /etc/os-release ]]; then
        grep -E '^(PRETTY_NAME|NAME|VERSION|VERSION_ID|ID)=' /etc/os-release
    else
        echo "n/a"
    fi
    echo "kernel=$(uname -r)"
    echo "arch=$(uname -m)"
    echo "== toolchain del clon =="
    echo "toolchain_fijado=$PINNED_CHANNEL"
    echo "rustc=$CLONE_RUSTC"
    echo "cargo=$(cd "$CLONE" && cargo --version 2>/dev/null || echo n/a)"
    echo "== commit del clon =="
    echo "commit=$CLONE_COMMIT"
    echo "describe=$CLONE_DESCRIBE"
    echo "== dependencias =="
    echo "cargo_lock_sha256=$(sha256sum "$CLONE/Cargo.lock" | cut -d' ' -f1)"
} > "$RUN_DIR/clone-environment.txt"
run_in_clone dependencies cargo tree --locked --depth 1
check "[RNF-02] rustc del clon corresponde al toolchain fijado (${PINNED_CHANNEL:-n/a}): $CLONE_RUSTC" \
    "$([[ -n "$PINNED_CHANNEL" && "$CLONE_RUSTC" == *"$PINNED_CHANNEL"* ]] && echo 0 || echo 1)"
check "[RNF-02] Lista de dependencias registrada (cargo tree --locked)" \
    "$([[ -s "$RUN_DIR/dependencies.log" ]] && grep -q 'speedyG' "$RUN_DIR/dependencies.log" && echo 0 || echo 1)"

# ── RNF-19 / RNF-20: calidad con los comandos documentados ───────────────────
run_in_clone fmt make fmt
check "[RNF-19] make fmt sin diferencias" "$?"

run_in_clone clippy make clippy
check "[RNF-19] make clippy (-D warnings) sin advertencias" "$?"

run_in_clone test make test
check "[RNF-20] make test termina con éxito" "$?"

# ── Sin artefactos sin ignorar tras construir ────────────────────────────────
UNTRACKED="$(git -C "$CLONE" status --porcelain)"
echo "${UNTRACKED:-limpio}" > "$RUN_DIR/git-status-after-build.txt"
check "[RNF-02] Árbol limpio tras construir (artefactos cubiertos por .gitignore)" \
    "$([[ -z "$UNTRACKED" ]] && echo 0 || echo 1)"

# ── Limpieza ─────────────────────────────────────────────────────────────────
if [[ "${TC014_KEEP_CLONE:-0}" == "1" ]]; then
    echo "[INFO] Clon conservado en $CLONE" | tee -a "$LOG"
else
    rm -rf "$CLONE"
fi

finish_run
