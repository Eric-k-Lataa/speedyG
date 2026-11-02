#!/bin/bash
# verif/scripts/lib/common.sh
#
# Biblioteca compartida para los scripts de verificación de speedyG.
#
# Uso desde un TC:
#   source "$(dirname "$0")/lib/common.sh"
#   setup_run_env "TC-001"          # crea RUN_DIR, SOCKET, DATA_DIR, LOG
#   start_daemon                    # arranca el daemon con su PID real
#   ...
#   stop_daemon                     # detiene el daemon limpiamente
#   finish_run                      # escribe summary y sale con el código correcto

# ── Constantes ────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BIN_DIR="$REPO_ROOT/target/debug"
DAEMON_BIN="$BIN_DIR/speedyG"
CLIENT_BIN="$BIN_DIR/speedyg"

DAEMON_WAIT_SECS=20   # segundos máximos esperando el socket al arrancar
CMD_TIMEOUT_SECS=10   # timeout por defecto para cada comando cliente

# ── Estado global de la corrida ───────────────────────────────────────────────

PASS_COUNT=0
FAIL_COUNT=0
BLOCKED_COUNT=0
DAEMON_PID=""
RUN_DIR=""
SOCKET=""
DATA_DIR=""
LOG=""

# ── setup_run_env <tc-id> ─────────────────────────────────────────────────────
# Crea el directorio de resultados con run-id único, el socket y el data-dir
# temporales, e inicializa el log principal.
#
# Variables exportadas tras la llamada:
#   RUN_DIR   — verif/results/<tc-id>/<run-id>/
#   SOCKET    — /tmp/speedyg-<tc-id>-<run-id>.sock
#   DATA_DIR  — /tmp/speedyg-<tc-id>-<run-id>-data/
#   LOG       — $RUN_DIR/output.log
setup_run_env() {
    local tc_id="$1"
    local run_id
    run_id="$(date '+%Y%m%d-%H%M%S')-$$"

    RUN_DIR="$REPO_ROOT/verif/results/$tc_id/$run_id"
    mkdir -p "$RUN_DIR"

    SOCKET=$(mktemp -u "/tmp/speedyg-${tc_id}-${run_id}-XXXXXX.sock")
    DATA_DIR=$(mktemp -d "/tmp/speedyg-${tc_id}-${run_id}-data-XXXXXX")
    LOG="$RUN_DIR/output.log"

    export SPEEDYG_SOCKET="$SOCKET"
    export SPEEDYG_DB="$DATA_DIR/speedyg.db"
    export SPEEDYG_JSON="$DATA_DIR/scheduler.json"

    # Guardar entorno de la corrida
    {
        echo "tc_id=$tc_id"
        echo "run_id=$run_id"
        echo "date=$(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "os=$(uname -s)"
        echo "kernel=$(uname -r)"
        echo "arch=$(uname -m)"
        echo "hostname=$(hostname)"
        echo "rust=$(rustc --version 2>/dev/null || echo n/a)"
        echo "cargo=$(cargo --version 2>/dev/null || echo n/a)"
        echo "branch=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo n/a)"
        echo "commit=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo n/a)"
        echo "socket=$SOCKET"
        echo "data_dir=$DATA_DIR"
        echo "db=$SPEEDYG_DB"
        echo "json=$SPEEDYG_JSON"
        echo "daemon_bin=$DAEMON_BIN"
        echo "client_bin=$CLIENT_BIN"
    } > "$RUN_DIR/environment.txt"

    _log_header "$tc_id" "$run_id"
}

# ── _log_header ───────────────────────────────────────────────────────────────
_log_header() {
    {
        echo "========================================"
        echo "$1  —  run $2"
        echo "========================================"
        cat "$RUN_DIR/environment.txt"
        echo "========================================"
    } | tee "$LOG"
}

