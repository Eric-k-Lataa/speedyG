#!/bin/bash
# verif/scripts/TC-020.sh
#
# TC-020 — Terminación inesperada del proceso hijo
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-020.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RF-29: Detección, liberación y diagnóstico tras muerte inesperada del hijo.
#   - RNF-30: Sin procesos huérfanos ni zombis tras fallo.
#
# Resultados en:
#   verif/results/TC-020/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=1
QUEUE_CAP=5

CMD_J1=(sleep 2001)                # Trabajo víctima (Running -> kill -9)
CMD_J2=(echo siguiente-tras-muerte) # Trabajo en cola que debe avanzar

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-020"

HAS_PGREP=0; command -v pgrep &>/dev/null && HAS_PGREP=1
echo "pgrep=$HAS_PGREP" >> "$RUN_DIR/environment.txt"

if [[ $HAS_PGREP -eq 0 ]]; then
    block "pgrep no disponible; identificaciones de subprocesos quedan BLOCKED"
fi

start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$MAX_CURRENT" "queue_cap=$QUEUE_CAP"

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
echo "[FASE 1] Lanzamiento de trabajos J1 (víctima) y J2 (cola)" | tee -a "$LOG"
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
echo "$STATUS_PRE" > "$RUN_DIR/status-pre-kill.txt"

ST_J1_PRE=$(job_state "$(client status "$ID_J1" 2>&1)")
ST_J2_PRE=$(job_state "$(client status "$ID_J2" 2>&1)")

check "J1 (${CMD_J1[*]}) está en estado Running (obtenido: '$ST_J1_PRE')" \
    "$([[ "$ST_J1_PRE" == "Running" ]] && echo 0 || echo 1)"
check "J2 (${CMD_J2[*]}) está en estado Queued (obtenido: '$ST_J2_PRE')" \
    "$([[ "$ST_J2_PRE" == "Queued" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 2: Identificación de PID en el SO
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 2] Identificación de PID en el SO" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

PID_J1=""
if [[ $HAS_PGREP -eq 1 ]]; then
    PID_J1=$(pgrep -f "sleep 2001" | head -1 || true)
fi

{
    echo "daemon_pid=$DAEMON_PID"
    echo "pid_j1=$PID_J1"
} > "$RUN_DIR/pids-pre-kill.txt"

echo "[INFO] PID de J1 identificado: '$PID_J1'" | tee -a "$LOG"

check "Subproceso de trabajo víctima J1 identificado en el SO (PID: '${PID_J1:-ninguno}')" \
    "$([[ -n "$PID_J1" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 3: Inyección de muerte inesperada (kill -9)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 3] Inyección de kill -9 al subproceso víctima J1 (PID: $PID_J1)" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

if [[ -n "$PID_J1" ]]; then
    {
        echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S.%N')"
        echo "target_pid=$PID_J1"
        echo "signal=SIGKILL (9)"
    } > "$RUN_DIR/kill-event.log"

    kill -9 "$PID_J1" 2>/dev/null || true
    pkill -9 -f "sleep 2001" 2>/dev/null || true
    echo "[INFO] Señal SIGKILL enviada a subproceso de J1." | tee -a "$LOG"
else
    echo "[WARN] PID_J1 no disponible; kill omitido." | tee -a "$LOG"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 4: Verificación de detección, liberación y avance de cola (RF-29)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 4] Verificación de detección y estado terminal de J1 y avance de J2 (RF-29)" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

sleep 2

STATUS_J1_POST=$(client status "$ID_J1" 2>&1)
echo "$STATUS_J1_POST" > "$RUN_DIR/status-j1-post-kill.txt"
ST_J1_POST=$(job_state "$STATUS_J1_POST")

check "[RF-29] Trabajo víctima J1 transicionó a estado terminal de fallo tras kill (estado: '$ST_J1_POST')" \
    "$([[ "$ST_J1_POST" == "Failed" || "$ST_J1_POST" == "KillSignal" ]] && echo 0 || echo 1)"

# Diagnóstico de señal: debe indicar código 137 o SIGKILL / señal 9 (no solo -1 genérico)
check "[RF-29] Diagnóstico de J1 refleja la señal o código de terminación (137/SIGKILL/señal 9, no solo -1)" \
    "$(grep -qE '(137|SIGKILL|señal 9|signal 9|KillSignal\(9\))' <<< "$STATUS_J1_POST" && echo 0 || echo 1)"

# Esperar a que J2 sea despachado y concluya en Succeeded
wait_job_state "$ID_J2" "Succeeded" 10
J2_WAIT_RC=$?

STATUS_J2_POST=$(client status "$ID_J2" 2>&1)
echo "$STATUS_J2_POST" > "$RUN_DIR/status-j2-post-kill.txt"
ST_J2_POST=$(job_state "$STATUS_J2_POST")

check "[RF-29] Trabajo J2 avanzó de cola y completó exitosamente (estado: '$ST_J2_POST')" \
    "$([[ "$J2_WAIT_RC" -eq 0 && "$ST_J2_POST" == "Succeeded" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 5: Verificación de ausencia de procesos zombis y huérfanos (RNF-30)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 5] Verificación de procesos zombis (STAT Z) y huérfanos (RNF-30)" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

ZOMBIES=$(ps -eo pid,ppid,stat,comm 2>/dev/null \
    | awk -v dpid="$DAEMON_PID" '$2 == dpid && $3 ~ /^Z/ {print $0}')
echo "${ZOMBIES:-ninguno}" > "$RUN_DIR/zombies-check.txt"

check "[RNF-30] Sin procesos zombi (STAT Z) bajo daemon PID $DAEMON_PID" \
    "$([[ -z "$ZOMBIES" ]] && echo 0 || echo 1)"

ORPHANS=""
if [[ $HAS_PGREP -eq 1 ]]; then
    ORPHANS=$(pgrep -f "sleep 2001" 2>/dev/null | tr '\n' ' ' || true)
fi

check "[RNF-30] Sin procesos huérfanos residuales sleep 2001 en el SO (PIDs: '${ORPHANS:-ninguno}')" \
    "$([[ -z "${ORPHANS// /}" ]] && echo 0 || echo 1)"

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

check "[RF-29] Daemon responde satisfactoriamente a health tras la terminación inesperada" \
    "$(grep -q "OK" <<< "$HEALTH" && echo 0 || echo 1)"

check_no_zombies

finish_run
