#!/bin/bash
# verif/scripts/TC-004.sh
#
# TC-004 — Consultar y listar trabajos (PROVISIONAL)
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-004.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Partes:
#   A. Consulta por ID           (RF-08)
#   B. Listado                   (RF-09)
#   C. Filtro por estado         (RF-09)  -> BLOCKED si el daemon no lo soporta (A2-07)
#   D. Tiempo de respuesta       (RNF-05) con al menos 100 trabajos almacenados
#
# PROVISIONAL: la sintaxis del filtro no está definida en los requisitos ni en
# los ADR. Se fija en FILTER_FMT y en TC-004.md (sección 6). Si A2-07 adopta otra,
# se cambia solo esa variable.
#
# Resultados en:
#   verif/results/TC-004/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=1          # ejecución en serie: permite tener Queued y Running a la vez
QUEUE_CAP=100          # evita rechazos al cargar 100 trabajos
LOAD_JOBS=100          # trabajos de carga para RNF-05
REPS=10                # mediciones por tipo de consulta
MAX_QUERY_SECS=1.0     # RNF-05
LOAD_WAIT_SECS=90

FILTER_FMT='status --state %s'      # sintaxis provisional del filtro por estado
STATES=(Queued Running Succeeded Failed Canceled)

CMD_S=(echo hola)                   # Succeeded, exit 0
CMD_F=(false)                       # Failed, exit 1
CMD_R=(sleep 8)                     # Running durante las consultas
CMD_Q1=(echo en-cola-1)             # Queued
CMD_Q2=(echo en-cola-2)             # Queued
CMD_X=(echo cancelar)               # Canceled (se cancela en cola)

# ── Utilidades ────────────────────────────────────────────────────────────────

# Pares "ID Estado" de cada línea "Job #N: ... [Estado]" (Failed(1) -> Failed)
job_pairs() { sed -nE 's/^Job #([0-9]+): .*\[([A-Za-z]+)(\([-0-9]+\))?\].*$/\1 \2/p' <<< "$1"; }
all_ids()   { job_pairs "$1" | awk '{print $1}' | sort -n; }
ids_in_state() { job_pairs "$1" | awk -v s="$2" '$2 == s {print $1}' | sort -n | paste -sd, -; }
state_of_id()  { job_pairs "$1" | awk -v i="$2" '$1 == i {print $2; exit}'; }

# Envía un trabajo e imprime su ID (vacío si fue rechazado)
submit() {
    local name="$1"; shift
    local out id
    out=$(client "$@" 2>&1)
    echo "$name: $* -> $out" | tee -a "$LOG" >> "$RUN_DIR/submit.txt"
    id=$(grep -oE 'Job #[0-9]+ encolado' <<< "$out" | grep -oE '[0-9]+' | head -1)
    echo "$id"
}

# Espera a que <id> esté en un estado terminal
wait_terminal() {
    local id="$1" secs="${2:-20}" i=0
    while [[ $i -lt $secs ]]; do
        case "$(job_state "$(client status "$id" 2>&1)")" in
            Succeeded|Failed|Canceled|Interrupted) return 0 ;;
        esac
        sleep 1; i=$((i + 1))
    done
    return 1
}

# Mide el tiempo de una consulta. Deja la salida en OUT y los segundos en ELAPSED.
OUT=""; ELAPSED=0
time_cmd() {
    local t0 t1
    t0=$(date +%s.%N)
    OUT=$(timeout 10 "$CLIENT_BIN" --socket "$SOCKET" "$@" 2>&1)
    t1=$(date +%s.%N)
    ELAPSED=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b-a}')
}

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-004"
start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$MAX_CURRENT" "queue_cap=$QUEUE_CAP"

: > "$RUN_DIR/submit.txt"

# ── Preparación: un trabajo en cada estado ───────────────────────────────────
echo "" | tee -a "$LOG"
echo "[1] Preparando trabajos en estados Succeeded, Failed, Running, Queued y Canceled" | tee -a "$LOG"

ID_S=$(submit S "${CMD_S[@]}")
ID_F=$(submit F "${CMD_F[@]}")
wait_terminal "$ID_S" 10; wait_terminal "$ID_F" 10

