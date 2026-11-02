#!/bin/bash
# verif/scripts/TC-003.sh
#
# TC-003 — Estados y tiempos de un trabajo
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-003.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Parte A (RF-06, estados): se evalúa siempre.
# Parte B (RF-07, tiempos): si `status <id>` no expone ningún tiempo, esa parte
# queda BLOCKED (falta A2-07). No se da PASS ni FAIL por algo que no se pudo probar.
#
# Resultados en:
#   verif/results/TC-003/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=1          # un solo trabajo a la vez: A, B y C se ejecutan en serie
QUEUE_CAP=3
SAMPLE_INTERVAL=0.1
MAX_WAIT_SECS=30

# Etiquetas esperadas en `status <id>` para los tiempos (contrato provisional
# del TC-003.md, sección 6). Si A2-07 adopta otros nombres, se ajustan aquí.
LBL_RECV='received|recibido|recepci'
LBL_START='started|iniciado|inicio'
LBL_FIN='finished|terminado|terminaci|finalizado'

# Trabajos de prueba (comando completo tal como se envía al cliente)
CMD_A=(sleep 3)                 # Succeeded, exit 0
CMD_B=(sleep 2)                 # Succeeded, exit 0, espera en cola a que termine A
CMD_C=(timeout 1 sleep 5)       # Failed, exit 124 (convención de timeout)
CMD_D=(sleep 1)                 # se cancela estando en cola -> Canceled

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-003"
start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$MAX_CURRENT" "queue_cap=$QUEUE_CAP"

STATUS_SAMPLES="$RUN_DIR/status-samples.log"
SAMPLING_FLAG="$RUN_DIR/.sampling"
: > "$STATUS_SAMPLES"

# ── Muestreo en segundo plano ────────────────────────────────────────────────
# Cada muestra: <ts> states=ID:Estado,...   (Failed(124) se registra como Failed)
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

T_START=$(date +%s.%N)
touch "$SAMPLING_FLAG"
sampler &
SAMPLER_PID=$!

# ── Paso 1: enviar A, B, C y D ───────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[1] Enviando A='${CMD_A[*]}' B='${CMD_B[*]}' C='${CMD_C[*]}' D='${CMD_D[*]}'" | tee -a "$LOG"

submit() {   # submit <nombre> <cmd...>  -> imprime el ID
    local name="$1"; shift
    local out id
    out=$(client "$@" 2>&1)
    echo "$name: $* -> $out" | tee -a "$LOG" >> "$RUN_DIR/submit.txt"
    id=$(grep -oE 'Job #[0-9]+ encolado' <<< "$out" | grep -oE '[0-9]+' | head -1)
    echo "$id"
}
: > "$RUN_DIR/submit.txt"
ID_A=$(submit A "${CMD_A[@]}")
ID_B=$(submit B "${CMD_B[@]}")
ID_C=$(submit C "${CMD_C[@]}")
ID_D=$(submit D "${CMD_D[@]}")
{ echo "A=$ID_A"; echo "B=$ID_B"; echo "C=$ID_C"; echo "D=$ID_D"; } > "$RUN_DIR/jobs.txt"

ALL_IDS="$ID_A$ID_B$ID_C$ID_D"
DISTINCT=$(printf '%s\n' "$ID_A" "$ID_B" "$ID_C" "$ID_D" | grep -v '^$' | sort -u | grep -c .)
check "Los 4 envíos fueron aceptados con ID distinto (distintos: $DISTINCT)" \
    "$([[ "$DISTINCT" -eq 4 ]] && echo 0 || echo 1)"
if [[ "$DISTINCT" -ne 4 ]]; then
    echo "[ERROR] Sin los 4 IDs no se puede continuar." | tee -a "$LOG"
    rm -f "$SAMPLING_FLAG"; wait "$SAMPLER_PID" 2>/dev/null || true
    finish_run
fi

# ── Paso 2: instantáneas mientras A corre y B espera ─────────────────────────
echo "" | tee -a "$LOG"
echo "[2] Instantáneas: A debe estar Running y B Queued" | tee -a "$LOG"
sleep 0.5
SNAP_A=$(client status "$ID_A" 2>&1); echo "$SNAP_A" | tee "$RUN_DIR/snapshot-A-running.txt" >> "$LOG"
SNAP_B=$(client status "$ID_B" 2>&1); echo "$SNAP_B" | tee "$RUN_DIR/snapshot-B-queued.txt" >> "$LOG"
check "A está en Running mientras ejecuta (obtenido: '$(job_state "$SNAP_A")')" \
    "$([[ "$(job_state "$SNAP_A")" == "Running" ]] && echo 0 || echo 1)"
