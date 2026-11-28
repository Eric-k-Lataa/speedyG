#!/bin/bash
# verif/scripts/TC-024.sh
#
# TC-024 — Liberación de recursos bajo carga
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-024.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RNF-33: Las pruebas de estrés deberán demostrar liberación de memoria,
#             procesos, archivos y sockets al concluir.
#
# Resultados en:
#   verif/results/TC-024/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

BURST_SIZE=100         # trabajos echo por ráfaga (Escenario A)
CANCEL_JOBS=20         # trabajos sleep para cancelar (Escenario B)
MAX_WAIT_DRAIN=30      # segundos máximos para vaciado de cola
FD_TOLERANCE=10        # variación máxima permitida de FDs
SIGTERM_WAIT_SECS=10   # segundos máximos esperando a que el daemon muera
SOCKET_WAIT_SECS=10    # segundos máximos esperando a que el socket desaparezca

# ── Helper: medir FDs del daemon ─────────────────────────────────────────────
# Imprime el recuento de FDs o "n/a" si /proc no está disponible.
measure_fds() {
    if [[ -n "$DAEMON_PID" ]] && [[ -d "/proc/$DAEMON_PID/fd" ]]; then
        ls "/proc/$DAEMON_PID/fd" 2>/dev/null | wc -l
    else
        echo "n/a"
    fi
}

# Helper: espera a que no quede Queued ni Running.
wait_no_active() {
    local secs="$1"
    local i=0
    while [[ $i -lt $secs ]]; do
        local out
        out=$(client status 2>&1)
        if ! echo "$out" | grep -qE '\[(Queued|Running)\]'; then
            return 0
        fi
        sleep 1
        i=$((i+1))
    done
    return 1
}

# Helper: comprueba que la variación de FDs respecto a la base es ≤ FD_TOLERANCE.
# Uso: check_fds_delta <label> <baseline_fds> <current_fds>
check_fds_delta() {
    local label="$1" base="$2" current="$3"
    if [[ "$base" == "n/a" || "$current" == "n/a" ]]; then
        block "[$label] /proc no disponible; verificación de FDs BLOCKED"
        return
    fi
    local delta
    delta=$(( current - base ))
    # Valor absoluto
    local abs_delta=$(( delta < 0 ? -delta : delta ))
    check "[$label] Variación de FDs ≤ $FD_TOLERANCE respecto a línea base (base=$base actual=$current delta=$delta)" \
        "$([[ $abs_delta -le $FD_TOLERANCE ]] && echo 0 || echo 1)"
}

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-024"

: > "$RUN_DIR/health-checks.txt"
: > "$RUN_DIR/orphans-check.txt"
: > "$RUN_DIR/socket-check.txt"

HAS_PGREP=0; command -v pgrep &>/dev/null && HAS_PGREP=1
HAS_PROC=0;  [[ -d /proc ]] && HAS_PROC=1
{
    echo "pgrep=$HAS_PGREP"
    echo "proc_fs=$HAS_PROC"
} >> "$RUN_DIR/environment.txt"

if [[ $HAS_PGREP -eq 0 ]]; then
    block "pgrep no disponible; verificaciones de procesos residuales quedan BLOCKED"
fi
if [[ $HAS_PROC -eq 0 ]]; then
    block "/proc no disponible; mediciones de FDs quedan BLOCKED"
fi

# ── Iniciar daemon ────────────────────────────────────────────────────────────
start_daemon --max-current 4 --queue-cap 120
require_daemon_config "max_current=4" "queue_cap=120"

# ═══════════════════════════════════════════════════════════════════════════════
# ESCENARIO A — Carga de trabajos rápidos (2 ráfagas de 100 echo)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[ESCENARIO A] Carga de trabajos rápidos" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

# ── Línea base de FDs ─────────────────────────────────────────────────────────
FDS_BASELINE=$(measure_fds)
echo "fds_baseline=$FDS_BASELINE" > "$RUN_DIR/fds-baseline.txt"
echo "[INFO] FDs en línea base: $FDS_BASELINE" | tee -a "$LOG"

# ── Ráfaga 1: 100 × echo carga-A-<n> en paralelo ─────────────────────────────
echo "" | tee -a "$LOG"
echo "[A] Ráfaga 1: $BURST_SIZE envíos echo carga-A en paralelo" | tee -a "$LOG"
declare -a BURST1_PIDS=()
for n in $(seq 1 $BURST_SIZE); do
    (client echo "carga-A-${n}" >/dev/null 2>&1) &
    BURST1_PIDS+=("$!")
done
for bp in "${BURST1_PIDS[@]}"; do wait "$bp" 2>/dev/null || true; done

