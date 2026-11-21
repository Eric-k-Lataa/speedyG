#!/bin/bash
# verif/scripts/TC-021.sh
#
# TC-021 — Escalamiento de cancelación
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-021.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RF-30: Escalamiento documentado y verificable (SIGTERM -> SIGKILL).
#   - RNF-30: Sin procesos huérfanos ni subprocesos nietos residuales.
#
# Resultados en:
#   verif/results/TC-021/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=1
QUEUE_CAP=5
GRACE_MS=1000

# Trabajo que ignora SIGTERM y genera un proceso nieto sleep 2002
CMD_J1=(sh -c "trap '' TERM; sleep 2002 & wait")
CMD_J2=(echo siguiente-tras-escalamiento)

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-021"

HAS_PGREP=0; command -v pgrep &>/dev/null && HAS_PGREP=1
echo "pgrep=$HAS_PGREP" >> "$RUN_DIR/environment.txt"

if [[ $HAS_PGREP -eq 0 ]]; then
    block "pgrep no disponible; identificaciones de subprocesos quedan BLOCKED"
fi

start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP" --grace-ms "$GRACE_MS"
require_daemon_config "max_current=$MAX_CURRENT" "grace_ms=$GRACE_MS"

echo "$DAEMON_PID" > "$RUN_DIR/daemon-pid.txt"

submit() {   # submit <nombre> <cmd...> -> imprime el ID
    local name="$1"; shift
    local out id
    out=$(client "$@" 2>&1)
    echo "$name: $* -> $out" | tee -a "$LOG" >> "$RUN_DIR/submit-jobs.txt"
    id=$(grep -oE 'Job #[0-9]+' <<< "$out" | grep -oE '[0-9]+' | head -1)
    echo "$id"
}

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 1: Lanzamiento de trabajos
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 1] Lanzamiento de trabajos J1 (reacio a SIGTERM) y J2 (cola)" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

: > "$RUN_DIR/submit-jobs.txt"
ID_J1=$(submit J1 "${CMD_J1[@]}")
ID_J2=$(submit J2 "${CMD_J2[@]}")

{
    echo "J1=$ID_J1"
    echo "J2=$ID_J2"
} > "$RUN_DIR/jobs-map.txt"

DISTINCT=$(printf '%s\n' "$ID_J1" "$ID_J2" | grep -v '^$' | sort -u | grep -c .)
check "Los 2 trabajos fueron aceptados con IDs válidos y distintos (distintos: $DISTINCT)" \
    "$([[ "$DISTINCT" -eq 2 ]] && echo 0 || echo 1)"

if [[ "$DISTINCT" -ne 2 ]]; then
    echo "[ERROR] No se obtuvieron los IDs requeridos para la prueba." | tee -a "$LOG"
    finish_run
fi

# Esperar estabilización para que J1 pase a Running y J2 a Queued
sleep 2

STATUS_PRE=$(client status 2>&1)
echo "$STATUS_PRE" > "$RUN_DIR/status-pre-cancel.txt"

ST_J1_PRE=$(job_state "$(client status "$ID_J1" 2>&1)")
ST_J2_PRE=$(job_state "$(client status "$ID_J2" 2>&1)")

check "J1 (${CMD_J1[*]}) está en estado Running (obtenido: '$ST_J1_PRE')" \
    "$([[ "$ST_J1_PRE" == "Running" ]] && echo 0 || echo 1)"
check "J2 (${CMD_J2[*]}) está en estado Queued (obtenido: '$ST_J2_PRE')" \
    "$([[ "$ST_J2_PRE" == "Queued" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 2: Identificación del árbol de procesos (hijo y nieto en el SO)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 2] Identificación de procesos hijo y nieto en el SO" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

PID_NIETO=""
if [[ $HAS_PGREP -eq 1 ]]; then
    PID_NIETO=$(pgrep -f "sleep 2002" | head -1 || true)
fi

{
    echo "daemon_pid=$DAEMON_PID"
    echo "pid_nieto_sleep2002=$PID_NIETO"
} > "$RUN_DIR/pids-pre-cancel.txt"

