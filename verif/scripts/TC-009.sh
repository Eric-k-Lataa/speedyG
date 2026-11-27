#!/bin/bash
# verif/scripts/TC-009.sh
#
# TC-009 — Cierre controlado
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-009.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RF-15:  Inicio y cierre controlados, sin aceptar trabajos al cerrar.
#   - RNF-25: El servicio deberá liberar sockets y procesos hijos al cerrar.
#   - RNF-30: Después de un cierre o falla, el servicio no deberá dejar
#             procesos huérfanos bajo su responsabilidad.
#
# Resultados en:
#   verif/results/TC-009/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

SIGTERM_WAIT_SECS=10   # segundos máximos esperando a que el daemon muera
SOCKET_WAIT_SECS=5     # segundos máximos esperando a que el socket desaparezca
POST_SUBMIT_TIMEOUT=2  # segundos de timeout para el envío post-SIGTERM

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-009"

: > "$RUN_DIR/pids-pre-close.txt"
: > "$RUN_DIR/orphans-check.txt"
: > "$RUN_DIR/socket-check.txt"

# Verificar utilidades opcionales requeridas
HAS_PGREP=0; command -v pgrep &>/dev/null && HAS_PGREP=1
HAS_SS=0;    command -v ss    &>/dev/null && HAS_SS=1
HAS_LSOF=0;  command -v lsof  &>/dev/null && HAS_LSOF=1
{
    echo "pgrep=$HAS_PGREP"
    echo "ss=$HAS_SS"
    echo "lsof=$HAS_LSOF"
} >> "$RUN_DIR/environment.txt"

if [[ $HAS_PGREP -eq 0 ]]; then
    block "pgrep no disponible; las comprobaciones de procesos huérfanos quedan BLOCKED"
fi

# ── Iniciar daemon ────────────────────────────────────────────────────────────
start_daemon --max-current 2 --queue-cap 10
require_daemon_config "max_current=2" "queue_cap=10"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 1 — Preparar trabajos activos y en cola
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 1] Preparar trabajos activos y en cola" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

: > "$RUN_DIR/submit-initial.txt"

