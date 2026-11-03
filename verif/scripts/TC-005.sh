#!/bin/bash
# verif/scripts/TC-005.sh
#
# TC-005 — Cancelar un trabajo en cola y en ejecución
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-005.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RF-10: Cancelar trabajo en cola y en ejecución, reflejar resultado.
#   - RNF-21: Mensajes de error claros en cancelaciones inválidas.
#   - RNF-30: Sin procesos residuales tras cancelación.
#
# Resultados en:
#   verif/results/TC-005/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=1          # ranura única: A corre, B y C esperan en cola
QUEUE_CAP=3
SAMPLE_INTERVAL=0.1
KILL_WAIT_SECS=5       # tiempo máx. para que el proceso desaparezca tras cancelar
OBSERVE_SECS=3        # tiempo de observación posterior sin regresión
MAX_WAIT_SECS=15      # espera máxima para avance y finalización de C

CMD_A=(sleep 1001)     # Pasa a Running y se cancela en ejecución
CMD_B=(sleep 1002)     # Queda en Queued y se cancela en cola
CMD_C=(echo siguiente) # Queda en Queued y debe avanzar a Running/Succeeded al liberarse ranura

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-005"
start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$MAX_CURRENT" "queue_cap=$QUEUE_CAP"

STATUS_SAMPLES="$RUN_DIR/status-samples.log"
SAMPLING_FLAG="$RUN_DIR/.sampling"
: > "$STATUS_SAMPLES"

# ── Muestreo en segundo plano ────────────────────────────────────────────────
sampler() {
    set +e
    while [[ -f "$SAMPLING_FLAG" ]]; do
        local ts out states
        ts=$(date +%s.%N)
        out=$(client status 2>&1)
        states=$(echo "$out" \
            | sed -nE 's/^Job #([0-9]+): .*\[([A-Za-z]+)(\([-0-9]+\))?\].*$/\1:\2/p' \
            | sort -t: -k1,1n | paste -sd, -)
        echo "$ts states=$states" >> "$STATUS_SAMPLES"
        sleep "$SAMPLE_INTERVAL"
    done
}

touch "$SAMPLING_FLAG"
sampler &
SAMPLER_PID=$!

submit() {   # submit <nombre> <cmd...> -> imprime el ID
    local name="$1"; shift
    local out id
    out=$(client "$@" 2>&1)
    echo "$name: $* -> $out" | tee -a "$LOG" >> "$RUN_DIR/submit.txt"
    id=$(grep -oE 'Job #[0-9]+ encolado' <<< "$out" | grep -oE '[0-9]+' | head -1)
    echo "$id"
}

# ── Paso 1: Enviar A, B y C ──────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[1] Enviando A='${CMD_A[*]}' B='${CMD_B[*]}' C='${CMD_C[*]}'" | tee -a "$LOG"
: > "$RUN_DIR/submit.txt"
ID_A=$(submit A "${CMD_A[@]}")
ID_B=$(submit B "${CMD_B[@]}")
ID_C=$(submit C "${CMD_C[@]}")
{ echo "A=$ID_A"; echo "B=$ID_B"; echo "C=$ID_C"; } > "$RUN_DIR/jobs.txt"

DISTINCT=$(printf '%s\n' "$ID_A" "$ID_B" "$ID_C" | grep -v '^$' | sort -u | grep -c .)
check "Los 3 envíos fueron aceptados con IDs distintos (distintos: $DISTINCT)" \
    "$([[ "$DISTINCT" -eq 3 ]] && echo 0 || echo 1)"

if [[ "$DISTINCT" -ne 3 ]]; then
    echo "[ERROR] Sin los 3 IDs no se puede continuar." | tee -a "$LOG"
    rm -f "$SAMPLING_FLAG"; wait "$SAMPLER_PID" 2>/dev/null || true
    finish_run
fi

# ── Paso 2: Estado antes de cancelar ─────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[2] Comprobando estados iniciales: A=Running, B=Queued, C=Queued" | tee -a "$LOG"
sleep 0.5
SNAP_A_PRE=$(client status "$ID_A" 2>&1)
SNAP_B_PRE=$(client status "$ID_B" 2>&1)
SNAP_C_PRE=$(client status "$ID_C" 2>&1)
{
    echo "$SNAP_A_PRE"
    echo "$SNAP_B_PRE"
    echo "$SNAP_C_PRE"
} | tee "$RUN_DIR/status-before.txt" >> "$LOG"

