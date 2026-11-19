#!/bin/bash
# verif/scripts/TC-002.sh
#
# TC-002 — Cola y límite de concurrencia
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-002.sh                       # caso principal (límite 3)
#   TC002_SENSITIVITY=1 bash verif/scripts/TC-002.sh   # verificación de sensibilidad (límite 4)
#
# En la verificación de sensibilidad el daemon se inicia con --max-current 4 y el
# script PASA solo si el muestreo DETECTA que se superó el límite de 3. Si no lo
# detecta, el muestreo no es válido. Sus resultados se guardan en TC-002-sensibilidad/.
#
# Resultados en:
#   verif/results/TC-002/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LIMIT=3                 # límite que exige el TC
QUEUE_CAP=3
JOBS_TOTAL=6
JOB_CMD_ARGS=(sleep 8)
MAX_WAIT_SECS=40
SAMPLE_INTERVAL=0.2

SENSITIVITY="${TC002_SENSITIVITY:-0}"
if [[ "$SENSITIVITY" == "1" ]]; then
    TC_ID="TC-002-sensibilidad"
    DAEMON_MAX_CURRENT=4
else
    TC_ID="TC-002"
    DAEMON_MAX_CURRENT=$LIMIT
fi

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

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "$TC_ID"
start_daemon --max-current "$DAEMON_MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$DAEMON_MAX_CURRENT" "queue_cap=$QUEUE_CAP"

STATUS_SAMPLES="$RUN_DIR/status-samples.log"
PS_SAMPLES="$RUN_DIR/ps-samples.log"
SAMPLING_FLAG="$RUN_DIR/.sampling"
: > "$STATUS_SAMPLES"
: > "$PS_SAMPLES"

# ── Muestreo en segundo plano ────────────────────────────────────────────────
# Cada muestra: una consulta 'status' y un conteo 'pgrep -P <daemon>'.
#   status-samples.log: <ts> running=N queued=N total=N states=ID:Estado,...
#   ps-samples.log:     <ts> children=N
sampler() {
    set +e
    while [[ -f "$SAMPLING_FLAG" ]]; do
        local ts out states running queued total children
        ts=$(date +%s.%N)
        out=$(client status 2>&1)
        states=$(echo "$out" \
            | sed -nE 's/^Job #([0-9]+): .*\[([A-Za-z]+)\].*$/\1:\2/p' \
            | sort -t: -k1,1n | paste -sd, -)
        running=$(echo "$out" | grep -cE '^Job #[0-9]+: .*\[Running\]')
        queued=$(echo "$out"  | grep -cE '^Job #[0-9]+: .*\[Queued\]')
        total=$(echo "$out"   | grep -cE '^Job #[0-9]+:')
        echo "$ts running=$running queued=$queued total=$total states=$states" >> "$STATUS_SAMPLES"

        children=$(pgrep -P "$DAEMON_PID" | wc -l)
        echo "$ts children=$children" >> "$PS_SAMPLES"
        sleep "$SAMPLE_INTERVAL"
    done
}

touch "$SAMPLING_FLAG"
sampler &
SAMPLER_PID=$!

# ── Paso 1: enviar 6 trabajos de forma secuencial ────────────────────────────
echo "" | tee -a "$LOG"
echo "[1] Enviando $JOBS_TOTAL trabajos: ${JOB_CMD_ARGS[*]}" | tee -a "$LOG"

: > "$RUN_DIR/submit.txt"
: > "$RUN_DIR/jobs.txt"
for n in $(seq 1 "$JOBS_TOTAL"); do
    OUT=$(client "${JOB_CMD_ARGS[@]}" 2>&1)
    echo "envio $n: $OUT" | tee -a "$LOG" >> "$RUN_DIR/submit.txt"
    echo "$OUT" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1 >> "$RUN_DIR/jobs.txt"
done