ID_R=$(submit R "${CMD_R[@]}")
ID_Q1=$(submit Q1 "${CMD_Q1[@]}")
ID_Q2=$(submit Q2 "${CMD_Q2[@]}")
ID_X=$(submit X "${CMD_X[@]}")
CANCEL_X=$(client cancel "$ID_X" 2>&1)
echo "$CANCEL_X" > "$RUN_DIR/cancel-X.txt"
wait_job_state "$ID_R" "\[Running\]" 5 >/dev/null

{ echo "S=$ID_S"; echo "F=$ID_F"; echo "R=$ID_R"; echo "Q1=$ID_Q1"; echo "Q2=$ID_Q2"; echo "X=$ID_X"; } > "$RUN_DIR/jobs.txt"
DISTINCT=$(printf '%s\n' "$ID_S" "$ID_F" "$ID_R" "$ID_Q1" "$ID_Q2" "$ID_X" | grep -v '^$' | sort -u | grep -c .)
check "Los 6 trabajos de preparación fueron aceptados con ID distinto (distintos: $DISTINCT)" \
    "$([[ "$DISTINCT" -eq 6 ]] && echo 0 || echo 1)"
if [[ "$DISTINCT" -ne 6 ]]; then
    echo "[ERROR] Sin los 6 IDs no se puede continuar." | tee -a "$LOG"
    finish_run
fi

# Instantánea del sistema (la usan las partes A, B y C)
sleep 0.5
LIST=$(client status 2>&1);  echo "$LIST"  > "$RUN_DIR/list-status.txt"
LIST2=$(client list 2>&1);   echo "$LIST2" > "$RUN_DIR/list-list.txt"

# ══ PARTE A — RF-08: consulta por ID ═════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "[2] Parte A (RF-08): consulta por ID" | tee -a "$LOG"

declare -A EXPECT=( [S]=Succeeded [F]=Failed [R]=Running [Q1]=Queued [Q2]=Queued [X]=Canceled )
declare -A IDOF=( [S]=$ID_S [F]=$ID_F [R]=$ID_R [Q1]=$ID_Q1 [Q2]=$ID_Q2 [X]=$ID_X )
: > "$RUN_DIR/query-by-id.txt"
for k in S F R Q1 Q2 X; do
    id="${IDOF[$k]}"
    time_cmd status "$id"
    { echo "--- $k (Job #$id) t=${ELAPSED}s"; echo "$OUT"; } >> "$RUN_DIR/query-by-id.txt"
    check "status $id responde con el ID consultado (Job #$id)" \
        "$(grep -q "^Job #$id:" <<< "$OUT" && echo 0 || echo 1)"
    check "status $id muestra el comando enviado" \
        "$(grep -qE "^Job #$id: (echo|false|sleep)" <<< "$OUT" && echo 0 || echo 1)"
    check "status $id muestra el estado ${EXPECT[$k]} (obtenido: '$(job_state "$OUT")')" \
        "$([[ "$(job_state "$OUT")" == "${EXPECT[$k]}" ]] && echo 0 || echo 1)"
done
OUT_S=$(client status "$ID_S" 2>&1); OUT_F=$(client status "$ID_F" 2>&1)
check "El trabajo exitoso muestra 'exit code: 0'" "$(grep -q 'exit code: 0' <<< "$OUT_S" && echo 0 || echo 1)"
check "El trabajo fallido muestra 'exit code: 1'" "$(grep -q 'exit code: 1' <<< "$OUT_F" && echo 0 || echo 1)"

MISSING=$((ID_X + 9999))
time_cmd status "$MISSING"
echo "--- inexistente (Job #$MISSING) t=${ELAPSED}s"$'\n'"$OUT" > "$RUN_DIR/query-missing.txt"
check "ID inexistente: respuesta explícita 'no encontrado'" \
    "$(grep -qiE 'no encontrado|no existe' <<< "$OUT" && echo 0 || echo 1)"
check "ID inexistente: el mensaje incluye el ID consultado" \
    "$(grep -q "$MISSING" <<< "$OUT" && echo 0 || echo 1)"
time_cmd status abc
echo "--- ID no numérico t=${ELAPSED}s"$'\n'"$OUT" > "$RUN_DIR/query-invalid.txt"
check "ID no numérico: se rechaza con mensaje (no se interpreta como consulta válida)" \
    "$(grep -qiE 'entero|número|id' <<< "$OUT" && ! grep -qE '^Job #' <<< "$OUT" && echo 0 || echo 1)"

