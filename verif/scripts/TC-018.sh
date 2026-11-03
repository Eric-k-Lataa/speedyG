#!/bin/bash
# verif/scripts/TC-018.sh
#
# TC-018 — Solicitud duplicada
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-018.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RF-27: Solicitudes duplicadas tratadas como trabajos independientes.
#   - RNF-27: Consistencia de estado y sin regresiones.
#
# Resultados en:
#   verif/results/TC-018/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=4
QUEUE_CAP=30
SAMPLE_INTERVAL=0.1
MAX_WAIT_ECHO=30

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-018"
start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$MAX_CURRENT" "queue_cap=$QUEUE_CAP"

STATUS_SAMPLES="$RUN_DIR/status-samples.log"
SAMPLING_FLAG="$RUN_DIR/.sampling"
: > "$STATUS_SAMPLES"

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

submit_job() {
    local out id
    out=$(client "$@" 2>&1)
    id=$(grep -oE 'Job #[0-9]+ encolado' <<< "$out" | grep -oE '[0-9]+' | head -1)
    echo "cmd='$*' -> id='$id' raw='$out'" >&2
    echo "$id"
}

# ── Escenario A: 5 × echo dup-A secuenciales ─────────────────────────────────
echo "" | tee -a "$LOG"
echo "[1] Escenario A: 5 envíos secuenciales de 'echo dup-A'" | tee -a "$LOG"
: > "$RUN_DIR/submit-A.txt"
IDS_A=()

for i in $(seq 1 5); do
    OUT=$(client echo dup-A 2>&1)
    echo "A$i: echo dup-A -> $OUT" >> "$RUN_DIR/submit-A.txt"
    ID=$(grep -oE 'Job #[0-9]+ encolado' <<< "$OUT" | grep -oE '[0-9]+' | head -1)
    IDS_A+=("$ID")
done

DISTINCT_A=$(printf '%s\n' "${IDS_A[@]}" | grep -v '^$' | sort -u | grep -c .)
check "Escenario A: 5 solicitudes secuenciales recibieron 5 IDs distintos (distintos: $DISTINCT_A)" \
    "$([[ "$DISTINCT_A" -eq 5 ]] && echo 0 || echo 1)"

# ── Escenario B: 10 × echo dup-B concurrentes ────────────────────────────────
echo "" | tee -a "$LOG"
echo "[2] Escenario B: 10 envíos concurrentes de 'echo dup-B'" | tee -a "$LOG"
: > "$RUN_DIR/submit-B.txt"

# Se espera solo a los clientes (no a $SAMPLER_PID, que corre hasta borrar el flag).
B_PIDS=()
for i in $(seq 1 10); do
    (
        OUT=$(client echo dup-B 2>&1)
        echo "B$i: echo dup-B -> $OUT" >> "$RUN_DIR/submit-B.txt"
    ) &
    B_PIDS+=("$!")
done
for b_pid in "${B_PIDS[@]}"; do
    wait "$b_pid" 2>/dev/null || true
done

IDS_B=($(grep -oE 'Job #[0-9]+ encolado' "$RUN_DIR/submit-B.txt" | grep -oE '[0-9]+' | sort -n))
DISTINCT_B=$(printf '%s\n' "${IDS_B[@]}" | grep -v '^$' | sort -u | grep -c .)
check "Escenario B: 10 solicitudes concurrentes recibieron 10 IDs distintos (distintos: $DISTINCT_B)" \
    "$([[ "$DISTINCT_B" -eq 10 ]] && echo 0 || echo 1)"

# ── Escenario C: 1 × echo dup-C enviado dos veces (reenvío) ──────────────────
echo "" | tee -a "$LOG"
echo "[3] Escenario C: Reenvío de 'echo dup-C' tras confirmación previa" | tee -a "$LOG"
: > "$RUN_DIR/submit-C.txt"
IDS_C=()

OUT_C1=$(client echo dup-C 2>&1)
echo "C1: echo dup-C -> $OUT_C1" >> "$RUN_DIR/submit-C.txt"
ID_C1=$(grep -oE 'Job #[0-9]+ encolado' <<< "$OUT_C1" | grep -oE '[0-9]+' | head -1)
IDS_C+=("$ID_C1")

OUT_C2=$(client echo dup-C 2>&1)
echo "C2: echo dup-C -> $OUT_C2" >> "$RUN_DIR/submit-C.txt"
ID_C2=$(grep -oE 'Job #[0-9]+ encolado' <<< "$OUT_C2" | grep -oE '[0-9]+' | head -1)
IDS_C+=("$ID_C2")

DISTINCT_C=$(printf '%s\n' "${IDS_C[@]}" | grep -v '^$' | sort -u | grep -c .)
check "Escenario C: 2 envíos de 'echo dup-C' recibieron 2 IDs distintos (distintos: $DISTINCT_C)" \
    "$([[ "$DISTINCT_C" -eq 2 ]] && echo 0 || echo 1)"