wait_no_active $MAX_WAIT_DRAIN
DRAIN1_RC=$?
check "[A] Ráfaga 1 completamente vaciada en máximo ${MAX_WAIT_DRAIN}s" \
    "$([[ $DRAIN1_RC -eq 0 ]] && echo 0 || echo 1)"

check_no_zombies

H1=$(client health 2>&1)
echo "post-rafaga1: $H1" >> "$RUN_DIR/health-checks.txt"
check "[A] Daemon responde health tras ráfaga 1" \
    "$(health_is_ok "$H1" && echo 0 || echo 1)"

# ── Pausa de reposo entre ráfagas y medición de FDs ──────────────────────────
sleep 2
FDS_MID=$(measure_fds)
echo "fds_mid=$FDS_MID" > "$RUN_DIR/fds-mid.txt"
echo "[INFO] FDs en reposo entre ráfagas: $FDS_MID" | tee -a "$LOG"
check_fds_delta "A reposo-entre-rafagas" "$FDS_BASELINE" "$FDS_MID"

unset BURST1_PIDS

# ── Ráfaga 2: 100 × echo carga-B-<n> en paralelo ─────────────────────────────
echo "" | tee -a "$LOG"
echo "[A] Ráfaga 2: $BURST_SIZE envíos echo carga-B en paralelo" | tee -a "$LOG"
declare -a BURST2_PIDS=()
for n in $(seq 1 $BURST_SIZE); do
    (client echo "carga-B-${n}" >/dev/null 2>&1) &
    BURST2_PIDS+=("$!")
done
for bp in "${BURST2_PIDS[@]}"; do wait "$bp" 2>/dev/null || true; done

wait_no_active $MAX_WAIT_DRAIN
DRAIN2_RC=$?
check "[A] Ráfaga 2 completamente vaciada en máximo ${MAX_WAIT_DRAIN}s" \
    "$([[ $DRAIN2_RC -eq 0 ]] && echo 0 || echo 1)"

check_no_zombies

H2=$(client health 2>&1)
echo "post-rafaga2: $H2" >> "$RUN_DIR/health-checks.txt"
check "[A] Daemon responde health tras ráfaga 2" \
    "$(health_is_ok "$H2" && echo 0 || echo 1)"

sleep 2
FDS_POST_LOAD=$(measure_fds)
echo "fds_post_load=$FDS_POST_LOAD" > "$RUN_DIR/fds-post-load.txt"
echo "[INFO] FDs tras segunda ráfaga: $FDS_POST_LOAD" | tee -a "$LOG"
check_fds_delta "A post-carga" "$FDS_BASELINE" "$FDS_POST_LOAD"

unset BURST2_PIDS

# ═══════════════════════════════════════════════════════════════════════════════
# ESCENARIO B — Cancelación bajo presión
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[ESCENARIO B] Cancelación bajo presión" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

# Enviar CANCEL_JOBS × sleep 3001 en paralelo
declare -a SLEEP_IDS=()
declare -a SUBMIT_PIDS=()
declare -a SUBMIT_TMPS=()

for i in $(seq 1 $CANCEL_JOBS); do
    TMP=$(mktemp)
    SUBMIT_TMPS+=("$TMP")
    (client sleep 3001 2>&1 > "$TMP") &
    SUBMIT_PIDS+=("$!")
done
for sp in "${SUBMIT_PIDS[@]}"; do wait "$sp" 2>/dev/null || true; done

