#!/bin/bash
# verif/scripts/TC-017.sh
#
# TC-017 — Cancelaciones concurrentes
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-017.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RF-26: Respuestas coherentes ante cancelaciones simultáneas del mismo trabajo.
#   - RNF-27: Estado final único (Canceled), sin regresiones ni estados imposibles.
#
# Resultados en:
#   verif/results/TC-017/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=4
QUEUE_CAP=10
SAMPLE_INTERVAL=0.1
OBSERVE_SECS=2
CLIENT_TIMEOUT=10

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-017"
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

submit() {
    local name="$1"; shift
    local out id
    out=$(client "$@" 2>&1)
    id=$(grep -oE 'Job #[0-9]+ encolado' <<< "$out" | grep -oE '[0-9]+' | head -1)
    echo "$id"
}

: > "$RUN_DIR/iterations.txt"
: > "$RUN_DIR/responses-summary.txt"
: > "$RUN_DIR/iterations-summary.txt"
: > "$RUN_DIR/pids.txt"

TOTAL_ITERATIONS=25
PASSED_ITERATIONS=0
FAILED_ITERATIONS=0

# Configuración de los 3 grupos (G1: 10 con 2 clientes sobre Running, G2: 10 con 2 sobre Queued, G3: 5 con 5 sobre Running)
declare -a G_NAMES=("G1" "G1" "G1" "G1" "G1" "G1" "G1" "G1" "G1" "G1" \
                    "G2" "G2" "G2" "G2" "G2" "G2" "G2" "G2" "G2" "G2" \
                    "G3" "G3" "G3" "G3" "G3")
declare -a G_STATES=("Running" "Running" "Running" "Running" "Running" "Running" "Running" "Running" "Running" "Running" \
                     "Queued" "Queued" "Queued" "Queued" "Queued" "Queued" "Queued" "Queued" "Queued" "Queued" \
                     "Running" "Running" "Running" "Running" "Running")
declare -a G_CLIENTS=(2 2 2 2 2 2 2 2 2 2 \
                      2 2 2 2 2 2 2 2 2 2 \
                      5 5 5 5 5)

echo "" | tee -a "$LOG"
echo "[INFO] Iniciando 25 iteraciones de cancelaciones concurrentes" | tee -a "$LOG"