ACCEPTED=$(grep -c . "$RUN_DIR/jobs.txt")
DISTINCT=$(sort -u "$RUN_DIR/jobs.txt" | grep -c .)
check "Los $JOBS_TOTAL envíos fueron aceptados con ID (obtenidos: $ACCEPTED)" \
    "$([[ "$ACCEPTED" -eq "$JOBS_TOTAL" ]] && echo 0 || echo 1)"
check "Los IDs devueltos son distintos (distintos: $DISTINCT)" \
    "$([[ "$DISTINCT" -eq "$JOBS_TOTAL" ]] && echo 0 || echo 1)"

# ── Paso 2: esperar a que todos terminen (máx. MAX_WAIT_SECS) ────────────────
echo "" | tee -a "$LOG"
echo "[2] Esperando estado terminal de los $JOBS_TOTAL trabajos (máx. ${MAX_WAIT_SECS}s)..." | tee -a "$LOG"

SECONDS=0
ALL_DONE=1
while [[ $SECONDS -lt $MAX_WAIT_SECS ]]; do
    FINAL=$(client status 2>&1)
    DONE=$(echo "$FINAL" | grep -cE '^Job #[0-9]+: .*\[(Succeeded|Failed|Canceled|Interrupted|ServiceRestarted)\]')
    if [[ "$DONE" -ge "$JOBS_TOTAL" ]]; then
        ALL_DONE=0
        break
    fi
    sleep 1
done
echo "tiempo_total_s=$SECONDS" >> "$RUN_DIR/concurrency-summary.txt"

# ── Paso 3: detener muestreo y capturar estado final ─────────────────────────
rm -f "$SAMPLING_FLAG"
wait "$SAMPLER_PID" 2>/dev/null || true

FINAL=$(client status 2>&1)
echo "$FINAL" > "$RUN_DIR/final-status.txt"
echo "$FINAL" | tee -a "$LOG"

# ── Paso 4: resumen de concurrencia a partir de las muestras ─────────────────
MAX_RUNNING=$(grep -oE 'running=[0-9]+' "$STATUS_SAMPLES" | cut -d= -f2 | sort -n | tail -1)
MAX_QUEUED=$(grep -oE 'queued=[0-9]+'  "$STATUS_SAMPLES" | cut -d= -f2 | sort -n | tail -1)
MAX_CHILDREN=$(grep -oE 'children=[0-9]+' "$PS_SAMPLES" | cut -d= -f2 | sort -n | tail -1)
N_SAMPLES=$(grep -c . "$STATUS_SAMPLES")
MAX_RUNNING=${MAX_RUNNING:-0}; MAX_QUEUED=${MAX_QUEUED:-0}; MAX_CHILDREN=${MAX_CHILDREN:-0}