check "B está en Queued mientras A ocupa la única ranura (obtenido: '$(job_state "$SNAP_B")')" \
    "$([[ "$(job_state "$SNAP_B")" == "Queued" ]] && echo 0 || echo 1)"

# ── Paso 3: cancelar D estando en cola ───────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[3] Cancelando D (Job #$ID_D) mientras está en cola" | tee -a "$LOG"
CANCEL_D=$(client cancel "$ID_D" 2>&1)
echo "$CANCEL_D" | tee "$RUN_DIR/cancel-D.txt" >> "$LOG"

# ── Paso 4: esperar a que A, B y C terminen ──────────────────────────────────
echo "" | tee -a "$LOG"
echo "[4] Esperando estado terminal de A, B y C (máx. ${MAX_WAIT_SECS}s)" | tee -a "$LOG"
ALL_DONE=0
SECONDS=0
while [[ $SECONDS -lt $MAX_WAIT_SECS ]]; do
    DONE=0
    for id in "$ID_A" "$ID_B" "$ID_C"; do
        case "$(job_state "$(client status "$id" 2>&1)")" in
            Succeeded|Failed|Canceled|Interrupted) DONE=$((DONE + 1)) ;;
        esac
    done
    if [[ "$DONE" -eq 3 ]]; then ALL_DONE=1; break; fi
    sleep 0.5
done
T_END=$(date +%s.%N)
sleep 0.5
rm -f "$SAMPLING_FLAG"
wait "$SAMPLER_PID" 2>/dev/null || true
check "A, B y C llegaron a un estado terminal en ${SECONDS}s" "$([[ "$ALL_DONE" -eq 1 ]] && echo 0 || echo 1)"

FA=$(client status "$ID_A" 2>&1); FB=$(client status "$ID_B" 2>&1)
FC=$(client status "$ID_C" 2>&1); FD=$(client status "$ID_D" 2>&1)
{ echo "$FA"; echo "$FB"; echo "$FC"; echo "$FD"; } | tee "$RUN_DIR/final-status.txt" >> "$LOG"

# ══ PARTE A — RF-06: estados ═════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "[5] Parte A (RF-06): secuencia de estados observada" | tee -a "$LOG"

# Secuencia de estados distintos por trabajo, regresiones y máximo de Running simultáneos.
# Rangos: Queued=0, Running=1, terminal=2. Una bajada de rango o un cambio entre
# estados terminales es un estado imposible.
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