for idx in $(seq 0 24); do
    i=$((idx + 1))
    GROUP="${G_NAMES[$idx]}"
    TARGET_STATE="${G_STATES[$idx]}"
    NUM_CLIENTS="${G_CLIENTS[$idx]}"
    MARKER="sleep 10$(printf '%02d' "$i")"

    echo "" | tee -a "$LOG"
    echo "── Iteración $i/25 [$GROUP: $TARGET_STATE, $NUM_CLIENTS clientes, comando: '$MARKER'] ──" | tee -a "$LOG"

    FILLER_IDS=()
    if [[ "$TARGET_STATE" == "Queued" ]]; then
        # Llenar las 4 ranuras activas para forzar que el siguiente quede en Queued
        for f in 1 2 3 4; do
            FID=$(submit "fill_${i}_${f}" sleep 2000)
            FILLER_IDS+=("$FID")
        done
        # Breve pausa para asegurar que los de relleno entren a Running
        sleep 0.3
    fi

    # Enviar trabajo objetivo
    TARGET_ID=$(submit "target_$i" $MARKER)
    echo "iter=$i group=$GROUP target_state=$TARGET_STATE clients=$NUM_CLIENTS id=$TARGET_ID cmd='$MARKER'" >> "$RUN_DIR/iterations.txt"

    if [[ -z "$TARGET_ID" ]]; then
        echo "[FAIL] Iteración $i: No se pudo encolar el trabajo objetivo." | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_ITERATIONS=$((FAILED_ITERATIONS + 1))
        echo "iter_$i: FAIL (no encolado)" >> "$RUN_DIR/iterations-summary.txt"
        continue
    fi

    # Esperar al estado esperado antes de cancelar
    wait_job_state "$TARGET_ID" "$TARGET_STATE" 5
    ACTUAL_STATE=$(job_state "$(client status "$TARGET_ID" 2>&1)")

    if [[ "$ACTUAL_STATE" != "$TARGET_STATE" ]]; then
        echo "[FAIL] Iteración $i: El trabajo #$TARGET_ID no alcanzó el estado $TARGET_STATE (obtenido: '$ACTUAL_STATE')." | tee -a "$LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_ITERATIONS=$((FAILED_ITERATIONS + 1))
        echo "iter_$i: FAIL (estado previo incorrecto: $ACTUAL_STATE != $TARGET_STATE)" >> "$RUN_DIR/iterations-summary.txt"
        continue
    fi

    # Registrar PIDs del trabajo si estaba corriendo
    if [[ "$TARGET_STATE" == "Running" ]]; then
        PIDS_BEFORE=$(pgrep -f "$MARKER" 2>/dev/null || true)
        echo "iter_$i: pids_before=$PIDS_BEFORE" >> "$RUN_DIR/pids.txt"
    fi

    # Lanzar K clientes concurrentes para cancelar el mismo TARGET_ID
    CANCEL_PIDS=()
    for (( c=1; c<=NUM_CLIENTS; c++ )); do
        (
            OUT=$(client cancel "$TARGET_ID" 2>&1)
            RC=$?
            echo "$OUT" > "$RUN_DIR/cancel-${i}-${c}.txt"
            echo "exit_code=$RC" >> "$RUN_DIR/cancel-${i}-${c}.txt"
        ) &
        CANCEL_PIDS+=($!)
    done

    # Esperar que terminen todos los clientes
    for c_pid in "${CANCEL_PIDS[@]}"; do
        wait "$c_pid" 2>/dev/null || true
    done

    # Clasificar respuestas de los clientes
    COUNT_INITIATED=0
    COUNT_IN_PROGRESS=0
    COUNT_ALREADY=0
    COUNT_OTHER=0
    CLIENT_OUTPUTS=()

    for (( c=1; c<=NUM_CLIENTS; c++ )); do
        OUT_TXT=$(cat "$RUN_DIR/cancel-${i}-${c}.txt" 2>/dev/null || echo "")
        CLIENT_OUTPUTS+=("c$c: $OUT_TXT")

        if grep -qiE "cancelad[oa] correctamente|cancelaci[oó]n iniciada" <<< "$OUT_TXT" && ! grep -qiE "ya.*cancelad|en curso|en progreso" <<< "$OUT_TXT"; then
            COUNT_INITIATED=$((COUNT_INITIATED + 1))
        elif grep -qiE "en curso|en progreso|in progress" <<< "$OUT_TXT"; then
            COUNT_IN_PROGRESS=$((COUNT_IN_PROGRESS + 1))
        elif grep -qiE "ya.*cancelad|anteriormente.*cancelad|already canceled" <<< "$OUT_TXT"; then
            COUNT_ALREADY=$((COUNT_ALREADY + 1))
        else
            COUNT_OTHER=$((COUNT_OTHER + 1))
        fi
    done

    {
        echo "iter=$i target_id=$TARGET_ID clients=$NUM_CLIENTS"
        echo "  initiated=$COUNT_INITIATED in_progress=$COUNT_IN_PROGRESS already=$COUNT_ALREADY other=$COUNT_OTHER"
        for out_line in "${CLIENT_OUTPUTS[@]}"; do
            echo "  $out_line"
        done
    } >> "$RUN_DIR/responses-summary.txt"

    # Verificar criterios RF-26
    ITER_OK=1

    # Exactamente 1 cliente debe recibir la confirmación de cancelación iniciada
    if [[ "$COUNT_INITIATED" -ne 1 ]]; then
        echo "[FAIL] Iteración $i: Se esperaba exactamente 1 cliente con cancelación iniciada (obtenido: $COUNT_INITIATED)." | tee -a "$LOG"
        ITER_OK=0
    fi

    # Los demás deben ser en curso o ya cancelado, y no 'other' (genérico/error no descriptivo)
    if [[ "$COUNT_OTHER" -gt 0 ]]; then
        echo "[FAIL] Iteración $i: $COUNT_OTHER cliente(s) recibieron respuesta no conforme (otra / genérica / sin ID)." | tee -a "$LOG"
        ITER_OK=0
    fi

    # Si estaba en Running, verificar que el proceso desaparezca en 5 s
    if [[ "$TARGET_STATE" == "Running" ]]; then
        PROCS_DEAD=0
        for (( s=1; s<=10; s++ )); do
            REMAIN=$(pgrep -f "$MARKER" 2>/dev/null | grep -c .) || REMAIN=0
            if [[ "$REMAIN" -eq 0 ]]; then
                PROCS_DEAD=1
                break
            fi
            sleep 0.5
        done
        echo "iter_$i: procs_dead=$PROCS_DEAD remaining=$REMAIN" >> "$RUN_DIR/pids.txt"
        if [[ "$PROCS_DEAD" -ne 1 ]]; then
            echo "[FAIL] Iteración $i: El proceso de '$MARKER' sigue vivo tras cancelar." | tee -a "$LOG"
            ITER_OK=0
        fi
    fi

    # Si había trabajos de relleno, cancelarlos para limpiar
    if [[ ${#FILLER_IDS[@]} -gt 0 ]]; then
        for fid in "${FILLER_IDS[@]}"; do
            client cancel "$fid" >/dev/null 2>&1 || true
        done
        # Esperar que los procesos de relleno mueran
        for (( s=1; s<=6; s++ )); do
            FILL_RUNNING=$(pgrep -f "sleep 2000" 2>/dev/null | grep -c .) || FILL_RUNNING=0
            [[ "$FILL_RUNNING" -eq 0 ]] && break
            sleep 0.5
        done
    fi

    # Muestreo y estado final del trabajo objetivo
    sleep "$OBSERVE_SECS"
    FINAL_TARGET=$(client status "$TARGET_ID" 2>&1)
    echo "$FINAL_TARGET" > "$RUN_DIR/final-${i}.txt"
    FINAL_STATE=$(job_state "$FINAL_TARGET")

    if [[ "$FINAL_STATE" != "Canceled" ]]; then
        echo "[FAIL] Iteración $i: Estado final de #$TARGET_ID es '$FINAL_STATE' (se esperaba Canceled)." | tee -a "$LOG"
        ITER_OK=0
    fi

    # Verificar que aparece exactamente 1 vez en el listado
    FULL_STATUS=$(client status 2>&1)
    ID_OCCURRENCES=$(grep -cE "^Job #${TARGET_ID}:" <<< "$FULL_STATUS" || true)
    if [[ "$ID_OCCURRENCES" -ne 1 ]]; then
        echo "[FAIL] Iteración $i: Job #$TARGET_ID aparece $ID_OCCURRENCES veces en status (esperado: 1)." | tee -a "$LOG"
        ITER_OK=0
    fi

    if [[ "$ITER_OK" -eq 1 ]]; then
        echo "[PASS] Iteración $i [$GROUP]: Cancelación concurrente correcta (1 iniciada, $((NUM_CLIENTS - 1)) en curso/ya cancelado, estado final Canceled)." | tee -a "$LOG"
        PASS_COUNT=$((PASS_COUNT + 1))
        PASSED_ITERATIONS=$((PASSED_ITERATIONS + 1))
        echo "iter_$i: PASS" >> "$RUN_DIR/iterations-summary.txt"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_ITERATIONS=$((FAILED_ITERATIONS + 1))
        echo "iter_$i: FAIL" >> "$RUN_DIR/iterations-summary.txt"
    fi
done

# Detener sampler
rm -f "$SAMPLING_FLAG"
wait "$SAMPLER_PID" 2>/dev/null || true

# ── Verificaciones globales ──────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[INFO] Resumen de iteraciones: $PASSED_ITERATIONS/$TOTAL_ITERATIONS aprobadas" | tee -a "$LOG"
check "Las 25 iteraciones de cancelaciones concurrentes fueron exitosas" \
    "$([[ "$PASSED_ITERATIONS" -eq 25 ]] && echo 0 || echo 1)"

# Salud del daemon
HEALTH=$(client health 2>&1)
check "Daemon responde a comando health con OK tras las 25 iteraciones" \
    "$(grep -q "OK:" <<< "$HEALTH" && echo 0 || echo 1)"

# Sin procesos residuales de pruebas
REM_TEST_PROCS=$(pgrep -f "sleep 10" 2>/dev/null | tr '\n' ' ')
check "Sin procesos residuales de sleep 10XX en el sistema${REM_TEST_PROCS:+ (PIDs:$REM_TEST_PROCS)}" \
    "$([[ -z "${REM_TEST_PROCS// /}" ]] && echo 0 || echo 1)"

echo "[INFO] File descriptors abiertos por daemon: $(count_open_fds)" | tee -a "$LOG"
check_no_zombies

finish_run