# FIFO y no-desaparición de trabajos, calculados sobre cada muestra.
AWK_RESULT=$(awk '
{
    # extraer states=ID:Estado,...
    s = ""
    for (i = 1; i <= NF; i++) if ($i ~ /^states=/) { s = substr($i, 8) }
    delete st
    n = split(s, parts, ",")
    for (i = 1; i <= n; i++) {
        if (parts[i] == "") continue
        split(parts[i], kv, ":")
        st[kv[1]+0] = kv[2]
    }
    # No-desaparición: un ID visto antes debe seguir presente
    for (id in seen) if (!(id in st)) { lost++ ; lostmsg = lostmsg " " id "@muestra" NR }
    for (id in st) seen[id] = 1
    # FIFO: ningún Queued con ID menor si hay un ID mayor que ya no está Queued
    for (a in st) if (st[a] == "Queued")
        for (b in st) if ((b+0) > (a+0) && st[b] != "Queued") { fifo++; fifomsg = fifomsg " Job" a "Queued/Job" b st[b] "@muestra" NR; break }
}
END {
    printf "lost=%d lostmsg=[%s] fifo_violations=%d fifomsg=[%s]\n", lost+0, lostmsg, fifo+0, fifomsg
}' "$STATUS_SAMPLES")
LOST=$(echo "$AWK_RESULT" | grep -oE 'lost=[0-9]+' | cut -d= -f2)
FIFO_V=$(echo "$AWK_RESULT" | grep -oE 'fifo_violations=[0-9]+' | cut -d= -f2)

{
    echo "limite_exigido=$LIMIT"
    echo "max_current_daemon=$DAEMON_MAX_CURRENT"
    echo "queue_cap_daemon=$QUEUE_CAP"
    echo "muestras=$N_SAMPLES"
    echo "max_running_status=$MAX_RUNNING"
    echo "max_queued_status=$MAX_QUEUED"
    echo "max_procesos_hijos_pgrep=$MAX_CHILDREN"
    echo "trabajos_desaparecidos=$LOST"
    echo "violaciones_fifo=$FIFO_V"
    echo "detalle=$AWK_RESULT"
} >> "$RUN_DIR/concurrency-summary.txt"
echo "" | tee -a "$LOG"
echo "[3] Resumen de concurrencia:" | tee -a "$LOG"
cat "$RUN_DIR/concurrency-summary.txt" | tee -a "$LOG"

# ── Paso 5: evaluación ───────────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[4] Evaluación" | tee -a "$LOG"

if [[ "$SENSITIVITY" == "1" ]]; then
    # Caso negativo: el muestreo DEBE detectar que se superó el límite de 3.
    check "Sensibilidad: el muestreo detecta más de $LIMIT Running (máx. status=$MAX_RUNNING)" \
        "$([[ "$MAX_RUNNING" -gt "$LIMIT" ]] && echo 0 || echo 1)"
    check "Sensibilidad: el muestreo detecta más de $LIMIT procesos hijos (máx. pgrep=$MAX_CHILDREN)" \
        "$([[ "$MAX_CHILDREN" -gt "$LIMIT" ]] && echo 0 || echo 1)"
else
    check "Máximo de Running por status es exactamente $LIMIT (obtenido: $MAX_RUNNING)" \
        "$([[ "$MAX_RUNNING" -eq "$LIMIT" ]] && echo 0 || echo 1)"
    check "Máximo de procesos hijos por pgrep es exactamente $LIMIT (obtenido: $MAX_CHILDREN)" \
        "$([[ "$MAX_CHILDREN" -eq "$LIMIT" ]] && echo 0 || echo 1)"
    check "Hubo $QUEUE_CAP trabajos Queued en alguna muestra (máx. Queued: $MAX_QUEUED)" \
        "$([[ "$MAX_QUEUED" -eq "$QUEUE_CAP" ]] && echo 0 || echo 1)"
    check "Orden FIFO en todas las muestras (violaciones: $FIFO_V)" \
        "$([[ "$FIFO_V" -eq 0 ]] && echo 0 || echo 1)"
    check "Ningún trabajo aceptado desapareció del listado (desaparecidos: $LOST)" \
        "$([[ "$LOST" -eq 0 ]] && echo 0 || echo 1)"
    check "Los $JOBS_TOTAL trabajos terminaron dentro de ${MAX_WAIT_SECS}s" "$ALL_DONE"

    SUCCEEDED=$(echo "$FINAL" | grep -cE '^Job #[0-9]+: .*\[Succeeded\] \(exit code: 0\)')
    check "Los $JOBS_TOTAL trabajos terminaron en Succeeded con exit code 0 (obtenidos: $SUCCEEDED)" \
        "$([[ "$SUCCEEDED" -eq "$JOBS_TOTAL" ]] && echo 0 || echo 1)"
fi

# ── Procesos residuales (antes de detener el daemon) ─────────────────────────
echo "" | tee -a "$LOG"
echo "[INFO] File descriptors abiertos por daemon: $(count_open_fds)" | tee -a "$LOG"
sleep 1
check_no_zombies

finish_run
