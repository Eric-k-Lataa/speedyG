#!/bin/bash
# verif/scripts/TC-022.sh
#
# TC-022 — Interrupción durante persistencia
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-022.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RNF-28: Actualizaciones persistentes atómicas o recuperables.
#   - RNF-31: Recuperación que distingue pendientes, terminados e interrumpidos.
#
# Resultados en:
#   verif/results/TC-022/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ── Parámetros globales ───────────────────────────────────────────────────────
MAX_WAIT_RECOVERY=30   # segundos máximos para que pendientes finalicen
MAX_WAIT_STATUS=3      # segundos máximos para respuesta de status tras reiniciar
ITERATIONS=10          # iteraciones del escenario A
JOBS_PER_ITER=20       # trabajos por iteración del escenario A

# ── Helpers locales ───────────────────────────────────────────────────────────

# kill_daemon_sigkill — envía SIGKILL al daemon actual y espera a que muera.
kill_daemon_sigkill() {
    if [[ -n "$DAEMON_PID" ]]; then
        echo "[INFO] SIGKILL -> PID $DAEMON_PID" | tee -a "$LOG"
        kill -9 "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
        DAEMON_PID=""
    fi
}

# restart_daemon [args...] — reinicia el daemon con los mismos socket/data-dir.
# Mide y devuelve (en RESTART_SECS) el tiempo hasta que el socket responde.
RESTART_SECS=""
restart_daemon() {
    local t0 t1
    t0=$(date +%s%N)
    echo "[INFO] Reiniciando daemon: $DAEMON_BIN $*" | tee -a "$LOG"
    "$DAEMON_BIN" \
        --socket   "$SOCKET" \
        --data-dir "$DATA_DIR" \
        "$@" \
        >> "$RUN_DIR/daemon.log" 2>&1 &
    DAEMON_PID=$!
    echo "[INFO] Nuevo PID del daemon: $DAEMON_PID" | tee -a "$LOG"

    wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
    local rc=$?
    t1=$(date +%s%N)
    RESTART_SECS=$(awk "BEGIN{printf \"%.3f\", ($t1-$t0)/1e9}")
    return $rc
}

# wait_no_active <secs> — espera a que no quede ningún trabajo Queued ni Running.
# Retorna 0 si lo consigue dentro del tiempo, 1 si agota.
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