# L1 — sleep 2001 → Running
OUT_L1=$(client sleep 2001 2>&1)
echo "L1: sleep 2001 -> $OUT_L1" >> "$RUN_DIR/submit-initial.txt"
ID_L1=$(echo "$OUT_L1" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
check "[FASE 1] L1 (sleep 2001) aceptado (ID #$ID_L1)" \
    "$([[ -n "$ID_L1" ]] && echo 0 || echo 1)"

# L2 — sleep 2002 → Running
OUT_L2=$(client sleep 2002 2>&1)
echo "L2: sleep 2002 -> $OUT_L2" >> "$RUN_DIR/submit-initial.txt"
ID_L2=$(echo "$OUT_L2" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
check "[FASE 1] L2 (sleep 2002) aceptado (ID #$ID_L2)" \
    "$([[ -n "$ID_L2" ]] && echo 0 || echo 1)"

# Esperar a que L1 y L2 estén en Running (ocupa las 2 ranuras)
wait_job_state "$ID_L1" "Running" 10
wait_job_state "$ID_L2" "Running" 10

ST_L1=$(job_state "$(client status "$ID_L1" 2>&1)")
ST_L2=$(job_state "$(client status "$ID_L2" 2>&1)")
check "[FASE 1] L1 está en Running (estado: $ST_L1)" \
    "$([[ "$ST_L1" == "Running" ]] && echo 0 || echo 1)"
check "[FASE 1] L2 está en Running (estado: $ST_L2)" \
    "$([[ "$ST_L2" == "Running" ]] && echo 0 || echo 1)"

# L3 — echo en-cola → debe quedar Queued (ranuras llenas)
OUT_L3=$(client echo en-cola 2>&1)
echo "L3: echo en-cola -> $OUT_L3" >> "$RUN_DIR/submit-initial.txt"
ID_L3=$(echo "$OUT_L3" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
check "[FASE 1] L3 (echo en-cola) aceptado (ID #$ID_L3)" \
    "$([[ -n "$ID_L3" ]] && echo 0 || echo 1)"

ST_L3=$(job_state "$(client status "$ID_L3" 2>&1)")
check "[FASE 1] L3 está en Queued (estado: $ST_L3)" \
    "$([[ "$ST_L3" == "Queued" ]] && echo 0 || echo 1)"

# Registrar PIDs del daemon y procesos hijos en el SO (evidencia E-002)
{
    echo "daemon_pid=$DAEMON_PID"
    echo "pids_sleep2001=$(pgrep -f 'sleep 2001' 2>/dev/null | tr '\n' ' ' || echo n/a)"
    echo "pids_sleep2002=$(pgrep -f 'sleep 2002' 2>/dev/null | tr '\n' ' ' || echo n/a)"
} > "$RUN_DIR/pids-pre-close.txt"

PROCS_L1=$(pgrep -f 'sleep 2001' 2>/dev/null | grep -c . || true)
PROCS_L2=$(pgrep -f 'sleep 2002' 2>/dev/null | grep -c . || true)
check "[FASE 1] Proceso sleep 2001 existe en el SO (encontrados: $PROCS_L1)" \
    "$([[ $PROCS_L1 -ge 1 ]] && echo 0 || echo 1)"
check "[FASE 1] Proceso sleep 2002 existe en el SO (encontrados: $PROCS_L2)" \
    "$([[ $PROCS_L2 -ge 1 ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 2 — Cierre controlado con SIGTERM
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 2] Cierre controlado con SIGTERM" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

SIGTERM_TS=$(date +%s.%N)
echo "[INFO] Enviando SIGTERM -> PID $DAEMON_PID (ts=$SIGTERM_TS)" | tee -a "$LOG"
kill "$DAEMON_PID" 2>/dev/null || true
echo "sigterm_ts=$SIGTERM_TS daemon_pid=$DAEMON_PID" >> "$RUN_DIR/pids-pre-close.txt"

# Intentar enviar un trabajo mientras el daemon se cierra (evidencia E-003)
# Se usa un subshell con timeout; cualquier respuesta de aceptación es FAIL.
POST_OUT=$(timeout "$POST_SUBMIT_TIMEOUT" "$CLIENT_BIN" --socket "$SOCKET" \
    echo post-sigterm 2>&1 || true)
echo "$POST_OUT" > "$RUN_DIR/post-sigterm-submit.txt"
check "[FASE 2] El intento de envío post-SIGTERM NO recibe confirmación de encolado (respuesta: '$(echo "$POST_OUT" | head -1)')" \
    "$(echo "$POST_OUT" | grep -q 'encolado correctamente' && echo 1 || echo 0)"

# Esperar a que el daemon muera
DAEMON_DEAD=0
for i in $(seq 1 $SIGTERM_WAIT_SECS); do
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
        DAEMON_DEAD=1
        break
    fi
    sleep 1
done
SIGTERM_ELAPSED=$i
echo "sigterm_elapsed=${SIGTERM_ELAPSED}s daemon_dead=$DAEMON_DEAD" \
    >> "$RUN_DIR/pids-pre-close.txt"
check "[FASE 2] Daemon termina en máximo ${SIGTERM_WAIT_SECS}s tras SIGTERM (tardó: ${SIGTERM_ELAPSED}s)" \
    "$([[ $DAEMON_DEAD -eq 1 ]] && echo 0 || echo 1)"

# Marcar DAEMON_PID vacío para que finish_run no intente matar un PID muerto
DAEMON_PID=""

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 3 — Verificar liberación de recursos
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 3] Verificar liberación de recursos" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

# ── Verificar que el socket fue liberado (RNF-25, evidencia E-004) ────────────
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
    echo "socket_exists_after=$([[ -S "$SOCKET" ]] && echo yes || echo no)"
    echo "socket_gone=$SOCKET_GONE"
} > "$RUN_DIR/socket-check.txt"
check "[FASE 3] Socket Unix liberado en máximo ${SOCKET_WAIT_SECS}s tras el cierre (liberado: $SOCKET_GONE)" \
    "$([[ $SOCKET_GONE -eq 1 ]] && echo 0 || echo 1)"

# Comprobar con ss/lsof que ningún FD apunta al socket
if [[ $HAS_SS -eq 1 ]]; then
    SS_RESULT=$(ss -xp 2>/dev/null | grep "$SOCKET" || true)
    echo "ss_result=${SS_RESULT:-ninguno}" >> "$RUN_DIR/socket-check.txt"
    check "[FASE 3] ss no muestra el socket como activo" \
        "$([[ -z "$SS_RESULT" ]] && echo 0 || echo 1)"