echo "[INFO] Proceso nieto sleep 2002 identificado con PID: '$PID_NIETO'" | tee -a "$LOG"

check "Proceso nieto sleep 2002 identificado en el SO (PID: '${PID_NIETO:-ninguno}')" \
    "$([[ -n "$PID_NIETO" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 3: Solicitud de cancelación y verificación de escalamiento (RF-30)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 3] Solicitud de cancel de J1 y escalamiento (RF-30)" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

CANCEL_OUT=$(client cancel "$ID_J1" 2>&1)
echo "$CANCEL_OUT" > "$RUN_DIR/cancel-response.txt"
echo "[INFO] Respuesta de cancel: '$CANCEL_OUT'" | tee -a "$LOG"

check "Respuesta de cancelación confirma solicitud para Job #$ID_J1" \
    "$(grep -q "$ID_J1" <<< "$CANCEL_OUT" && echo 0 || echo 1)"

# Esperar a que el escalamiento a SIGKILL (tras grace_ms=1000) complete y transicione a Canceled
wait_job_state "$ID_J1" "Canceled" 6
J1_CANCEL_RC=$?

STATUS_J1_POST=$(client status "$ID_J1" 2>&1)
echo "$STATUS_J1_POST" > "$RUN_DIR/status-j1-post-cancel.txt"
ST_J1_POST=$(job_state "$STATUS_J1_POST")

check "[RF-30] Trabajo J1 transicionó a estado Canceled tras escalamiento (estado: '$ST_J1_POST')" \
    "$([[ "$J1_CANCEL_RC" -eq 0 && "$ST_J1_POST" == "Canceled" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 4: Verificación de despacho y avance de cola de J2 (RF-30)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 4] Verificación de avance y finalización de J2" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

wait_job_state "$ID_J2" "Succeeded" 10
J2_WAIT_RC=$?

STATUS_J2_POST=$(client status "$ID_J2" 2>&1)
echo "$STATUS_J2_POST" > "$RUN_DIR/status-j2-post-cancel.txt"
ST_J2_POST=$(job_state "$STATUS_J2_POST")

check "[RF-30] Trabajo J2 avanzó de cola y culminó exitosamente (estado: '$ST_J2_POST')" \
    "$([[ "$J2_WAIT_RC" -eq 0 && "$ST_J2_POST" == "Succeeded" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 5: Verificación de eliminación completa de procesos huérfanos (RNF-30)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 5] Verificación de procesos nietos huérfanos y zombis (RNF-30)" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

ORPHANS=""
if [[ $HAS_PGREP -eq 1 ]]; then
    ORPHANS=$(pgrep -f "sleep 2002" 2>/dev/null | tr '\n' ' ' || true)
fi
echo "${ORPHANS:-ninguno}" > "$RUN_DIR/orphans-check.txt"

check "[RNF-30] Sin procesos nietos residuales sleep 2002 en el SO (PIDs: '${ORPHANS:-ninguno}')" \
    "$([[ -z "${ORPHANS// /}" ]] && echo 0 || echo 1)"

ZOMBIES=$(ps -eo pid,ppid,stat,comm 2>/dev/null \
    | awk -v dpid="$DAEMON_PID" '$2 == dpid && $3 ~ /^Z/ {print $0}')
echo "${ZOMBIES:-ninguno}" > "$RUN_DIR/zombies-check.txt"

check "[RNF-30] Sin procesos zombi (STAT Z) bajo daemon PID $DAEMON_PID" \
    "$([[ -z "$ZOMBIES" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 6: Verificación de salud y cierre
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 6] Verificación de salud del daemon y cierre" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

HEALTH=$(client health 2>&1)
echo "$HEALTH" > "$RUN_DIR/health-check.txt"
echo "[INFO] Respuesta de health: '$HEALTH'" | tee -a "$LOG"

check "[RF-30] Daemon responde satisfactoriamente a health tras escalamiento" \
    "$(grep -q "OK" <<< "$HEALTH" && echo 0 || echo 1)"

check_no_zombies

finish_run