check_seq() {   # check_seq <nombre> <id> <regex permitido> <descripción>
    local seq bad
    seq=$(seq_of "$2"); bad=$(bad_of "$2")
    check "$1: secuencia '$seq' cumple $4" "$([[ "$seq" =~ $3 ]] && echo 0 || echo 1)"
    check "$1: sin regresiones ni cambios entre estados terminales${bad:+ (detectado:$bad)}" \
        "$([[ -z "${bad// /}" ]] && echo 0 || echo 1)"
}
check_seq "A" "$ID_A" '^(Queued>)?Running>Succeeded$' "[Queued>]Running>Succeeded"
check_seq "B" "$ID_B" '^Queued>Running>Succeeded$'    "Queued>Running>Succeeded"
check_seq "C" "$ID_C" '^Queued>Running>Failed$'       "Queued>Running>Failed"
check_seq "D" "$ID_D" '^Queued>Canceled$'             "Queued>Canceled"

MAXRUN=$(sed -nE 's/^MAXRUN ([0-9]+)$/\1/p' "$RUN_DIR/state-sequences.txt")
check "Con límite $MAX_CURRENT nunca hubo más de $MAX_CURRENT Running (máx. observado: ${MAXRUN:-?})" \
    "$([[ "${MAXRUN:-99}" -le "$MAX_CURRENT" ]] && echo 0 || echo 1)"

# Códigos de salida (RF-07, parte "código de salida"): no dependen de A2-07
check "A terminó con exit code 0"   "$(grep -q 'exit code: 0'   <<< "$FA" && echo 0 || echo 1)"
check "B terminó con exit code 0"   "$(grep -q 'exit code: 0'   <<< "$FB" && echo 0 || echo 1)"
check "C terminó con exit code 124" "$(grep -q 'exit code: 124' <<< "$FC" && echo 0 || echo 1)"
check "D (cancelado) respondió 'cancelado correctamente'" \
    "$(grep -q 'cancelado correctamente' <<< "$CANCEL_D" && echo 0 || echo 1)"

# ══ PARTE B — RF-07: tiempos ═════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "[6] Parte B (RF-07): tiempos de recepción, inicio y terminación" | tee -a "$LOG"

times_of() {   # times_of <texto>  -> deja TS_R, TS_S, TS_F (epoch en segundos)
    TS_R=$(to_epoch "$(ts_field "$1" "$LBL_RECV")")
    TS_S=$(to_epoch "$(ts_field "$1" "$LBL_START")")
    TS_F=$(to_epoch "$(ts_field "$1" "$LBL_FIN")")
}
times_of "$FA";     A_R=$TS_R; A_S=$TS_S; A_F=$TS_F
times_of "$FB";     B_R=$TS_R; B_S=$TS_S; B_F=$TS_F
times_of "$FC";     C_R=$TS_R; C_S=$TS_S; C_F=$TS_F
times_of "$SNAP_B"; QB_R=$TS_R; QB_S=$TS_S; QB_F=$TS_F
times_of "$SNAP_A"; RA_R=$TS_R; RA_S=$TS_S; RA_F=$TS_F
{
    echo "ventana_prueba: inicio=$T_START fin=$T_END"
    echo "A: received=$A_R started=$A_S finished=$A_F"
    echo "B: received=$B_R started=$B_S finished=$B_F"
    echo "C: received=$C_R started=$C_S finished=$C_F"
    echo "B en cola:  received=$QB_R started=$QB_S finished=$QB_F"
    echo "A corriendo: received=$RA_R started=$RA_S finished=$RA_F"
} > "$RUN_DIR/times.txt"
cat "$RUN_DIR/times.txt" | tee -a "$LOG"

sub()  { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f", a-b}'; }
ge()   { num_le "$2" "$1"; }                       # ge a b  -> a >= b
rc()   { "$@" && echo 0 || echo 1; }

if [[ -z "$A_R$A_S$A_F$B_R$B_S$B_F$C_R$C_S$C_F" ]]; then
    block "RF-07: 'status <id>' no expone ningún tiempo (received/started/finished). Falta A2-07; la parte B no se evaluó."
else
    LO=$(sub "$T_START" 2); HI=$(awk -v t="$T_END" 'BEGIN{printf "%.3f", t+2}')
    for j in A B C; do
        eval "R=\$${j}_R S=\$${j}_S F=\$${j}_F"
        check "$j: expone received, started y finished" \
            "$([[ -n "$R" && -n "$S" && -n "$F" ]] && echo 0 || echo 1)"
        check "$j: received <= started <= finished" \
            "$(num_le "$R" "$S" && num_le "$S" "$F" && echo 0 || echo 1)"
        check "$j: los tiempos caen dentro de la ventana real de la prueba (±2 s)" \
            "$(num_le "$LO" "$R" && num_le "$F" "$HI" && echo 0 || echo 1)"
    done
    check "A: duración (finished-started) >= 2.5 s para sleep 3 (obtenida: $(sub "$A_F" "$A_S"))" \
        "$(rc ge "$(sub "$A_F" "$A_S")" 2.5)"
    check "B: esperó en cola >= 2.0 s (started-received: $(sub "$B_S" "$B_R"))" \
        "$(rc ge "$(sub "$B_S" "$B_R")" 2.0)"
    check "B inició después de que terminó A (ranura única)" \
        "$(num_le "$(sub "$A_F" 0.2)" "$B_S" && echo 0 || echo 1)"
    check "C inició después de que terminó B (ranura única)" \
        "$(num_le "$(sub "$B_F" 0.2)" "$C_S" && echo 0 || echo 1)"
    check "En Queued: received presente; started y finished ausentes" \
        "$([[ -n "$QB_R" && -z "$QB_S" && -z "$QB_F" ]] && echo 0 || echo 1)"
    check "En Running: received y started presentes; finished ausente" \
        "$([[ -n "$RA_R" && -n "$RA_S" && -z "$RA_F" ]] && echo 0 || echo 1)"
fi

# ── Procesos residuales (antes de detener el daemon) ─────────────────────────
echo "" | tee -a "$LOG"
echo "[INFO] File descriptors abiertos por daemon: $(count_open_fds)" | tee -a "$LOG"
sleep 1
check_no_zombies

finish_run