# ══ PARTE B — RF-09: listado ═════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "[3] Parte B (RF-09): listado completo" | tee -a "$LOG"

EXPECTED_IDS=$(printf '%s\n' "$ID_S" "$ID_F" "$ID_R" "$ID_Q1" "$ID_Q2" "$ID_X" | sort -n | paste -sd, -)
GOT_IDS=$(all_ids "$LIST" | paste -sd, -)
check "status sin argumentos lista exactamente los 6 trabajos (esperado: $EXPECTED_IDS; obtenido: $GOT_IDS)" \
    "$([[ "$GOT_IDS" == "$EXPECTED_IDS" ]] && echo 0 || echo 1)"
DUPS=$(all_ids "$LIST" | uniq -d | paste -sd, -)
check "El listado no repite ningún trabajo (repetidos: ${DUPS:-ninguno})" "$([[ -z "$DUPS" ]] && echo 0 || echo 1)"
check "Cada estado del listado coincide con el de la consulta por ID" \
    "$(for k in S F R Q1 Q2 X; do [[ "$(state_of_id "$LIST" "${IDOF[$k]}")" == "${EXPECT[$k]}" ]] || echo bad; done | grep -q bad && echo 1 || echo 0)"
GOT2=$(all_ids "$LIST2" | paste -sd, -)
check "'list' devuelve los mismos trabajos que 'status' (obtenido: $GOT2)" \
    "$([[ "$GOT2" == "$EXPECTED_IDS" ]] && echo 0 || echo 1)"

# ══ PARTE C — RF-09: filtro por estado ═══════════════════════════════════════
echo "" | tee -a "$LOG"
echo "[4] Parte C (RF-09): filtro por estado (sintaxis provisional: '$FILTER_FMT')" | tee -a "$LOG"

# shellcheck disable=SC2059
PROBE=$(client $(printf "$FILTER_FMT" Succeeded) 2>&1)
echo "sonda: $(printf "$FILTER_FMT" Succeeded)"$'\n'"$PROBE" > "$RUN_DIR/filter-probe.txt"
if ! grep -qE '^Job #[0-9]+:' <<< "$PROBE"; then
    block "RF-09: el daemon no soporta el filtro por estado ('$(printf "$FILTER_FMT" Succeeded)' -> '$(head -1 <<< "$PROBE")'). Falta A2-07; la parte C no se evaluó."
else
    : > "$RUN_DIR/filter-results.txt"
    for st in "${STATES[@]}"; do
        # shellcheck disable=SC2059
        F_OUT=$(client $(printf "$FILTER_FMT" "$st") 2>&1)
        { echo "--- filtro: $st"; echo "$F_OUT"; } >> "$RUN_DIR/filter-results.txt"
        EXP=$(ids_in_state "$LIST" "$st")
        GOT=$(job_pairs "$F_OUT" | awk '{print $1}' | sort -n | paste -sd, -)
        OTHERS=$(job_pairs "$F_OUT" | awk -v s="$st" '$2 != s' | wc -l)
        check "Filtro $st devuelve exactamente [$EXP] (obtenido: [$GOT])" "$([[ "$GOT" == "$EXP" ]] && echo 0 || echo 1)"
        check "Filtro $st no devuelve trabajos de otro estado (ajenos: $OTHERS)" "$([[ "$OTHERS" -eq 0 ]] && echo 0 || echo 1)"
    done
    # shellcheck disable=SC2059
    BAD=$(client $(printf "$FILTER_FMT" EstadoInexistente) 2>&1)
    echo "--- filtro inválido"$'\n'"$BAD" >> "$RUN_DIR/filter-results.txt"
    check "Un estado inexistente se rechaza con mensaje (no devuelve el listado completo)" \
        "$(! grep -qE '^Job #' <<< "$BAD" && [[ -n "$BAD" ]] && echo 0 || echo 1)"
fi

# Dejar terminar R y esperar a que Q1 y Q2 corran antes de la carga
wait_terminal "$ID_R" 20; wait_terminal "$ID_Q1" 20; wait_terminal "$ID_Q2" 20

# ══ PARTE D — RNF-05: tiempo de consulta con ≥ 100 trabajos almacenados ═════
echo "" | tee -a "$LOG"
echo "[5] Parte D (RNF-05): cargando $LOAD_JOBS trabajos 'echo carga'" | tee -a "$LOG"