for TMP in "${SUBMIT_TMPS[@]}"; do
    OUT=$(cat "$TMP" 2>/dev/null || true)
    ID=$(echo "$OUT" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
    [[ -n "$ID" ]] && SLEEP_IDS+=("$ID")
    rm -f "$TMP"
done

echo "[INFO] Trabajos sleep 3001 enviados: ${#SLEEP_IDS[@]}" | tee -a "$LOG"
check "[B] Al menos 1 trabajo sleep 3001 aceptado (aceptados: ${#SLEEP_IDS[@]})" \
    "$([[ ${#SLEEP_IDS[@]} -gt 0 ]] && echo 0 || echo 1)"

# Esperar a que al menos uno esté Running
sleep 2

# Cancelar todos en paralelo
declare -a CANCEL_PIDS=()
for ID in "${SLEEP_IDS[@]}"; do
    (client cancel "$ID" >/dev/null 2>&1) &
    CANCEL_PIDS+=("$!")
done
for cp in "${CANCEL_PIDS[@]}"; do wait "$cp" 2>/dev/null || true; done

# Esperar hasta 10 s a que todos queden Canceled
CANCEL_OK=0
for i in $(seq 1 10); do
    ALL_CANCELED=1
    for ID in "${SLEEP_IDS[@]}"; do
        ST=$(job_state "$(client status "$ID" 2>&1)")
        if [[ "$ST" != "Canceled" && "$ST" != "Interrupted" && "$ST" != "Succeeded" && "$ST" != "Failed" ]]; then
            ALL_CANCELED=0
            break
        fi
    done
    if [[ $ALL_CANCELED -eq 1 ]]; then
        CANCEL_OK=1
        break
    fi
    sleep 1
done
check "[B] Todos los trabajos sleep 3001 alcanzaron estado terminal tras cancelar (ok: $CANCEL_OK)" \
    "$([[ $CANCEL_OK -eq 1 ]] && echo 0 || echo 1)"

# Verificar ausencia de procesos sleep 3001 en el SO
if [[ $HAS_PGREP -eq 1 ]]; then
    ORPHANS=$(pgrep -f 'sleep 3001' 2>/dev/null | tr '\n' ' ' || true)
    echo "orphans_sleep3001=${ORPHANS:-ninguno}" > "$RUN_DIR/orphans-check.txt"
    check "[B] Sin procesos residuales sleep 3001 en el SO (PIDs: '${ORPHANS:-ninguno}')" \
        "$([[ -z "${ORPHANS// /}" ]] && echo 0 || echo 1)"
else
    block "[B] pgrep no disponible; verificación de procesos residuales BLOCKED"
    echo "orphans_sleep3001=n/a" > "$RUN_DIR/orphans-check.txt"
fi

check_no_zombies

H3=$(client health 2>&1)
echo "post-cancel: $H3" >> "$RUN_DIR/health-checks.txt"
check "[B] Daemon responde health tras cancelaciones" \
    "$(health_is_ok "$H3" && echo 0 || echo 1)"

sleep 2
FDS_POST_CANCEL=$(measure_fds)
echo "fds_post_cancel=$FDS_POST_CANCEL" > "$RUN_DIR/fds-post-cancel.txt"
echo "[INFO] FDs tras cancelaciones: $FDS_POST_CANCEL" | tee -a "$LOG"
check_fds_delta "B post-cancelacion" "$FDS_BASELINE" "$FDS_POST_CANCEL"

unset SLEEP_IDS SUBMIT_PIDS SUBMIT_TMPS CANCEL_PIDS

# ═══════════════════════════════════════════════════════════════════════════════
# ESCENARIO C — Cierre tras carga máxima
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[ESCENARIO C] Cierre tras carga máxima" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

SIGTERM_PID="$DAEMON_PID"
echo "[INFO] Enviando SIGTERM -> PID $SIGTERM_PID" | tee -a "$LOG"
kill "$SIGTERM_PID" 2>/dev/null || true

# Esperar a que el daemon muera
DAEMON_DEAD=0
for i in $(seq 1 $SIGTERM_WAIT_SECS); do
    if ! kill -0 "$SIGTERM_PID" 2>/dev/null; then
        DAEMON_DEAD=1
        break
    fi
    sleep 1
done
DAEMON_PID=""   # evitar que finish_run intente matar un PID muerto
check "[C] Daemon termina en máximo ${SIGTERM_WAIT_SECS}s tras SIGTERM (dead: $DAEMON_DEAD)" \
    "$([[ $DAEMON_DEAD -eq 1 ]] && echo 0 || echo 1)"

# Verificar que el socket fue liberado
SOCKET_GONE=0
for i in $(seq 1 $SOCKET_WAIT_SECS); do
    if [[ ! -S "$SOCKET" ]]; then
        SOCKET_GONE=1
        break
    fi
    sleep 1
done
{
    echo "socket_path=$SOCKET"
    echo "socket_gone=$SOCKET_GONE"
} > "$RUN_DIR/socket-check.txt"
check "[C] Socket Unix liberado en máximo ${SOCKET_WAIT_SECS}s tras cierre (liberado: $SOCKET_GONE)" \
    "$([[ $SOCKET_GONE -eq 1 ]] && echo 0 || echo 1)"

# Verificar ausencia de procesos sleep 3001 residuales tras el cierre
if [[ $HAS_PGREP -eq 1 ]]; then
    ORPHANS_C=$(pgrep -f 'sleep 3001' 2>/dev/null | tr '\n' ' ' || true)
    echo "orphans_after_close=${ORPHANS_C:-ninguno}" >> "$RUN_DIR/orphans-check.txt"
    check "[C] Sin procesos huérfanos sleep 3001 tras el cierre (PIDs: '${ORPHANS_C:-ninguno}')" \
        "$([[ -z "${ORPHANS_C// /}" ]] && echo 0 || echo 1)"
fi

finish_run