# ── Espera de finalización para los 17 trabajos echo ─────────────────────────
echo "" | tee -a "$LOG"
echo "[4] Esperando finalización de los 17 trabajos echo (A:5, B:10, C:2)" | tee -a "$LOG"
ALL_ECHO_IDS=("${IDS_A[@]}" "${IDS_B[@]}" "${IDS_C[@]}")
WAIT_ECHO=0
ALL_ECHO_SUCCEEDED=0

while [[ $WAIT_ECHO -lt $MAX_WAIT_ECHO ]]; do
    SUCC_COUNT=0
    for eid in "${ALL_ECHO_IDS[@]}"; do
        ST=$(job_state "$(client status "$eid" 2>&1)")
        [[ "$ST" == "Succeeded" ]] && SUCC_COUNT=$((SUCC_COUNT + 1))
    done

    if [[ "$SUCC_COUNT" -eq 17 ]]; then
        ALL_ECHO_SUCCEEDED=1
        break
    fi
    sleep 0.5
    WAIT_ECHO=$((WAIT_ECHO + 1))
done

check "Los 17 trabajos echo alcanzaron el estado Succeeded en ${WAIT_ECHO}s" \
    "$([[ "$ALL_ECHO_SUCCEEDED" -eq 1 ]] && echo 0 || echo 1)"

# ── Escenario D: 3 × sleep 3001 (aislamiento entre duplicados) ───────────────
echo "" | tee -a "$LOG"
echo "[5] Escenario D: 3 envíos de 'sleep 3001', cancelación aislada del segundo" | tee -a "$LOG"
: > "$RUN_DIR/submit-D.txt"
IDS_D=()

for i in 1 2 3; do
    OUT_D=$(client sleep 3001 2>&1)
    echo "D$i: sleep 3001 -> $OUT_D" >> "$RUN_DIR/submit-D.txt"
    ID_D=$(grep -oE 'Job #[0-9]+ encolado' <<< "$OUT_D" | grep -oE '[0-9]+' | head -1)
    IDS_D+=("$ID_D")
done

ID_D1="${IDS_D[0]}"
ID_D2="${IDS_D[1]}"
ID_D3="${IDS_D[2]}"

DISTINCT_D=$(printf '%s\n' "${IDS_D[@]}" | grep -v '^$' | sort -u | grep -c .)
check "Escenario D: 3 solicitudes de 'sleep 3001' recibieron 3 IDs distintos (distintos: $DISTINCT_D)" \
    "$([[ "$DISTINCT_D" -eq 3 ]] && echo 0 || echo 1)"

# Esperar a que los 3 entren a Running
sleep 0.5
ST_D1=$(job_state "$(client status "$ID_D1" 2>&1)")
ST_D2=$(job_state "$(client status "$ID_D2" 2>&1)")
ST_D3=$(job_state "$(client status "$ID_D3" 2>&1)")

check "Los 3 trabajos 'sleep 3001' están en Running simultáneamente" \
    "$([[ "$ST_D1" == "Running" && "$ST_D2" == "Running" && "$ST_D3" == "Running" ]] && echo 0 || echo 1)"

# Contar procesos en el SO antes de cancelar D2
PROCS_D_BEFORE=$(pgrep -f "sleep 3001" 2>/dev/null | grep -c .) || PROCS_D_BEFORE=0
{
    echo "procs_before_cancel=$PROCS_D_BEFORE"
    echo "pids=$(pgrep -f "sleep 3001" 2>/dev/null | tr '\n' ' ')"
} > "$RUN_DIR/pids-D.txt"

check "Existen 3 procesos independientes 'sleep 3001' en el SO (encontrados: $PROCS_D_BEFORE)" \
    "$([[ "$PROCS_D_BEFORE" -eq 3 ]] && echo 0 || echo 1)"

# Cancelar únicamente el segundo trabajo (D2)
CANCEL_D2=$(client cancel "$ID_D2" 2>&1)
echo "$CANCEL_D2" > "$RUN_DIR/cancel-D.txt"
check "Cancelación de D2 (Job #$ID_D2) aceptada" \
    "$((grep -qi "cancelad" <<< "$CANCEL_D2" && grep -q "$ID_D2" <<< "$CANCEL_D2") && echo 0 || echo 1)"

# Esperar hasta 5s a que D2 desaparezca y quede Canceled
sleep 1
ST_D2_AFTER=$(job_state "$(client status "$ID_D2" 2>&1)")
ST_D1_AFTER=$(job_state "$(client status "$ID_D1" 2>&1)")
ST_D3_AFTER=$(job_state "$(client status "$ID_D3" 2>&1)")
PROCS_D_AFTER=$(pgrep -f "sleep 3001" 2>/dev/null | grep -c .) || PROCS_D_AFTER=0

{
    echo "status_D1=$ST_D1_AFTER"
    echo "status_D2=$ST_D2_AFTER"
    echo "status_D3=$ST_D3_AFTER"
    echo "procs_after_cancel=$PROCS_D_AFTER"
    echo "pids=$(pgrep -f "sleep 3001" 2>/dev/null | tr '\n' ' ')"
} >> "$RUN_DIR/pids-D.txt"

