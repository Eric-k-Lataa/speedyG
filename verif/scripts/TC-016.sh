#!/bin/bash
# verif/scripts/TC-016.sh
#
# TC-016 — Saturación de cola y rechazo explícito
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-016.sh
#
# Resultados en:
#   verif/results/TC-016/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=3
QUEUE_CAP=3
FIRST_BATCH=$((MAX_CURRENT + QUEUE_CAP))   # 6 aceptados
REJECT_MAX_SECS=3
RECOVERY_MAX_SECS=20
FINAL_MAX_SECS=40

# check <descripción> <código>   (0 = cumple)
check() {
    if [[ "$2" -eq 0 ]]; then
        echo "[PASS] $1" | tee -a "$LOG"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL] $1" | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

job_ids() { grep -oE '^Job #[0-9]+' <<< "$1" | grep -oE '[0-9]+' | sort -n | paste -sd, -; }

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-016"
start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$MAX_CURRENT" "queue_cap=$QUEUE_CAP"

# ── Paso 1: saturar el sistema con 6 trabajos aceptados ──────────────────────
echo "" | tee -a "$LOG"
echo "[1] Enviando $FIRST_BATCH trabajos: sleep 8" | tee -a "$LOG"

: > "$RUN_DIR/submit.txt"
ACCEPTED_IDS=()
for n in $(seq 1 "$FIRST_BATCH"); do
    OUT=$(client sleep 8 2>&1)
    echo "envio $n: $OUT" | tee -a "$LOG" >> "$RUN_DIR/submit.txt"
    ID=$(grep -oE 'Job #[0-9]+ encolado' <<< "$OUT" | grep -oE '[0-9]+' | head -1)
    [[ -n "$ID" ]] && ACCEPTED_IDS+=("$ID")