elif [[ $HAS_LSOF -eq 1 ]]; then
    LSOF_RESULT=$(lsof "$SOCKET" 2>/dev/null || true)
    echo "lsof_result=${LSOF_RESULT:-ninguno}" >> "$RUN_DIR/socket-check.txt"
    check "[FASE 3] lsof no muestra el socket como abierto" \
        "$([[ -z "$LSOF_RESULT" ]] && echo 0 || echo 1)"
else
    block "[FASE 3] ss y lsof no disponibles; verificación de FD del socket BLOCKED"
fi

# ── Verificar ausencia de procesos huérfanos (RNF-30, evidencia E-005) ────────
ORPHANS_L1=$(pgrep -f 'sleep 2001' 2>/dev/null | tr '\n' ' ' || true)
ORPHANS_L2=$(pgrep -f 'sleep 2002' 2>/dev/null | tr '\n' ' ' || true)
{
    echo "orphans_sleep2001=${ORPHANS_L1:-ninguno}"
    echo "orphans_sleep2002=${ORPHANS_L2:-ninguno}"
} > "$RUN_DIR/orphans-check.txt"

check "[FASE 3] Sin procesos huérfanos de sleep 2001 tras el cierre (PIDs: '${ORPHANS_L1:-ninguno}')" \
    "$([[ -z "${ORPHANS_L1// /}" ]] && echo 0 || echo 1)"
check "[FASE 3] Sin procesos huérfanos de sleep 2002 tras el cierre (PIDs: '${ORPHANS_L2// /}')" \
    "$([[ -z "${ORPHANS_L2// /}" ]] && echo 0 || echo 1)"

# Verificar ausencia de zombis (ps busca cualquier proceso Z sin PPID específico
# porque el daemon ya murió)
ZOMBIES=$(ps -eo pid,stat,comm 2>/dev/null | awk '$2 ~ /^Z/ {print $0}' || true)
{
    echo "zombies=${ZOMBIES:-ninguno}"
} >> "$RUN_DIR/orphans-check.txt"
check "[FASE 3] Sin procesos zombis en el sistema tras el cierre (encontrados: '${ZOMBIES:-ninguno}')" \
    "$([[ -z "$ZOMBIES" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 4 — Verificar estado final de los trabajos
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 4] Verificar estado final de los trabajos" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

# Reiniciar el daemon sobre el mismo DATA_DIR para consultar status
"$DAEMON_BIN" \
    --socket   "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current 2 --queue-cap 10 \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!
wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
RC_RESTART=$?
check "[FASE 4] Daemon reinicia para consulta de estado final" \
    "$([[ $RC_RESTART -eq 0 ]] && echo 0 || echo 1)"

ST_L1_FINAL=$(job_state "$(client status "$ID_L1" 2>&1)")
ST_L2_FINAL=$(job_state "$(client status "$ID_L2" 2>&1)")
ST_L3_FINAL=$(job_state "$(client status "$ID_L3" 2>&1)")

{
    client status "$ID_L1" 2>&1
    client status "$ID_L2" 2>&1
    client status "$ID_L3" 2>&1
} > "$RUN_DIR/status-after-close.txt"

# L1 y L2 estaban Running al momento del SIGTERM: deben quedar en un estado
# terminal coherente (Interrupted, Canceled o Succeeded según la implementación;
# lo que no puede ocurrir es que sigan Running).
check "[FASE 4] L1 no permanece Running tras cierre (estado: $ST_L1_FINAL)" \
    "$([[ "$ST_L1_FINAL" != "Running" ]] && echo 0 || echo 1)"
check "[FASE 4] L2 no permanece Running tras cierre (estado: $ST_L2_FINAL)" \
    "$([[ "$ST_L2_FINAL" != "Running" ]] && echo 0 || echo 1)"

# L3 estaba Queued: no debe haber pasado a Running durante el cierre.
check "[FASE 4] L3 no pasó a Running durante el cierre (estado final: $ST_L3_FINAL)" \
    "$([[ "$ST_L3_FINAL" != "Running" ]] && echo 0 || echo 1)"

echo "l1_final=$ST_L1_FINAL l2_final=$ST_L2_FINAL l3_final=$ST_L3_FINAL" \
    >> "$RUN_DIR/status-after-close.txt"

# ── Salud final ───────────────────────────────────────────────────────────────
HEALTH=$(client health 2>&1)
check "[CIERRE] Daemon responde health tras reinicio de verificación (obtenido: '$HEALTH')" \
    "$(health_is_ok "$HEALTH" && echo 0 || echo 1)"

finish_run