ST_A_PRE=$(job_state "$SNAP_A_PRE")
ST_B_PRE=$(job_state "$SNAP_B_PRE")
ST_C_PRE=$(job_state "$SNAP_C_PRE")

check "A está en Running antes de cancelar (obtenido: '$ST_A_PRE')" \
    "$([[ "$ST_A_PRE" == "Running" ]] && echo 0 || echo 1)"
check "B está en Queued antes de cancelar (obtenido: '$ST_B_PRE')" \
    "$([[ "$ST_B_PRE" == "Queued" ]] && echo 0 || echo 1)"
check "C está en Queued antes de cancelar (obtenido: '$ST_C_PRE')" \
    "$([[ "$ST_C_PRE" == "Queued" ]] && echo 0 || echo 1)"

# ── Paso 3: Cancelar B en cola (RF-10) ────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[3] Cancelando B (Job #$ID_B) estando en cola" | tee -a "$LOG"
CANCEL_B=$(client cancel "$ID_B" 2>&1)
echo "$CANCEL_B" | tee "$RUN_DIR/cancel-queued.txt" >> "$LOG"

check "Respuesta de cancelar B indica cancelación e incluye ID #$ID_B" \
    "$((grep -qi "cancelad" <<< "$CANCEL_B" && grep -q "$ID_B" <<< "$CANCEL_B") && echo 0 || echo 1)"

SNAP_B_POST=$(client status "$ID_B" 2>&1)
SNAP_A_MID=$(client status "$ID_A" 2>&1)
SNAP_C_MID=$(client status "$ID_C" 2>&1)
{
    echo "$SNAP_B_POST"
    echo "$SNAP_A_MID"
    echo "$SNAP_C_MID"
} | tee "$RUN_DIR/status-after-queued.txt" >> "$LOG"

check "B pasa a estado Canceled tras cancelar en cola (obtenido: '$(job_state "$SNAP_B_POST")')" \
    "$([[ "$(job_state "$SNAP_B_POST")" == "Canceled" ]] && echo 0 || echo 1)"
check "A sigue en Running tras cancelar B en cola (obtenido: '$(job_state "$SNAP_A_MID")')" \
    "$([[ "$(job_state "$SNAP_A_MID")" == "Running" ]] && echo 0 || echo 1)"
check "C sigue en Queued tras cancelar B en cola (obtenido: '$(job_state "$SNAP_C_MID")')" \
    "$([[ "$(job_state "$SNAP_C_MID")" == "Queued" ]] && echo 0 || echo 1)"

# Comprobar que el proceso de B ('sleep 1002') nunca existió
PROC_B_COUNT=$(pgrep -f "sleep 1002" 2>/dev/null | grep -c .) || PROC_B_COUNT=0
check "Proceso de B ('sleep 1002') nunca fue ejecutado en el SO (encontrados: $PROC_B_COUNT)" \
    "$([[ "$PROC_B_COUNT" -eq 0 ]] && echo 0 || echo 1)"

# ── Paso 4: Cancelar A en ejecución (RF-10, RNF-30) ───────────────────────────
echo "" | tee -a "$LOG"
echo "[4] Localizando PID de A y cancelando en ejecución" | tee -a "$LOG"

# Localizar PIDs asociados a A antes de cancelar
DIRECT_CHILDREN=$(ps -eo pid,ppid,comm 2>/dev/null | awk -v dpid="$DAEMON_PID" '$2 == dpid {print $1}')
MARKER_PIDS_A=$(pgrep -f "sleep 1001" 2>/dev/null || true)
ALL_PIDS_A=$(printf '%s\n' $DIRECT_CHILDREN $MARKER_PIDS_A | grep -v '^$' | sort -u | tr '\n' ' ')

{
    echo "daemon_pid=$DAEMON_PID"
    echo "direct_children=$DIRECT_CHILDREN"
    echo "marker_pids_sleep_1001=$MARKER_PIDS_A"
    echo "all_tracked_pids_A=$ALL_PIDS_A"
} > "$RUN_DIR/pids-before.txt"
cat "$RUN_DIR/pids-before.txt" | tee -a "$LOG"