check "D2 (Job #$ID_D2) pasa a estado Canceled tras cancelación" \
    "$([[ "$ST_D2_AFTER" == "Canceled" ]] && echo 0 || echo 1)"
check "D1 (Job #$ID_D1) permanece en Running tras cancelar D2" \
    "$([[ "$ST_D1_AFTER" == "Running" ]] && echo 0 || echo 1)"
check "D3 (Job #$ID_D3) permanece en Running tras cancelar D2" \
    "$([[ "$ST_D3_AFTER" == "Running" ]] && echo 0 || echo 1)"
check "Quedan exactamente 2 procesos 'sleep 3001' vivos en el SO (encontrados: $PROCS_D_AFTER)" \
    "$([[ "$PROCS_D_AFTER" -eq 2 ]] && echo 0 || echo 1)"

# Limpiar D1 y D3
client cancel "$ID_D1" >/dev/null 2>&1 || true
client cancel "$ID_D3" >/dev/null 2>&1 || true

# Detener el muestreo
rm -f "$SAMPLING_FLAG"
wait "$SAMPLER_PID" 2>/dev/null || true

# ── Resumen de IDs y conteos totales ─────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[6] Verificando unicidad total de los 20 trabajos y consistencia de status" | tee -a "$LOG"

ALL_IDS=("${IDS_A[@]}" "${IDS_B[@]}" "${IDS_C[@]}" "${IDS_D[@]}")
TOTAL_SUBMITTED=${#ALL_IDS[@]}
TOTAL_DISTINCT=$(printf '%s\n' "${ALL_IDS[@]}" | grep -v '^$' | sort -u | grep -c .)

{
    echo "total_submitted=$TOTAL_SUBMITTED"
    echo "total_distinct=$TOTAL_DISTINCT"
    echo "IDs_A=${IDS_A[*]}"
    echo "IDs_B=${IDS_B[*]}"
    echo "IDs_C=${IDS_C[*]}"
    echo "IDs_D=${IDS_D[*]}"
} > "$RUN_DIR/ids.txt"

check "Total de 20 solicitudes generaron 20 IDs únicos (distintos: $TOTAL_DISTINCT)" \
    "$([[ "$TOTAL_SUBMITTED" -eq 20 && "$TOTAL_DISTINCT" -eq 20 ]] && echo 0 || echo 1)"

FINAL_STATUS=$(client status 2>&1)
echo "$FINAL_STATUS" > "$RUN_DIR/final-status.txt"
COUNT_IN_STATUS=$(grep -cE '^Job #[0-9]+:' "$RUN_DIR/final-status.txt" || true)

{
    echo "escenario_A_esperado=5 obtenido=${#IDS_A[@]}"
    echo "escenario_B_esperado=10 obtenido=${#IDS_B[@]}"
    echo "escenario_C_esperado=2 obtenido=${#IDS_C[@]}"
    echo "escenario_D_esperado=3 obtenido=${#IDS_D[@]}"
    echo "total_esperado=20 total_obtenido=$TOTAL_DISTINCT"
    echo "total_en_status=$COUNT_IN_STATUS"
} > "$RUN_DIR/duplicates-summary.txt"

check "El listado de status contiene exactamente 20 trabajos registrados (encontrados: $COUNT_IN_STATUS)" \
    "$([[ "$COUNT_IN_STATUS" -eq 20 ]] && echo 0 || echo 1)"

# Comprobar que ningún ID aparece repetido en status
DUPLICATE_LINES_IN_STATUS=$(grep -oE '^Job #[0-9]+:' "$RUN_DIR/final-status.txt" | sort | uniq -d | grep -c .) || DUPLICATE_LINES_IN_STATUS=0
check "Ningún ID aparece más de una vez en el listado de status (duplicados: $DUPLICATE_LINES_IN_STATUS)" \
    "$([[ "$DUPLICATE_LINES_IN_STATUS" -eq 0 ]] && echo 0 || echo 1)"

# ── Salud del daemon y procesos residuales ───────────────────────────────────
echo "" | tee -a "$LOG"
echo "[7] Verificando salud del daemon y ausencia de procesos residuales / zombis" | tee -a "$LOG"

HEALTH=$(client health 2>&1)
check "Daemon responde a comando health con OK (obtenido: '$HEALTH')" \
    "$(grep -q "OK:" <<< "$HEALTH" && echo 0 || echo 1)"

REM_SLEEP=$(pgrep -f "sleep 3001" 2>/dev/null | tr '\n' ' ')
check "Sin procesos residuales de sleep 3001 en el sistema${REM_SLEEP:+ (PIDs:$REM_SLEEP)}" \
    "$([[ -z "${REM_SLEEP// /}" ]] && echo 0 || echo 1)"

echo "[INFO] File descriptors abiertos por daemon: $(count_open_fds)" | tee -a "$LOG"
check_no_zombies

finish_run