done
DISTINCT=$(printf '%s\n' "${ACCEPTED_IDS[@]:-}" | sort -u | grep -c .)
check "Los $FIRST_BATCH primeros envíos fueron aceptados (aceptados: ${#ACCEPTED_IDS[@]})" \
    "$([[ "${#ACCEPTED_IDS[@]}" -eq "$FIRST_BATCH" ]] && echo 0 || echo 1)"
check "Los IDs aceptados son distintos (distintos: $DISTINCT)" \
    "$([[ "$DISTINCT" -eq "$FIRST_BATCH" ]] && echo 0 || echo 1)"
LAST_ID="${ACCEPTED_IDS[-1]:-0}"

# ── Paso 2: estado saturado (3 Running + 3 Queued) ───────────────────────────
echo "" | tee -a "$LOG"
echo "[2] Estado saturado antes del rechazo" | tee -a "$LOG"
sleep 1
BEFORE=$(client status 2>&1)
echo "$BEFORE" | tee "$RUN_DIR/status-before.txt" >> "$LOG"
RUN_B=$(grep -cE '^Job #[0-9]+: .*\[Running\]' <<< "$BEFORE")
QUE_B=$(grep -cE '^Job #[0-9]+: .*\[Queued\]'  <<< "$BEFORE")
IDS_B=$(job_ids "$BEFORE")
check "Antes del rechazo hay $MAX_CURRENT Running (obtenidos: $RUN_B)" \
    "$([[ "$RUN_B" -eq "$MAX_CURRENT" ]] && echo 0 || echo 1)"
check "Antes del rechazo hay $QUEUE_CAP Queued (obtenidos: $QUE_B)" \
    "$([[ "$QUE_B" -eq "$QUEUE_CAP" ]] && echo 0 || echo 1)"

# ── Paso 3: séptima solicitud → debe ser rechazada, sin bloquear ─────────────
echo "" | tee -a "$LOG"
echo "[3] Séptima solicitud (debe ser rechazada)" | tee -a "$LOG"
T0=$(date +%s.%N)
REJ=$(timeout 10 "$CLIENT_BIN" --socket "$SOCKET" sleep 8 2>&1)
T1=$(date +%s.%N)
ELAPSED=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", b-a}')
{
    echo "respuesta: $REJ"
    echo "tiempo_respuesta_s: $ELAPSED"
} | tee "$RUN_DIR/rejection.txt" >> "$LOG"

NOT_ACCEPTED=1; grep -q 'encolado correctamente' <<< "$REJ" || NOT_ACCEPTED=0
check "La séptima solicitud NO fue aceptada" "$NOT_ACCEPTED"
FAST=$(awk -v e="$ELAPSED" -v m="$REJECT_MAX_SECS" 'BEGIN{print (e<m)?0:1}')
check "El rechazo respondió en menos de ${REJECT_MAX_SECS}s (${ELAPSED}s)" "$FAST"

# RNF-21: operación, causa y acción sugerida
grep -qiE 'sleep'                        <<< "$REJ"; OP=$?
grep -qiE "llena.*$QUEUE_CAP|$QUEUE_CAP.*llena" <<< "$REJ"; CAUSE=$?
grep -qiE 'espera|reintent|intenta|libere' <<< "$REJ"; ACTION=$?
check "RNF-21: el mensaje indica la operación (sleep)" "$OP"
check "RNF-21: el mensaje indica la causa (cola llena, capacidad $QUEUE_CAP)" "$CAUSE"
check "RNF-21: el mensaje sugiere una acción (esperar/reintentar)" "$ACTION"

# ── Paso 4: los aceptados se conservan y el rechazado no aparece ─────────────
echo "" | tee -a "$LOG"
echo "[4] Estado tras el rechazo" | tee -a "$LOG"
AFTER=$(client status 2>&1)
echo "$AFTER" | tee "$RUN_DIR/status-after.txt" >> "$LOG"
IDS_A=$(job_ids "$AFTER")
N_A=$(grep -cE '^Job #[0-9]+:' <<< "$AFTER")
check "Siguen presentes los $FIRST_BATCH trabajos aceptados, sin un séptimo (en status: $N_A)" \
    "$([[ "$N_A" -eq "$FIRST_BATCH" && "$IDS_A" == "$IDS_B" ]] && echo 0 || echo 1)"

# ── Paso 5: el daemon sigue vivo ─────────────────────────────────────────────
HEALTH=$(client health 2>&1)
echo "health: $HEALTH" | tee -a "$LOG"
assert_contains "El daemon responde health tras el rechazo" "OK: Daemon speedyg funcionando correctamente" "$HEALTH"

# ── Paso 6: recuperación al liberarse espacio ────────────────────────────────
echo "" | tee -a "$LOG"
echo "[5] Reintentando 'echo recuperado' hasta que se libere espacio (máx. ${RECOVERY_MAX_SECS}s)" | tee -a "$LOG"
: > "$RUN_DIR/recovery.txt"
RECOVERED=1
RECOVERY_ID=""
SECONDS=0
while [[ $SECONDS -lt $RECOVERY_MAX_SECS ]]; do
    R=$(client echo recuperado 2>&1)
    echo "t=${SECONDS}s: $R" | tee -a "$LOG" >> "$RUN_DIR/recovery.txt"
    RECOVERY_ID=$(grep -oE 'Job #[0-9]+ encolado' <<< "$R" | grep -oE '[0-9]+' | head -1)
    if [[ -n "$RECOVERY_ID" ]]; then RECOVERED=0; break; fi
    sleep 1
done
check "Al liberarse espacio una nueva solicitud fue aceptada" "$RECOVERED"
EXPECTED_ID=$((LAST_ID + 1))
check "El rechazo no consumió ID: ID esperado $EXPECTED_ID, obtenido '${RECOVERY_ID:-ninguno}'" \
    "$([[ "$RECOVERY_ID" == "$EXPECTED_ID" ]] && echo 0 || echo 1)"

# ── Paso 7: estado final ─────────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[6] Esperando fin de los $((FIRST_BATCH + 1)) trabajos aceptados (máx. ${FINAL_MAX_SECS}s)" | tee -a "$LOG"
TOTAL_OK=$((FIRST_BATCH + 1))
SECONDS=0
while [[ $SECONDS -lt $FINAL_MAX_SECS ]]; do
    FINAL=$(client status 2>&1)
    DONE=$(grep -cE '^Job #[0-9]+: .*\[(Succeeded|Failed|Canceled|Interrupted|ServiceRestarted)\]' <<< "$FINAL")
    [[ "$DONE" -ge "$TOTAL_OK" ]] && break
    sleep 1
done
FINAL=$(client status 2>&1)
echo "$FINAL" | tee "$RUN_DIR/final-status.txt" >> "$LOG"
SUCC=$(grep -cE '^Job #[0-9]+: .*\[Succeeded\] \(exit code: 0\)' <<< "$FINAL")
check "Los $TOTAL_OK trabajos aceptados terminaron en Succeeded con exit code 0 (obtenidos: $SUCC)" \
    "$([[ "$SUCC" -eq "$TOTAL_OK" ]] && echo 0 || echo 1)"

# ── Paso 8: el rechazo quedó registrado en daemon.log (RF-23) ────────────────
CLEAN_LOG=$(sed 's/\x1b\[[0-9;]*m//g' "$RUN_DIR/daemon.log")
grep -iE 'cola está llena' <<< "$CLEAN_LOG" > "$RUN_DIR/rejection-log-lines.txt"
N_REJ_LOG=$(grep -c . "$RUN_DIR/rejection-log-lines.txt")
check "RF-23: daemon.log registra el rechazo por cola llena (entradas: $N_REJ_LOG)" \
    "$([[ "$N_REJ_LOG" -ge 1 ]] && echo 0 || echo 1)"

# ── Procesos residuales (antes de detener el daemon) ─────────────────────────
echo "" | tee -a "$LOG"
echo "[INFO] File descriptors abiertos por daemon: $(count_open_fds)" | tee -a "$LOG"
sleep 1
check_no_zombies

finish_run