# kill_orphans_by_marker <marker> — elimina procesos cuyo argumento coincide.
kill_orphans_by_marker() {
    local marker="$1"
    local pids
    pids=$(pgrep -f "$marker" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "[INFO] Eliminando procesos huérfanos ($marker): $pids" | tee -a "$LOG"
        # shellcheck disable=SC2086
        kill -9 $pids 2>/dev/null || true
        echo "marker=$marker pids=$pids" >> "$RUN_DIR/pids.txt"
    fi
}

# submit_accepted <file> <cmd...> — envía un trabajo y registra la respuesta.
# Imprime el ID si fue aceptado (contiene "encolado correctamente"), vacío si no.
submit_accepted() {
    local outfile="$1"; shift
    local out
    out=$(client "$@" 2>&1)
    echo "$out" >> "$outfile"
    if echo "$out" | grep -q "encolado correctamente"; then
        echo "$out" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1
    fi
}

# integrity_check_db <label> — comprueba PRAGMA integrity_check en speedyg.db.
integrity_check_db() {
    local label="$1"
    if ! command -v sqlite3 &>/dev/null; then
        block "[$label] sqlite3 no disponible; no se puede comprobar integridad de la base"
        return
    fi
    if [[ ! -f "$SPEEDYG_DB" ]]; then
        echo "[$label] speedyg.db no existe (aún no se ha creado)." >> "$RUN_DIR/integrity.txt"
        return
    fi
    local result
    result=$(sqlite3 "$SPEEDYG_DB" "PRAGMA integrity_check;" 2>&1)
    echo "[$label] integrity_check: $result" >> "$RUN_DIR/integrity.txt"
    check "[$label] speedyg.db pasa PRAGMA integrity_check (resultado: $result)" \
        "$([[ "$result" == "ok" ]] && echo 0 || echo 1)"
}

# integrity_check_json <label> — valida que scheduler.json sea JSON válido.
integrity_check_json() {
    local label="$1"
    if [[ ! -f "$SPEEDYG_JSON" ]]; then
        echo "[$label] scheduler.json no existe; nada que validar." >> "$RUN_DIR/integrity.txt"
        return
    fi
    if ! command -v python3 &>/dev/null; then
        block "[$label] python3 no disponible; no se puede validar JSON"
        return
    fi
    local result
    if python3 -c "import sys,json; json.load(open('$SPEEDYG_JSON'))" 2>/dev/null; then
        result="ok"
    else
        result="INVALID"
    fi
    echo "[$label] scheduler.json válido: $result" >> "$RUN_DIR/integrity.txt"
    check "[$label] scheduler.json es JSON válido (resultado: $result)" \
        "$([[ "$result" == "ok" ]] && echo 0 || echo 1)"
}

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-022"

: > "$RUN_DIR/integrity.txt"
: > "$RUN_DIR/pids.txt"
: > "$RUN_DIR/restart-times.txt"
: > "$RUN_DIR/iterations.txt"
: > "$RUN_DIR/iterations-summary.txt"
: > "$RUN_DIR/state-sequences.txt"

echo "[INFO] Verificando herramientas opcionales..." | tee -a "$LOG"
HAS_SQLITE3=0; command -v sqlite3 &>/dev/null && HAS_SQLITE3=1
HAS_PYTHON3=0; command -v python3 &>/dev/null && HAS_PYTHON3=1
echo "sqlite3=$HAS_SQLITE3 python3=$HAS_PYTHON3" >> "$RUN_DIR/environment.txt"

# ═══════════════════════════════════════════════════════════════════════════════
# ESCENARIO A — Interrupción bajo carga de escritura (10 iteraciones)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[ESCENARIO A] Interrupción bajo carga de escritura" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

start_daemon --max-current 4 --queue-cap 30
require_daemon_config "max_current=4" "queue_cap=30"

# MAX_ID_BEFORE_A: mayor ID conocido antes de empezar (para verificar no-reutilización).
MAX_ID_BEFORE_A=0

for ITER in $(seq 1 $ITERATIONS); do
    DELAY=$(awk "BEGIN{printf \"%.3f\", 0.05 + 0.035 * $ITER}")
    echo "" | tee -a "$LOG"
    echo "[A] Iteración $ITER/$ITERATIONS (delay=${DELAY}s)" | tee -a "$LOG"
    echo "iter=$ITER delay=$DELAY" >> "$RUN_DIR/iterations.txt"

    SUBMIT_FILE="$RUN_DIR/submit-${ITER}.txt"
    : > "$SUBMIT_FILE"
    ACCEPTED_IDS=()

    # Lanzar JOBS_PER_ITER envíos en paralelo
    declare -a SUBM_PIDS=()
    declare -a SUBM_OUT_FILES=()
    for n in $(seq 1 $JOBS_PER_ITER); do
        TMP_OUT=$(mktemp)
        SUBM_OUT_FILES+=("$TMP_OUT")
        (
            OUT=$(client echo "carga-${ITER}-${n}" 2>&1)
            echo "$OUT" > "$TMP_OUT"
        ) &
        SUBM_PIDS+=("$!")
    done

    # Esperar el retardo y matar el daemon
    sleep "$DELAY"
    KILL_TS=$(date +%s.%N)
    echo "kill_ts=$KILL_TS iter=$ITER" >> "$RUN_DIR/iterations.txt"
    kill_daemon_sigkill

    # Recoger respuestas de los clientes que ya terminaron
    for sp in "${SUBM_PIDS[@]}"; do
        wait "$sp" 2>/dev/null || true
    done

    # Recoger IDs aceptados (los que llegaron antes del kill)
    for i in "${!SUBM_OUT_FILES[@]}"; do
        TMP_OUT="${SUBM_OUT_FILES[$i]}"
        OUT=$(cat "$TMP_OUT" 2>/dev/null || true)
        echo "iter=$ITER job=$((i+1)): $OUT" >> "$SUBMIT_FILE"
        if echo "$OUT" | grep -q "encolado correctamente"; then
            ID=$(echo "$OUT" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
            [[ -n "$ID" ]] && ACCEPTED_IDS+=("$ID")
        fi
        rm -f "$TMP_OUT"
    done

    echo "iter=$ITER accepted_count=${#ACCEPTED_IDS[@]} ids=${ACCEPTED_IDS[*]:-}" \
        >> "$RUN_DIR/iterations.txt"

    # Comprobar integridad de la base y el JSON tras el kill
    integrity_check_db  "A-iter${ITER}"
    integrity_check_json "A-iter${ITER}"

    # Reiniciar daemon
    restart_daemon --max-current 4 --queue-cap 30
    echo "iter=$ITER restart_secs=$RESTART_SECS" >> "$RUN_DIR/restart-times.txt"
    check "[A-iter${ITER}] Daemon reinicia y socket responde (${RESTART_SECS}s)" \
        "$([[ -n "$RESTART_SECS" ]] && echo 0 || echo 1)"

    # Verificar que responde health y status en menos de MAX_WAIT_STATUS s
    T0_STATUS=$(date +%s)
    STATUS_OUT=$(client status 2>&1)
    T1_STATUS=$(date +%s)
    STATUS_LAT=$((T1_STATUS - T0_STATUS))
    echo "$STATUS_OUT" > "$RUN_DIR/status-restart-${ITER}.txt"
    check "[A-iter${ITER}] status responde en menos de ${MAX_WAIT_STATUS}s (latencia: ${STATUS_LAT}s)" \
        "$([[ $STATUS_LAT -lt $MAX_WAIT_STATUS ]] && echo 0 || echo 1)"

    HEALTH_OUT=$(client health 2>&1)
    check "[A-iter${ITER}] health responde OK" \
        "$(echo "$HEALTH_OUT" | grep -q "OK" && echo 0 || echo 1)"

    # Comprobar que ningún ID aceptado desapareció
    MISSING=0
    for AID in "${ACCEPTED_IDS[@]}"; do
        if ! grep -q "Job #${AID}" "$RUN_DIR/status-restart-${ITER}.txt"; then
            echo "[FAIL] iter=$ITER ID aceptado #$AID no encontrado en status" | tee -a "$LOG"
            MISSING=$((MISSING+1))
        fi
    done
    check "[A-iter${ITER}] Ningún ID aceptado desaparece tras reiniciar (faltantes: $MISSING)" \
        "$([[ $MISSING -eq 0 ]] && echo 0 || echo 1)"

    # Comprobar que no hay IDs duplicados en status
    DUP=$(grep -oE '^Job #[0-9]+:' "$RUN_DIR/status-restart-${ITER}.txt" \
        | sort | uniq -d | grep -c . || true)
    check "[A-iter${ITER}] Sin IDs duplicados en status (duplicados: $DUP)" \
        "$([[ $DUP -eq 0 ]] && echo 0 || echo 1)"

    # Esperar a que no quede ningún Queued ni Running
    wait_no_active $MAX_WAIT_RECOVERY
    WAIT_RC=$?
    STATUS_FINAL=$(client status 2>&1)
    echo "$STATUS_FINAL" > "$RUN_DIR/status-final-${ITER}.txt"
    check "[A-iter${ITER}] Sin trabajos Queued/Running tras recuperación (${MAX_WAIT_RECOVERY}s)" \
        "$([[ $WAIT_RC -eq 0 ]] && echo 0 || echo 1)"

    # Verificar que todo Succeeded tiene exit code 0 y nadie quedó Running
    RUNNING_LEFT=$(grep -cE '\[Running\]' "$RUN_DIR/status-final-${ITER}.txt" || true)
    check "[A-iter${ITER}] Sin trabajos en Running tras recuperación (encontrados: $RUNNING_LEFT)" \
        "$([[ $RUNNING_LEFT -eq 0 ]] && echo 0 || echo 1)"

    BAD_SUCC=$(grep -E '\[Succeeded\]' "$RUN_DIR/status-final-${ITER}.txt" \
        | grep -v "exit code: 0" | grep -c . || true)
    check "[A-iter${ITER}] Todo Succeeded tiene exit code 0 (con code!=0: $BAD_SUCC)" \
        "$([[ $BAD_SUCC -eq 0 ]] && echo 0 || echo 1)"

    # Enviar un trabajo nuevo y verificar que su ID es mayor que todos los existentes
    if [[ $MISSING -eq 0 ]]; then
        CURRENT_MAX=$(grep -oE 'Job #[0-9]+' "$RUN_DIR/status-final-${ITER}.txt" \
            | grep -oE '[0-9]+' | sort -n | tail -1 || echo "0")
        NEW_OUT=$(client echo nuevo 2>&1)
        NEW_ID=$(echo "$NEW_OUT" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
        check "[A-iter${ITER}] ID nuevo (#${NEW_ID}) es mayor que el máximo actual (#${CURRENT_MAX})" \
            "$([[ -n "$NEW_ID" && "$NEW_ID" -gt "${CURRENT_MAX:-0}" ]] && echo 0 || echo 1)"
        [[ -n "$NEW_ID" && "$NEW_ID" -gt "${MAX_ID_BEFORE_A:-0}" ]] && MAX_ID_BEFORE_A=$NEW_ID
    fi

    # Resumen de la iteración
    {
        echo "iter=$ITER"
        echo "accepted=${#ACCEPTED_IDS[@]}"
        echo "missing=$MISSING"
        echo "duplicates=$DUP"
        echo "running_left=$RUNNING_LEFT"
        echo "bad_succeeded=$BAD_SUCC"
        echo "---"
    } >> "$RUN_DIR/iterations-summary.txt"

    unset SUBM_PIDS SUBM_OUT_FILES ACCEPTED_IDS
done

# ═══════════════════════════════════════════════════════════════════════════════
# ESCENARIO B — Clasificación tras reinicio (estado determinista)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[ESCENARIO B] Clasificación tras reinicio" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

# Reiniciar el entorno con --max-current 1 --queue-cap 10.
# Se reutiliza el mismo DATA_DIR para que los IDs continúen.
kill_daemon_sigkill 2>/dev/null || true
"$DAEMON_BIN" \
    --socket   "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current 1 --queue-cap 10 \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!
wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
require_daemon_config "max_current=1" "queue_cap=10"

# D — echo terminado → Succeeded
OUT_D=$(client echo terminado 2>&1)
ID_D=$(echo "$OUT_D" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
check "[B] D enviado y aceptado (ID #$ID_D)" \
    "$([[ -n "$ID_D" ]] && echo 0 || echo 1)"
wait_job_state "$ID_D" "Succeeded" 15
check "[B] D llegó a Succeeded" \
    "$(client status "$ID_D" 2>&1 | grep -q "Succeeded" && echo 0 || echo 1)"

# E — sleep 1005 → cancelar → Canceled
OUT_E=$(client sleep 1005 2>&1)
ID_E=$(echo "$OUT_E" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
check "[B] E enviado y aceptado (ID #$ID_E)" \
    "$([[ -n "$ID_E" ]] && echo 0 || echo 1)"
wait_job_state "$ID_E" "Running" 15
client cancel "$ID_E" >/dev/null 2>&1 || true
sleep 1
check "[B] E quedó Canceled" \
    "$(client status "$ID_E" 2>&1 | grep -q "Canceled" && echo 0 || echo 1)"
kill_orphans_by_marker "sleep 1005"

# A — sleep 1003 → Running
OUT_A=$(client sleep 1003 2>&1)
ID_A=$(echo "$OUT_A" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
check "[B] A enviado y aceptado (ID #$ID_A)" \
    "$([[ -n "$ID_A" ]] && echo 0 || echo 1)"
wait_job_state "$ID_A" "Running" 15
check "[B] A está en Running" \
    "$(client status "$ID_A" 2>&1 | grep -q "Running" && echo 0 || echo 1)"

# B y C — Queued (--max-current 1, A ya ocupa la ranura)
OUT_B=$(client sleep 2 2>&1)
ID_B=$(echo "$OUT_B" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
OUT_C=$(client echo pendiente 2>&1)
ID_C=$(echo "$OUT_C" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
check "[B] B enviado (ID #$ID_B)" "$([[ -n "$ID_B" ]] && echo 0 || echo 1)"
check "[B] C enviado (ID #$ID_C)" "$([[ -n "$ID_C" ]] && echo 0 || echo 1)"
check "[B] B está Queued" \
    "$(client status "$ID_B" 2>&1 | grep -q "Queued" && echo 0 || echo 1)"
check "[B] C está Queued" \
    "$(client status "$ID_C" 2>&1 | grep -q "Queued" && echo 0 || echo 1)"

# Guardar status antes del kill (evidencia E-006)
for id_label in "D:$ID_D" "E:$ID_E" "A:$ID_A" "B:$ID_B" "C:$ID_C"; do
    lbl="${id_label%%:*}"; jid="${id_label#*:}"
    client status "$jid" 2>&1 > "$RUN_DIR/before-${jid}.txt"
    echo "before_${lbl}_id=${jid} state=$(job_state "$(cat "$RUN_DIR/before-${jid}.txt")")" \
        >> "$RUN_DIR/state-sequences.txt"
done

# SIGKILL
kill_daemon_sigkill
kill_orphans_by_marker "sleep 1003"

# Reiniciar
restart_daemon --max-current 1 --queue-cap 10
RC_B_RESTART=$?
check "[B] Daemon reinicia tras SIGKILL (socket responde en ${RESTART_SECS}s)" \
    "$([[ $RC_B_RESTART -eq 0 ]] && echo 0 || echo 1)"

# Capturar status inmediatamente (evidencia E-006)
for id_label in "D:$ID_D" "E:$ID_E" "A:$ID_A" "B:$ID_B" "C:$ID_C"; do
    lbl="${id_label%%:*}"; jid="${id_label#*:}"
    client status "$jid" 2>&1 > "$RUN_DIR/after-${jid}.txt"
    echo "after_${lbl}_id=${jid} state=$(job_state "$(cat "$RUN_DIR/after-${jid}.txt")")" \
        >> "$RUN_DIR/state-sequences.txt"
done

STATE_D_AFTER=$(job_state "$(cat "$RUN_DIR/after-${ID_D}.txt")")
STATE_E_AFTER=$(job_state "$(cat "$RUN_DIR/after-${ID_E}.txt")")
STATE_A_AFTER=$(job_state "$(cat "$RUN_DIR/after-${ID_A}.txt")")
STATE_B_AFTER=$(job_state "$(cat "$RUN_DIR/after-${ID_B}.txt")")
STATE_C_AFTER=$(job_state "$(cat "$RUN_DIR/after-${ID_C}.txt")")

check "[B] D permanece Succeeded tras reinicio (estado: $STATE_D_AFTER)" \
    "$([[ "$STATE_D_AFTER" == "Succeeded" ]] && echo 0 || echo 1)"
check "[B] E permanece Canceled tras reinicio (estado: $STATE_E_AFTER)" \
    "$([[ "$STATE_E_AFTER" == "Canceled" ]] && echo 0 || echo 1)"
check "[B] A queda Interrupted (no Running/Succeeded) tras reinicio (estado: $STATE_A_AFTER)" \
    "$([[ "$STATE_A_AFTER" == "Interrupted" ]] && echo 0 || echo 1)"

# Verificar que los datos de D y E son idénticos antes/después
DIFF_D=$(diff <(grep -v "^$" "$RUN_DIR/before-${ID_D}.txt") \
              <(grep -v "^$" "$RUN_DIR/after-${ID_D}.txt") | grep -c . || true)
DIFF_E=$(diff <(grep -v "^$" "$RUN_DIR/before-${ID_E}.txt") \
              <(grep -v "^$" "$RUN_DIR/after-${ID_E}.txt") | grep -c . || true)
check "[B] Datos de D idénticos antes y después del reinicio (diff lines: $DIFF_D)" \
    "$([[ $DIFF_D -eq 0 ]] && echo 0 || echo 1)"
check "[B] Datos de E idénticos antes y después del reinicio (diff lines: $DIFF_E)" \
    "$([[ $DIFF_E -eq 0 ]] && echo 0 || echo 1)"

# Esperar a que B y C lleguen a Succeeded
wait_job_state "$ID_B" "Succeeded" $MAX_WAIT_RECOVERY
wait_job_state "$ID_C" "Succeeded" $MAX_WAIT_RECOVERY

STATE_B_FINAL=$(job_state "$(client status "$ID_B" 2>&1)")
STATE_C_FINAL=$(job_state "$(client status "$ID_C" 2>&1)")
STATE_A_FINAL=$(job_state "$(client status "$ID_A" 2>&1)")
echo "final_B=$STATE_B_FINAL final_C=$STATE_C_FINAL final_A=$STATE_A_FINAL" \
    >> "$RUN_DIR/state-sequences.txt"

check "[B] B termina en Succeeded (estado final: $STATE_B_FINAL)" \
    "$([[ "$STATE_B_FINAL" == "Succeeded" ]] && echo 0 || echo 1)"
check "[B] C termina en Succeeded (estado final: $STATE_C_FINAL)" \
    "$([[ "$STATE_C_FINAL" == "Succeeded" ]] && echo 0 || echo 1)"
check "[B] A permanece Interrupted al final (estado final: $STATE_A_FINAL)" \
    "$([[ "$STATE_A_FINAL" == "Interrupted" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# ESCENARIO C — Archivos de persistencia dañados
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[ESCENARIO C] Archivos de persistencia dañados" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

# Reiniciar el daemon con --max-current 4 --queue-cap 30 para construir la línea base.
kill_daemon_sigkill 2>/dev/null || true
"$DAEMON_BIN" \
    --socket   "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current 4 --queue-cap 30 \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!
wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
require_daemon_config "max_current=4" "queue_cap=30"

# Línea base: 2 × echo → Succeeded, 1 × sleep 1006 → Canceled
OUT_BL1=$(client echo base-uno 2>&1)
ID_BL1=$(echo "$OUT_BL1" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
OUT_BL2=$(client echo base-dos 2>&1)
ID_BL2=$(echo "$OUT_BL2" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
OUT_BL3=$(client sleep 1006 2>&1)
ID_BL3=$(echo "$OUT_BL3" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)

wait_job_state "$ID_BL1" "Succeeded" 15
wait_job_state "$ID_BL2" "Succeeded" 15
wait_job_state "$ID_BL3" "Running"   15
client cancel "$ID_BL3" >/dev/null 2>&1 || true
sleep 1
kill_orphans_by_marker "sleep 1006"
wait_job_state "$ID_BL3" "Canceled" 10

# Estado de línea base
BL_STATUS=$(client status 2>&1)
echo "$BL_STATUS" > "$RUN_DIR/baseline-status.txt"
BL_STATE1=$(job_state "$(client status "$ID_BL1" 2>&1)")
BL_STATE2=$(job_state "$(client status "$ID_BL2" 2>&1)")
BL_STATE3=$(job_state "$(client status "$ID_BL3" 2>&1)")
check "[C] Línea base: BL1=$BL_STATE1 BL2=$BL_STATE2 BL3=$BL_STATE3" \
    "$([[ "$BL_STATE1" == "Succeeded" && "$BL_STATE2" == "Succeeded" && "$BL_STATE3" == "Canceled" ]] \
       && echo 0 || echo 1)"

# Kill en reposo y copiar la carpeta de datos
kill_daemon_sigkill
BASELINE_BACKUP="$DATA_DIR/../tc022-baseline-backup"
cp -a "$DATA_DIR/." "$BASELINE_BACKUP"
echo "[INFO] Línea base guardada en $BASELINE_BACKUP" | tee -a "$LOG"

# Función para restaurar la línea base
restore_baseline() {
    kill_daemon_sigkill 2>/dev/null || true
    rm -rf "$DATA_DIR"
    cp -a "$BASELINE_BACKUP" "$DATA_DIR"
}

# Función para verificar que el estado recuperado coincide con la línea base
verify_matches_baseline() {
    local label="$1"
    local outfile="$RUN_DIR/corrupt-${label}.txt"
    local status_out
    status_out=$(client status 2>&1)
    echo "$status_out" > "$outfile"

    local s1 s2 s3
    s1=$(job_state "$(client status "$ID_BL1" 2>&1)")
    s2=$(job_state "$(client status "$ID_BL2" 2>&1)")
    s3=$(job_state "$(client status "$ID_BL3" 2>&1)")
    echo "states: BL1=$s1 BL2=$s2 BL3=$s3" >> "$outfile"

    check "[$label] BL1 coincide con línea base: Succeeded (obtenido: $s1)" \
        "$([[ "$s1" == "Succeeded" ]] && echo 0 || echo 1)"
    check "[$label] BL2 coincide con línea base: Succeeded (obtenido: $s2)" \
        "$([[ "$s2" == "Succeeded" ]] && echo 0 || echo 1)"
    check "[$label] BL3 coincide con línea base: Canceled (obtenido: $s3)" \
        "$([[ "$s3" == "Canceled" ]] && echo 0 || echo 1)"
}

# ── C1: scheduler.json.tmp parcial (escritura interrumpida antes del rename) ──
echo "" | tee -a "$LOG"
echo "[C1] Archivo .tmp parcial" | tee -a "$LOG"
restore_baseline

if [[ -f "$DATA_DIR/scheduler.json" ]]; then
    HALF=$(( $(wc -c < "$DATA_DIR/scheduler.json") / 2 ))
    dd if="$DATA_DIR/scheduler.json" bs=1 count="$HALF" \
        of="$DATA_DIR/scheduler.json.tmp" 2>/dev/null
fi

"$DAEMON_BIN" \
    --socket   "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current 4 --queue-cap 30 \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!
wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
verify_matches_baseline "C1"
kill_daemon_sigkill

# ── C2: scheduler.json truncado a la mitad; base SQLite intacta ───────────────
echo "" | tee -a "$LOG"
echo "[C2] scheduler.json truncado a la mitad" | tee -a "$LOG"
restore_baseline

if [[ -f "$DATA_DIR/scheduler.json" ]]; then
    HALF=$(( $(wc -c < "$DATA_DIR/scheduler.json") / 2 ))
    truncate -s "$HALF" "$DATA_DIR/scheduler.json" 2>/dev/null \
        || dd if="$DATA_DIR/scheduler.json" bs=1 count="$HALF" \
              of="$DATA_DIR/scheduler.json.truncated" 2>/dev/null \
           && mv "$DATA_DIR/scheduler.json.truncated" "$DATA_DIR/scheduler.json"
fi

"$DAEMON_BIN" \
    --socket   "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current 4 --queue-cap 30 \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!
wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
verify_matches_baseline "C2"
kill_daemon_sigkill

# ── C3: speedyg.db con bytes inválidos; scheduler.json intacto ───────────────
echo "" | tee -a "$LOG"
echo "[C3] speedyg.db corrupto; JSON intacto" | tee -a "$LOG"
restore_baseline

printf '\xDE\xAD\xBE\xEF\x00\x00\x00\x00' > "$SPEEDYG_DB"

"$DAEMON_BIN" \
    --socket   "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current 4 --queue-cap 30 \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!
wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
verify_matches_baseline "C3"

# La recuperación debe quedar registrada en daemon.log
LOG_HAS_RECOVERY=$(grep -ciE "(corrupt|recover|no pudo|ilegible|invalid|error)" \
    "$RUN_DIR/daemon.log" || true)
check "[C3] daemon.log registra evento de recuperación/error al leer la base (ocurrencias: $LOG_HAS_RECOVERY)" \
    "$([[ $LOG_HAS_RECOVERY -gt 0 ]] && echo 0 || echo 1)"
echo "daemon_log_recovery_mentions=$LOG_HAS_RECOVERY" >> "$RUN_DIR/corrupt-C3.txt"

# Enviar un trabajo nuevo, que debe sobrevivir a otro kill+reinicio
OUT_C3_NEW=$(client echo c3-nuevo 2>&1)
ID_C3_NEW=$(echo "$OUT_C3_NEW" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
check "[C3] Trabajo nuevo aceptado tras recuperación (ID #$ID_C3_NEW)" \
    "$([[ -n "$ID_C3_NEW" ]] && echo 0 || echo 1)"
wait_job_state "$ID_C3_NEW" "Succeeded" 15

# Segundo kill + reinicio para verificar que el trabajo nuevo persiste
kill_daemon_sigkill
"$DAEMON_BIN" \
    --socket   "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current 4 --queue-cap 30 \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!
wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"

STATE_C3_NEW=$(job_state "$(client status "$ID_C3_NEW" 2>&1)")
check "[C3] Trabajo nuevo (#$ID_C3_NEW) sobrevive al segundo reinicio (estado: $STATE_C3_NEW)" \
    "$([[ "$STATE_C3_NEW" == "Succeeded" ]] && echo 0 || echo 1)"
{
    echo "new_job_id=$ID_C3_NEW"
    echo "state_after_second_restart=$STATE_C3_NEW"
} >> "$RUN_DIR/recovery-C3.txt"

kill_daemon_sigkill

# ── C4: base Y JSON ilegibles ─────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[C4] Base y JSON ilegibles" | tee -a "$LOG"
restore_baseline

printf '\xDE\xAD\xBE\xEF\x00\x00\x00\x00' > "$SPEEDYG_DB"
printf 'NO ES JSON {{{ \x00\x01\x02' > "$SPEEDYG_JSON"

"$DAEMON_BIN" \
    --socket   "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current 4 --queue-cap 30 \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!
C4_RC=0
wait_socket "$SOCKET" "$DAEMON_WAIT_SECS" || C4_RC=1
check "[C4] Daemon arranca y socket responde pese a archivos ilegibles" \
    "$([[ $C4_RC -eq 0 ]] && echo 0 || echo 1)"

C4_HEALTH=$(client health 2>&1)
check "[C4] health responde OK con archivos ilegibles (obtenido: '$C4_HEALTH')" \
    "$(echo "$C4_HEALTH" | grep -q "OK" && echo 0 || echo 1)"

C4_STATUS=$(client status 2>&1)
echo "$C4_STATUS" > "$RUN_DIR/corrupt-C4.txt"
C4_JOB_COUNT=$(grep -cE '^Job #[0-9]+:' "$RUN_DIR/corrupt-C4.txt" || true)
check "[C4] status no muestra trabajos inventados (trabajos en status: $C4_JOB_COUNT)" \
    "$([[ $C4_JOB_COUNT -eq 0 ]] && echo 0 || echo 1)"

C4_LOG_ERRORS=$(grep -ciE "(corrupt|error|ilegible|no pudo|invalid)" \
    "$RUN_DIR/daemon.log" || true)
check "[C4] daemon.log registra el error de lectura (ocurrencias: $C4_LOG_ERRORS)" \
    "$([[ $C4_LOG_ERRORS -gt 0 ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# CIERRE
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[CIERRE] Verificación final y limpieza" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

HEALTH_FINAL=$(client health 2>&1)
check "[CIERRE] Daemon responde health al terminar (obtenido: '$HEALTH_FINAL')" \
    "$(echo "$HEALTH_FINAL" | grep -q "OK" && echo 0 || echo 1)"

# Eliminar cualquier proceso huérfano residual de los marcadores usados en el TC
for marker in "sleep 1003" "sleep 1005" "sleep 1006"; do
    kill_orphans_by_marker "$marker"
done

finish_run