: > "$RUN_DIR/load-submit.txt"
LOAD_OK=0
for n in $(seq 1 "$LOAD_JOBS"); do
    R=$(client echo "carga-$n" 2>&1)
    echo "carga-$n -> $R" >> "$RUN_DIR/load-submit.txt"
    grep -q 'encolado correctamente' <<< "$R" && LOAD_OK=$((LOAD_OK + 1))
done
check "Los $LOAD_JOBS trabajos de carga fueron aceptados (aceptados: $LOAD_OK)" \
    "$([[ "$LOAD_OK" -eq "$LOAD_JOBS" ]] && echo 0 || echo 1)"

SECONDS=0
while [[ $SECONDS -lt $LOAD_WAIT_SECS ]]; do
    LOADED=$(client status 2>&1)
    PENDING=$(job_pairs "$LOADED" | awk '$2 == "Queued" || $2 == "Running"' | wc -l)
    [[ "$PENDING" -eq 0 ]] && break
    sleep 1
done
LOADED=$(client status 2>&1)
echo "$LOADED" > "$RUN_DIR/load-status.txt"
STORED=$(job_pairs "$LOADED" | wc -l)
check "Hay al menos $LOAD_JOBS trabajos almacenados y ninguno pendiente (almacenados: $STORED)" \
    "$([[ "$STORED" -ge "$LOAD_JOBS" && "${PENDING:-1}" -eq 0 ]] && echo 0 || echo 1)"

# Medición: REPS consultas de cada tipo; el criterio se evalúa sobre el MÁXIMO
: > "$RUN_DIR/response-times.txt"
measure() {   # measure <etiqueta> <args...>  -> deja MAX_T
    local label="$1"; shift
    MAX_T=0
    for r in $(seq 1 "$REPS"); do
        time_cmd "$@"
        echo "$label rep=$r t=${ELAPSED}s bytes=${#OUT}" >> "$RUN_DIR/response-times.txt"
        MAX_T=$(awk -v a="$MAX_T" -v b="$ELAPSED" 'BEGIN{printf "%.3f", (b>a)?b:a}')
    done
    echo "$label MAX=${MAX_T}s" | tee -a "$RUN_DIR/response-times.txt" >> "$LOG"
}
check_time() {   # check_time <descripción> <máx medido>
    check "$1 (máx. ${2}s <= ${MAX_QUERY_SECS}s)" "$(awk -v t="$2" -v m="$MAX_QUERY_SECS" 'BEGIN{exit !(t<=m)}' && echo 0 || echo 1)"
}

measure "status-por-id" status "$ID_S";   check_time "RNF-05: status <id> con $STORED trabajos" "$MAX_T"
measure "status-listado" status;           check_time "RNF-05: status (listado completo) con $STORED trabajos" "$MAX_T"
LIST_BYTES=${#OUT}
check "El listado completo devolvió los $STORED trabajos (líneas: $(job_pairs "$OUT" | wc -l))" \
    "$([[ "$(job_pairs "$OUT" | wc -l)" -ge "$LOAD_JOBS" ]] && echo 0 || echo 1)"

# shellcheck disable=SC2059
if grep -qE '^Job #[0-9]+:' <<< "$(client $(printf "$FILTER_FMT" Succeeded) 2>&1)"; then
    # shellcheck disable=SC2059
    measure "status-filtrado" $(printf "$FILTER_FMT" Succeeded)
    check_time "RNF-05: consulta filtrada con $STORED trabajos" "$MAX_T"
else
    block "RNF-05: no se midió la consulta filtrada porque el filtro por estado no está soportado (A2-07)."
fi

{
    echo "trabajos_almacenados=$STORED"
    echo "repeticiones_por_consulta=$REPS"
    echo "umbral_s=$MAX_QUERY_SECS"
    echo "bytes_listado=$LIST_BYTES"
    grep 'MAX=' "$RUN_DIR/response-times.txt"
} > "$RUN_DIR/rnf05-summary.txt"

# ── Procesos residuales (antes de detener el daemon) ─────────────────────────
echo "" | tee -a "$LOG"
echo "[INFO] File descriptors abiertos por daemon: $(count_open_fds)" | tee -a "$LOG"
sleep 1
check_no_zombies

finish_run