# ── require_binaries ──────────────────────────────────────────────────────────
# Verifica que los binarios compilados existan; falla rápido si no.
# Llama a esto antes de start_daemon.
require_binaries() {
    if [[ ! -x "$DAEMON_BIN" ]]; then
        echo "[ERROR] Daemon no compilado: $DAEMON_BIN" | tee -a "$LOG"
        echo "[ERROR] Ejecuta 'cargo build' desde la raíz del repositorio primero." | tee -a "$LOG"
        exit 2
    fi
    if [[ ! -x "$CLIENT_BIN" ]]; then
        echo "[ERROR] Cliente no compilado: $CLIENT_BIN" | tee -a "$LOG"
        echo "[ERROR] Ejecuta 'cargo build' desde la raíz del repositorio primero." | tee -a "$LOG"
        exit 2
    fi
}

# ── start_daemon [flags extra...] ─────────────────────────────────────────────
# Arranca el daemon con su PID real (no el PID de cargo).
# Los argumentos opcionales se pasan al daemon (p. ej. --max-current 3 --queue-cap 3).
# Espera hasta DAEMON_WAIT_SECS segundos a que el socket aparezca.
start_daemon() {
    require_binaries

    DAEMON_EXTRA_ARGS="$*"
    echo "daemon_args=$DAEMON_EXTRA_ARGS" >> "$RUN_DIR/environment.txt"

    echo "" | tee -a "$LOG"
    echo "[INFO] Iniciando daemon: $DAEMON_BIN $DAEMON_EXTRA_ARGS" | tee -a "$LOG"
    echo "[INFO] Socket: $SOCKET" | tee -a "$LOG"

    "$DAEMON_BIN" \
        --socket  "$SOCKET" \
        --data-dir "$DATA_DIR" \
        "$@" \
        >> "$RUN_DIR/daemon.log" 2>&1 &
    DAEMON_PID=$!

    echo "[INFO] PID del daemon: $DAEMON_PID" | tee -a "$LOG"

    wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "[FAIL] El daemon no creó el socket en ${DAEMON_WAIT_SECS}s." | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        finish_run   # no tiene sentido continuar
    fi
    echo "[PASS] Daemon disponible (PID $DAEMON_PID)." | tee -a "$LOG"
    PASS_COUNT=$((PASS_COUNT + 1))
}

# ── stop_daemon ───────────────────────────────────────────────────────────────
# Detiene el daemon limpiamente y espera a que termine.
stop_daemon() {
    if [[ -n "$DAEMON_PID" ]]; then
        echo "" | tee -a "$LOG"
        echo "[INFO] Deteniendo daemon PID $DAEMON_PID..." | tee -a "$LOG"
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
        DAEMON_PID=""
    fi
}

# ── _cleanup ──────────────────────────────────────────────────────────────────
# Limpia artefactos temporales; se registra con trap EXIT.
_cleanup() {
    stop_daemon
    rm -f  "$SOCKET"   2>/dev/null || true
    rm -rf "$DATA_DIR" 2>/dev/null || true
}
trap _cleanup EXIT