check "Se identificó el proceso activo de A antes de cancelar ('sleep 1001')" \
    "$([[ -n "${MARKER_PIDS_A// /}" ]] && echo 0 || echo 1)"

CANCEL_A=$(client cancel "$ID_A" 2>&1)
echo "$CANCEL_A" | tee "$RUN_DIR/cancel-running.txt" >> "$LOG"

check "Respuesta de cancelar A indica cancelación e incluye ID #$ID_A" \
    "$((grep -qi "cancelad" <<< "$CANCEL_A" && grep -q "$ID_A" <<< "$CANCEL_A") && echo 0 || echo 1)"

# Esperar hasta KILL_WAIT_SECS a que el estado sea Canceled y los procesos mueran
ELAPSED=0
A_STATE_CANCELED=0
A_PROCS_DEAD=0
while [[ $ELAPSED -lt $KILL_WAIT_SECS ]]; do
    SNAP_A_CURR=$(client status "$ID_A" 2>&1)
    if [[ "$(job_state "$SNAP_A_CURR")" == "Canceled" ]]; then
        A_STATE_CANCELED=1
    fi

    # Comprobar si los PIDs registrados o el marcador siguen vivos
    STILL_ALIVE=0
    for p in $ALL_PIDS_A; do
        if [[ -d "/proc/$p" ]] || kill -0 "$p" 2>/dev/null; then
            STILL_ALIVE=$((STILL_ALIVE + 1))
        fi
    done
    REMAINING_MARKER=$(pgrep -f "sleep 1001" 2>/dev/null | grep -c .) || REMAINING_MARKER=0

    if [[ "$STILL_ALIVE" -eq 0 && "$REMAINING_MARKER" -eq 0 ]]; then
        A_PROCS_DEAD=1
    fi

    if [[ "$A_STATE_CANCELED" -eq 1 && "$A_PROCS_DEAD" -eq 1 ]]; then
        break
    fi

    sleep 0.5
    ELAPSED=$((ELAPSED + 1))
done

# Registrar evidencia de PIDs después de cancelar
{
    echo "elapsed_sec=$ELAPSED"
    echo "state_canceled=$A_STATE_CANCELED"
    echo "procs_dead=$A_PROCS_DEAD"
    echo "remaining_direct_children=$(ps -eo pid,ppid,comm 2>/dev/null | awk -v dpid="$DAEMON_PID" '$2 == dpid {print $1}')"
    echo "remaining_sleep_1001=$(pgrep -f "sleep 1001" 2>/dev/null || true)"
} > "$RUN_DIR/pids-after.txt"

check "A pasa a estado Canceled dentro de ${KILL_WAIT_SECS}s (tiempo: ${ELAPSED}s)" \
    "$([[ "$A_STATE_CANCELED" -eq 1 ]] && echo 0 || echo 1)"
check "El proceso de A ('sleep 1001') deja de existir en el SO dentro de ${KILL_WAIT_SECS}s" \
    "$([[ "$A_PROCS_DEAD" -eq 1 ]] && echo 0 || echo 1)"

# ── Paso 5: Ventana de observación posterior (3 s) ───────────────────────────
echo "" | tee -a "$LOG"
echo "[5] Observación posterior (${OBSERVE_SECS}s): verificar estabilidad de Canceled" | tee -a "$LOG"
sleep "$OBSERVE_SECS"

SNAP_A_OBS=$(client status "$ID_A" 2>&1)
SNAP_B_OBS=$(client status "$ID_B" 2>&1)
check "A permanece en Canceled tras ${OBSERVE_SECS}s (obtenido: '$(job_state "$SNAP_A_OBS")')" \
    "$([[ "$(job_state "$SNAP_A_OBS")" == "Canceled" ]] && echo 0 || echo 1)"
check "B permanece en Canceled tras ${OBSERVE_SECS}s (obtenido: '$(job_state "$SNAP_B_OBS")')" \
    "$([[ "$(job_state "$SNAP_B_OBS")" == "Canceled" ]] && echo 0 || echo 1)"

# ── Paso 6: Avance de C (RF-10) ──────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[6] Verificando avance de C tras liberación de ranura (máx. ${MAX_WAIT_SECS}s)" | tee -a "$LOG"
C_DONE=0
WAIT_C=0
while [[ $WAIT_C -lt $MAX_WAIT_SECS ]]; do
    SNAP_C_CURR=$(client status "$ID_C" 2>&1)
    if [[ "$(job_state "$SNAP_C_CURR")" == "Succeeded" ]]; then
        C_DONE=1
        break
    fi
    sleep 0.5
    WAIT_C=$((WAIT_C + 1))
done

SNAP_C_FINAL=$(client status "$ID_C" 2>&1)
check "C avanza y termina en Succeeded tras cancelarse A (tiempo: ${WAIT_C}s)" \
    "$([[ "$C_DONE" -eq 1 ]] && echo 0 || echo 1)"
check "C finaliza con exit code: 0" \
    "$(grep -q 'exit code: 0' <<< "$SNAP_C_FINAL" && echo 0 || echo 1)"

# Detener el muestreador
rm -f "$SAMPLING_FLAG"
wait "$SAMPLER_PID" 2>/dev/null || true

# ── Paso 7: Cancelaciones inválidas (RF-10, RNF-21) ───────────────────────────
echo "" | tee -a "$LOG"
echo "[7] Evaluando cancelaciones inválidas (RNF-21)" | tee -a "$LOG"

INV_C=$(client cancel "$ID_C" 2>&1)
INV_A=$(client cancel "$ID_A" 2>&1)
INV_NON=$(client cancel 99999 2>&1)
INV_NOID=$(client cancel 2>&1)
INV_STR=$(client cancel abc 2>&1)

{
    echo "--- cancel terminado (Job #$ID_C) ---"
    echo "$INV_C"
    echo "--- cancel ya cancelado (Job #$ID_A) ---"
    echo "$INV_A"
    echo "--- cancel id inexistente (99999) ---"
    echo "$INV_NON"
    echo "--- cancel sin id ---"
    echo "$INV_NOID"
    echo "--- cancel id no numerico (abc) ---"
    echo "$INV_STR"
} | tee "$RUN_DIR/cancel-invalid.txt" >> "$LOG"

# Validación según tabla de sección 6 de TC-005.md:
# 1. cancel <C> (terminado): Error con ID y motivo (ya terminó / Succeeded); no afirma cancelar
check "cancel <terminado> reporta error con ID #$ID_C y motivo (terminado/Succeeded)" \
    "$((grep -q "$ID_C" <<< "$INV_C" && grep -qiE "terminad|succeeded|completad" <<< "$INV_C" && ! grep -qiE "^Job #[0-9]+ cancelado correctamente" <<< "$INV_C") && echo 0 || echo 1)"

# 2. cancel <A> (ya cancelado): Respuesta con ID que indica ya estaba cancelado
check "cancel <ya cancelado> indica que el Job #$ID_A ya estaba cancelado" \
    "$((grep -q "$ID_A" <<< "$INV_A" && grep -qiE "ya.*cancelad|anteriormente.*cancelad" <<< "$INV_A") && echo 0 || echo 1)"

# 3. cancel <99999>: Error explícito de no encontrado / inexistente con ID
check "cancel <inexistente> reporta error con ID 99999 (no encontrado / inexistente)" \
    "$((grep -q "99999" <<< "$INV_NON" && grep -qiE "no encontrad|inexistente|no existe" <<< "$INV_NON") && echo 0 || echo 1)"

# 4. cancel sin ID: Mensaje de uso o sintaxis
check "cancel sin ID devuelve mensaje de uso o error de sintaxis" \
    "$(grep -qiE "uso:|error|requiere|argumento|sintaxis" <<< "$INV_NOID" && echo 0 || echo 1)"

# 5. cancel abc: Mensaje de que el ID debe ser numérico
check "cancel abc devuelve mensaje de ID entero / numérico" \
    "$(grep -qiE "entero|num[eé]rico|invalido|inválido|sintaxis" <<< "$INV_STR" && echo 0 || echo 1)"

# Comprobar que los estados no sufrieron mutaciones indeseadas
CHECK_C_AFTER=$(client status "$ID_C" 2>&1)
CHECK_A_AFTER=$(client status "$ID_A" 2>&1)
check "C sigue en Succeeded con exit code 0 tras cancelaciones inválidas" \
    "$(( [[ "$(job_state "$CHECK_C_AFTER")" == "Succeeded" ]] && grep -q 'exit code: 0' <<< "$CHECK_C_AFTER" ) && echo 0 || echo 1)"
check "A sigue en Canceled tras cancelaciones inválidas" \
    "$([[ "$(job_state "$CHECK_A_AFTER")" == "Canceled" ]] && echo 0 || echo 1)"

# ── Paso 8: Estado final y secuencias de estado ──────────────────────────────
echo "" | tee -a "$LOG"
echo "[8] Verificando estado final y secuencias de estado observadas" | tee -a "$LOG"

FA=$(client status "$ID_A" 2>&1)
FB=$(client status "$ID_B" 2>&1)
FC=$(client status "$ID_C" 2>&1)
{
    echo "$FA"
    echo "$FB"
    echo "$FC"
} | tee "$RUN_DIR/final-status.txt" >> "$LOG"

# Analizar muestras de estado
awk '
function rank(s) { return (s == "Queued") ? 0 : (s == "Running") ? 1 : 2 }
{
    s = ""
    for (i = 1; i <= NF; i++) if ($i ~ /^states=/) s = substr($i, 8)
    n = split(s, p, ","); run = 0
    for (k = 1; k <= n; k++) {
        if (p[k] == "") continue
        split(p[k], kv, ":"); id = kv[1] + 0; st = kv[2]
        if (st == "Running") run++
        if (!(id in last)) { last[id] = st; seq[id] = st; continue }
        if (st != last[id]) {
            if (rank(last[id]) == 2 || rank(st) < rank(last[id]))
                bad[id] = bad[id] " " last[id] "->" st "@muestra" NR
            seq[id] = seq[id] ">" st; last[id] = st
        }
    }
    if (run > maxrun) maxrun = run
}
END {
    for (id in seq) printf "JOB %d %s |%s\n", id, seq[id], bad[id]
    printf "MAXRUN %d\n", maxrun + 0
}' "$STATUS_SAMPLES" | sort > "$RUN_DIR/state-sequences.txt"
cat "$RUN_DIR/state-sequences.txt" | tee -a "$LOG"

seq_of() { sed -nE "s/^JOB $1 ([^ ]*) \|.*/\1/p" "$RUN_DIR/state-sequences.txt"; }
bad_of() { sed -nE "s/^JOB $1 [^ ]* \|(.*)$/\1/p" "$RUN_DIR/state-sequences.txt"; }

SEQ_A=$(seq_of "$ID_A"); BAD_A=$(bad_of "$ID_A")
SEQ_B=$(seq_of "$ID_B"); BAD_B=$(bad_of "$ID_B")
SEQ_C=$(seq_of "$ID_C"); BAD_C=$(bad_of "$ID_C")

RE_A='^(Queued>)?Running>Canceled$'
# C es un 'echo' que termina en milisegundos: el muestreo (0,1 s) puede no ver
# 'Running'. Se acepta Queued>Succeeded si 'Iniciado' prueba que pasó por Running.
RE_C='^Queued>(Running>)?Succeeded$'
C_STARTED=1
grep -qE 'Iniciado: +[0-9]{4}-' <<< "$FC" && C_STARTED=0

check "A: secuencia de estados '$SEQ_A' cumple (Queued>)?Running>Canceled" \
    "$([[ "$SEQ_A" =~ $RE_A ]] && echo 0 || echo 1)"
check "A: sin regresiones de estado${BAD_A:+ (detectado:$BAD_A)}" \
    "$([[ -z "${BAD_A// /}" ]] && echo 0 || echo 1)"

check "B: secuencia de estados '$SEQ_B' cumple Queued>Canceled (nunca entró a Running)" \
    "$([[ "$SEQ_B" == "Queued>Canceled" ]] && echo 0 || echo 1)"
check "B: sin regresiones de estado${BAD_B:+ (detectado:$BAD_B)}" \
    "$([[ -z "${BAD_B// /}" ]] && echo 0 || echo 1)"

check "C: secuencia de estados '$SEQ_C' cumple Queued>(Running>)?Succeeded y registra hora de inicio" \
    "$([[ "$SEQ_C" =~ $RE_C && "$C_STARTED" -eq 0 ]] && echo 0 || echo 1)"
check "C: sin regresiones de estado${BAD_C:+ (detectado:$BAD_C)}" \
    "$([[ -z "${BAD_C// /}" ]] && echo 0 || echo 1)"

# ── Paso 9: Salud del daemon y verificación de procesos residuales ───────────
echo "" | tee -a "$LOG"
echo "[9] Verificando salud del daemon y ausencia de procesos residuales / zombis" | tee -a "$LOG"

HEALTH=$(client health 2>&1)
check "Daemon responde a comando health con OK (obtenido: '$HEALTH')" \
    "$(grep -q "OK:" <<< "$HEALTH" && echo 0 || echo 1)"

REM_A=$(pgrep -f "sleep 1001" 2>/dev/null | tr '\n' ' ')
REM_B=$(pgrep -f "sleep 1002" 2>/dev/null | tr '\n' ' ')
check "Sin procesos residuales de sleep 1001 en el sistema${REM_A:+ (PIDs:$REM_A)}" \
    "$([[ -z "${REM_A// /}" ]] && echo 0 || echo 1)"
check "Sin procesos residuales de sleep 1002 en el sistema${REM_B:+ (PIDs:$REM_B)}" \
    "$([[ -z "${REM_B// /}" ]] && echo 0 || echo 1)"

echo "[INFO] File descriptors abiertos por daemon: $(count_open_fds)" | tee -a "$LOG"
check_no_zombies

finish_run