# ── wait_socket <path> <secs> ─────────────────────────────────────────────────
# Espera hasta <secs> segundos a que <path> sea un socket Unix.
# Retorna 0 si aparece, 1 si agota el tiempo.
wait_socket() {
    local path="$1"
    local secs="${2:-$DAEMON_WAIT_SECS}"
    local i=0
    while [[ $i -lt $secs ]]; do
        [[ -S "$path" ]] && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# ── wait_job_state <job-id> <estado> <secs> ───────────────────────────────────
# Sondea 'status <job-id>' hasta que la salida contenga <estado> o se agote el tiempo.
# Retorna 0 si el estado aparece, 1 si agota el tiempo.
wait_job_state() {
    local job_id="$1"
    local state="$2"
    local secs="${3:-$CMD_TIMEOUT_SECS}"
    local i=0
    while [[ $i -lt $secs ]]; do
        local out
        out=$(client status "$job_id" 2>&1)
        if echo "$out" | grep -q "$state"; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# ── client <args...> ──────────────────────────────────────────────────────────
# Ejecuta el cliente CLI contra el socket de la corrida actual.
client() {
    "$CLIENT_BIN" --socket "$SOCKET" "$@"
}

# ── assert_contains <descripción> <cadena> <texto> ───────────────────────────
# Falla si <texto> no contiene <cadena>.
assert_contains() {
    local desc="$1"
    local needle="$2"
    local haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "[PASS] $desc" | tee -a "$LOG"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL] $desc" | tee -a "$LOG"
        echo "       Esperado: '$needle'" | tee -a "$LOG"
        echo "       Obtenido: '$haystack'" | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ── assert_not_contains <descripción> <cadena> <texto> ───────────────────────
assert_not_contains() {
    local desc="$1"
    local needle="$2"
    local haystack="$3"
    if ! echo "$haystack" | grep -q "$needle"; then
        echo "[PASS] $desc" | tee -a "$LOG"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL] $desc" | tee -a "$LOG"
        echo "       No esperado: '$needle'" | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ── assert_exit_zero <descripción> <código> ───────────────────────────────────
assert_exit_zero() {
    local desc="$1"
    local code="$2"
    if [[ "$code" -eq 0 ]]; then
        echo "[PASS] $desc" | tee -a "$LOG"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL] $desc (exit code: $code)" | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ── count_open_fds ────────────────────────────────────────────────────────────
# Imprime el número de file descriptors abiertos por el daemon.
count_open_fds() {
    if [[ -n "$DAEMON_PID" ]] && [[ -d "/proc/$DAEMON_PID/fd" ]]; then
        ls /proc/"$DAEMON_PID"/fd 2>/dev/null | wc -l
    else
        echo "n/a"
    fi
}

# ── check_no_zombies ──────────────────────────────────────────────────────────
# Verifica que el daemon no tenga hijos zombi ni hijos vivos sin trabajo activo.
# Cuenta como FAIL (no solo advertencia). Llamar ANTES de stop_daemon.
check_no_zombies() {
    local zombies
    zombies=$(ps -eo pid,ppid,stat,comm 2>/dev/null \
        | awk -v dpid="$DAEMON_PID" '$2 == dpid && $3 ~ /^Z/ {print $0}')

    if [[ -z "$zombies" ]]; then
        echo "[PASS] Sin procesos zombi bajo daemon PID $DAEMON_PID." | tee -a "$LOG"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL] Procesos zombi detectados:" | tee -a "$LOG"
        echo "$zombies" | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    local orphans
    orphans=$(ps -eo pid,ppid,comm 2>/dev/null \
        | awk -v dpid="$DAEMON_PID" '$2 == dpid {print $0}')

    if [[ -z "$orphans" ]]; then
        echo "[PASS] Sin procesos hijos residuales bajo daemon PID $DAEMON_PID." | tee -a "$LOG"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL] Procesos hijos activos bajo daemon PID $DAEMON_PID:" | tee -a "$LOG"
        echo "$orphans" | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ── daemon_config_value <clave> ───────────────────────────────────────────────
# Lee de daemon.log el valor de <clave> en la línea "Configuración cargada"
# (quita colores ANSI). Imprime el valor o nada si no existe.
daemon_config_value() {
    local key="$1"
    sed 's/\x1b\[[0-9;]*m//g' "$RUN_DIR/daemon.log" 2>/dev/null \
        | grep "Configuración cargada" | tail -1 \
        | grep -oE "${key}=[^ ]+" | head -1 | cut -d= -f2
}

# ── require_daemon_config <clave=valor> ... ───────────────────────────────────
# Si el daemon NO cargó la configuración esperada, el caso es BLOCKED:
# escribe summary con result=BLOCKED y sale con código 3.
# Evita dar PASS/FAIL con una configuración distinta a la que exige el TC.
require_daemon_config() {
    local pair key expected actual
    for pair in "$@"; do
        key="${pair%%=*}"
        expected="${pair#*=}"
        actual="$(daemon_config_value "$key")"
        echo "config_${key}=${actual:-n/a}" >> "$RUN_DIR/environment.txt"
        if [[ "$actual" != "$expected" ]]; then
            echo "[BLOCKED] Configuración efectiva $key='${actual:-n/a}', se esperaba '$expected'." | tee -a "$LOG"
            {
                echo "result=BLOCKED"
                echo "reason=config $key esperado=$expected obtenido=${actual:-n/a}"
                echo "date=$(date '+%Y-%m-%d %H:%M:%S %Z')"
                echo "run_dir=$RUN_DIR"
            } > "$RUN_DIR/summary.txt"
            stop_daemon
            exit 3
        fi
    done
    echo "[PASS] Configuración efectiva del daemon: $*" | tee -a "$LOG"
    PASS_COUNT=$((PASS_COUNT + 1))
}
# ── check <descripción> <código> ─────────────────────────────────────────────
# Registra [PASS] si <código> es 0 y [FAIL] en otro caso.
check() {
    if [[ "$2" -eq 0 ]]; then
        echo "[PASS] $1" | tee -a "$LOG"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL] $1" | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ── block <descripción> ───────────────────────────────────────────────────────
# Registra una comprobación que NO pudo evaluarse porque la funcionalidad que
# necesita aún no existe (no es FAIL del sistema ni error de ambiente).
# Si no hay FAIL, la corrida termina como BLOCKED (exit 3).
block() {
    echo "[BLOCKED] $1" | tee -a "$LOG"
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
}

# ── job_state <texto de status> ───────────────────────────────────────────────
# Imprime el estado (sin código de salida) de la primera línea con [Estado].
# Ejemplo: "Job #3: false [Failed(1)] (exit code: 1)"  ->  Failed
job_state() {
    grep -oE '\[[A-Za-z]+(\([-0-9]+\))?\]' <<< "$1" | head -1 | tr -d '[]' | sed -E 's/\(.*//'
}

# ── to_epoch <valor> ──────────────────────────────────────────────────────────
# Convierte ISO-8601 o epoch (s o ms) a segundos con 3 decimales.
# Imprime vacío si el valor no se puede interpretar.
to_epoch() {
    local v="${1:-}"
    [[ -z "$v" ]] && return 0
    if [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        awk -v x="$v" 'BEGIN{ if (x >= 1e12) x = x / 1000; printf "%.3f", x }'
    else
        date -d "$v" +%s.%N 2>/dev/null | awk '{printf "%.3f", $1}'
    fi
}

# ── ts_field <texto> <regex-de-etiqueta> ──────────────────────────────────────
# Extrae el valor (ISO-8601 o epoch) que sigue a una etiqueta en <texto>.
# Imprime vacío si la etiqueta no aparece con un valor de tiempo.
ts_field() {
    local text="$1" label="$2"
    grep -oiE "(${label})[^0-9]{0,8}([0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.]+(Z|[+-][0-9]{2}:?[0-9]{2})?|[0-9]{9,}(\.[0-9]+)?)" <<< "$text" \
        | head -1 | sed -E "s/^(${label})[^0-9]{0,8}//I"
}

# ── num_le <a> <b> ────────────────────────────────────────────────────────────
# Código 0 si a <= b (numérico). Código 1 si falta un valor o no se cumple.
num_le() {
    [[ -n "${1:-}" && -n "${2:-}" ]] || return 1
    awk -v a="$1" -v b="$2" 'BEGIN{exit !(a <= b)}'
}



# ── finish_run ────────────────────────────────────────────────────────────────
# Escribe el summary, detiene el daemon y sale con 0 (PASS) o 1 (FAIL).
finish_run() {
    local result
    if [[ $FAIL_COUNT -gt 0 ]]; then
        result="FAIL"
    elif [[ $BLOCKED_COUNT -gt 0 ]]; then
        result="BLOCKED"
    else
        result="PASS"
    fi

    {
        echo ""
        echo "========================================"
        echo "RESULTADO: $result"
        echo "PASS: $PASS_COUNT  FAIL: $FAIL_COUNT  BLOCKED: $BLOCKED_COUNT"
        echo "========================================"
    } | tee -a "$LOG"

    # Guardar summary estructurado
    {
        echo "result=$result"
        echo "pass=$PASS_COUNT"
        echo "fail=$FAIL_COUNT"
        echo "blocked=$BLOCKED_COUNT"
        echo "date=$(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "run_dir=$RUN_DIR"
    } > "$RUN_DIR/summary.txt"

    stop_daemon

    case "$result" in
        PASS)    exit 0 ;;
        BLOCKED) exit 3 ;;
        *)       exit 1 ;;
    esac
}
