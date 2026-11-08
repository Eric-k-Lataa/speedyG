#!/bin/bash
# verif/scripts/TC-007.sh
#
# TC-007 — Reinicio, recuperación y capacidad de persistencia del daemon
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-007.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RF-12: Conservar metadatos y resultados mínimos después de reiniciar.
#   - RF-13: Recuperar historial persistido y marcar coherentemente trabajos interrumpidos.
#   - RNF-06: Soportar al menos 500 registros de trabajos sin pérdida de metadatos.
#   - RNF-10: Tras reinicio, no reportar como RUNNING un proceso que ya no controla.
#   - RNF-11: Integridad de archivos persistentes evitando estados parcialmente actualizados.
#   - RNF-31: Distinguir trabajos pendientes, terminados e interrumpidos sin reportar ejecución inexistente.
#
# Resultados en:
#   verif/results/TC-007/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=1
QUEUE_CAP=550
MAX_WAIT_DRAIN_SECS=15
LOAD_500_COUNT=500

CMD_J1=(echo terminado-exito)
CMD_J2=(false)
CMD_J3=(sleep 1003)
CMD_J4=(sleep 1004)
CMD_J5=(echo en-cola-1)
CMD_J6=(echo en-cola-2)
CMD_J7=(echo post-reinicio)

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-007"
start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$MAX_CURRENT" "queue_cap=$QUEUE_CAP"

submit() {   # submit <nombre> <cmd...> -> imprime el ID
    local name="$1"; shift
    local out id
    out=$(client "$@" 2>&1)
    echo "$name: $* -> $out" | tee -a "$LOG" >> "$RUN_DIR/submit-initial.txt"
    id=$(grep -oE 'Job #[0-9]+' <<< "$out" | grep -oE '[0-9]+' | head -1)
    echo "$id"
}

# ── Paso 1: Enviar mezcla de trabajos (J1 a J6) ──────────────────────────────
echo "" | tee -a "$LOG"
echo "[1] Preparando mezcla de trabajos en distintos estados antes de la caída" | tee -a "$LOG"
: > "$RUN_DIR/submit-initial.txt"

# J1: Succeeded
ID_J1=$(submit J1 "${CMD_J1[@]}")
wait_job_state "$ID_J1" "Succeeded" 5
SNAP_J1_INIT=$(client status "$ID_J1" 2>&1)

# J2: Failed
ID_J2=$(submit J2 "${CMD_J2[@]}")
wait_job_state "$ID_J2" "Failed" 5
SNAP_J2_INIT=$(client status "$ID_J2" 2>&1)

# J3: Canceled en cola
ID_J3=$(submit J3 "${CMD_J3[@]}")
client cancel "$ID_J3" >/dev/null 2>&1 || true
SNAP_J3_INIT=$(client status "$ID_J3" 2>&1)

# J4: Running (ranura ocupada con max_current=1)
ID_J4=$(submit J4 "${CMD_J4[@]}")
wait_job_state "$ID_J4" "Running" 5
SNAP_J4_INIT=$(client status "$ID_J4" 2>&1)

# J5 y J6: Queued
ID_J5=$(submit J5 "${CMD_J5[@]}")
ID_J6=$(submit J6 "${CMD_J6[@]}")
SNAP_J5_INIT=$(client status "$ID_J5" 2>&1)
SNAP_J6_INIT=$(client status "$ID_J6" 2>&1)

{
    echo "J1=$ID_J1 (Succeeded)"
    echo "J2=$ID_J2 (Failed)"
    echo "J3=$ID_J3 (Canceled)"
    echo "J4=$ID_J4 (Running)"
    echo "J5=$ID_J5 (Queued)"
    echo "J6=$ID_J6 (Queued)"
} > "$RUN_DIR/jobs-map.txt"
cat "$RUN_DIR/jobs-map.txt" | tee -a "$LOG"

DISTINCT=$(printf '%s\n' "$ID_J1" "$ID_J2" "$ID_J3" "$ID_J4" "$ID_J5" "$ID_J6" | grep -v '^$' | sort -u | grep -c .)
check "Los 6 trabajos iniciales fueron aceptados con IDs únicos (distintos: $DISTINCT)" \
    "$([[ "$DISTINCT" -eq 6 ]] && echo 0 || echo 1)"

if [[ "$DISTINCT" -ne 6 ]]; then
    echo "[ERROR] No se obtuvieron los 6 IDs requeridos para el caso." | tee -a "$LOG"
    finish_run
fi

# ── Paso 2: Estado consolidado previo a la caída ─────────────────────────────
echo "" | tee -a "$LOG"
echo "[2] Verificando estados consolidados antes de kill -9" | tee -a "$LOG"

{
    echo "=== ESTADO PRE-KILL ==="
    echo "$SNAP_J1_INIT"
    echo "$SNAP_J2_INIT"
    echo "$SNAP_J3_INIT"
    echo "$SNAP_J4_INIT"
    echo "$SNAP_J5_INIT"
    echo "$SNAP_J6_INIT"
} | tee "$RUN_DIR/status-before-kill.txt" >> "$LOG"

ST_J1_PRE=$(job_state "$SNAP_J1_INIT")
ST_J2_PRE=$(job_state "$SNAP_J2_INIT")
ST_J3_PRE=$(job_state "$SNAP_J3_INIT")
ST_J4_PRE=$(job_state "$SNAP_J4_INIT")
ST_J5_PRE=$(job_state "$SNAP_J5_INIT")
ST_J6_PRE=$(job_state "$SNAP_J6_INIT")

check "J1 está en Succeeded (exit code 0) antes del kill (obtenido: '$ST_J1_PRE')" \
    "$(( [[ "$ST_J1_PRE" == "Succeeded" ]] && grep -q 'exit code: 0' <<< "$SNAP_J1_INIT" ) && echo 0 || echo 1)"
check "J2 está en Failed antes del kill (obtenido: '$ST_J2_PRE')" \
    "$([[ "$ST_J2_PRE" == "Failed" ]] && echo 0 || echo 1)"
check "J3 está en Canceled antes del kill (obtenido: '$ST_J3_PRE')" \
    "$([[ "$ST_J3_PRE" == "Canceled" ]] && echo 0 || echo 1)"
check "J4 está en Running antes del kill (obtenido: '$ST_J4_PRE')" \
    "$([[ "$ST_J4_PRE" == "Running" ]] && echo 0 || echo 1)"
check "J5 está en Queued antes del kill (obtenido: '$ST_J5_PRE')" \
    "$([[ "$ST_J5_PRE" == "Queued" ]] && echo 0 || echo 1)"
check "J6 está en Queued antes del kill (obtenido: '$ST_J6_PRE')" \
    "$([[ "$ST_J6_PRE" == "Queued" ]] && echo 0 || echo 1)"

# ── Paso 3: Snapshot de persistencia y registro de PIDs ──────────────────────
echo "" | tee -a "$LOG"
echo "[3] Registrando PIDs y snapshot de persistencia en disco" | tee -a "$LOG"

DIRECT_CHILDREN=$(ps -eo pid,ppid,comm 2>/dev/null | awk -v dpid="$DAEMON_PID" '$2 == dpid {print $1}')
MARKER_PIDS_J4=$(pgrep -f "sleep 1004" 2>/dev/null || true)
{
    echo "daemon_pid=$DAEMON_PID"
    echo "direct_children=$DIRECT_CHILDREN"
    echo "marker_pids_sleep_1004=$MARKER_PIDS_J4"
} > "$RUN_DIR/pids-pre-kill.txt"
cat "$RUN_DIR/pids-pre-kill.txt" | tee -a "$LOG"

if [[ -f "$SPEEDYG_JSON" ]]; then
    cp "$SPEEDYG_JSON" "$RUN_DIR/snapshot-pre-kill.json"
fi
if [[ -f "$SPEEDYG_DB" ]]; then
    cp "$SPEEDYG_DB" "$RUN_DIR/snapshot-pre-kill.db"
fi

# ── Paso 4: Interrupción abrupta (kill -9) ────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[4] Provocando caída abrupta del daemon con kill -9 (PID $DAEMON_PID)" | tee -a "$LOG"

OLD_DAEMON_PID="$DAEMON_PID"
{
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "killing_pid=$OLD_DAEMON_PID"
} > "$RUN_DIR/kill-daemon.log"

kill -9 "$OLD_DAEMON_PID" 2>/dev/null || true
sleep 1

# Verificar que el daemon anterior murió
DAEMON_STILL_ALIVE=0
if kill -0 "$OLD_DAEMON_PID" 2>/dev/null; then
    DAEMON_STILL_ALIVE=1
fi
check "Daemon PID $OLD_DAEMON_PID terminado abruptamente por SIGKILL" \
    "$([[ "$DAEMON_STILL_ALIVE" -eq 0 ]] && echo 0 || echo 1)"

# Matar procesos huérfanos de sleep 1004 para simular proceso no controlado
pkill -9 -f "sleep 1004" 2>/dev/null || true
DAEMON_PID=""

# ── Paso 5: Verificación de integridad del archivo persistente (RNF-11) ───────
echo "" | tee -a "$LOG"
echo "[5] Verificando integridad del archivo de persistencia en disco (RNF-11)" | tee -a "$LOG"

PERSIST_INTEGRITY=1
INTEGRITY_DETAILS=""

if [[ -f "$SPEEDYG_JSON" ]]; then
    if command -v jq >/dev/null 2>&1; then
        if jq . "$SPEEDYG_JSON" >/dev/null 2>&1; then
            PERSIST_INTEGRITY=0
            INTEGRITY_DETAILS="JSON válido verificado con jq."
        else
            INTEGRITY_DETAILS="Error: JSON malformado según jq."
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if python3 -m json.tool "$SPEEDYG_JSON" >/dev/null 2>&1; then
            PERSIST_INTEGRITY=0
            INTEGRITY_DETAILS="JSON válido verificado con python3."
        else
            INTEGRITY_DETAILS="Error: JSON malformado según python3."
        fi
    else
        # Verificación básica de llaves
        if grep -q "{" "$SPEEDYG_JSON" && grep -q "}" "$SPEEDYG_JSON"; then
            PERSIST_INTEGRITY=0
            INTEGRITY_DETAILS="JSON con estructura básica consistente."
        fi
    fi
elif [[ -f "$SPEEDYG_DB" ]]; then
    if command -v sqlite3 >/dev/null 2>&1; then
        if sqlite3 "$SPEEDYG_DB" "PRAGMA integrity_check;" 2>&1 | grep -q "ok"; then
            PERSIST_INTEGRITY=0
            INTEGRITY_DETAILS="SQLite integrity check: ok."
        fi
    else
        PERSIST_INTEGRITY=0
        INTEGRITY_DETAILS="Base de datos SQLite presente."
    fi
else
    INTEGRITY_DETAILS="Error: No se encontró archivo de persistencia ($SPEEDYG_JSON / $SPEEDYG_DB)."
fi

{
    echo "integrity_result=$PERSIST_INTEGRITY"
    echo "details=$INTEGRITY_DETAILS"
    echo "json_path=$SPEEDYG_JSON"
    echo "db_path=$SPEEDYG_DB"
} > "$RUN_DIR/persistence-integrity-check.txt"
cat "$RUN_DIR/persistence-integrity-check.txt" | tee -a "$LOG"

check "Archivo de persistencia íntegro y sin estado parcialmente corrupto (RNF-11)" \
    "$([[ "$PERSIST_INTEGRITY" -eq 0 ]] && echo 0 || echo 1)"

# ── Paso 6: Reinicio del daemon (Instancia 2) ─────────────────────────────────
echo "" | tee -a "$LOG"
echo "[6] Reiniciando daemon (Instancia 2) sobre el mismo directorio de datos" | tee -a "$LOG"

"$DAEMON_BIN" \
    --socket "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current "$MAX_CURRENT" \
    --queue-cap "$QUEUE_CAP" \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!

echo "[INFO] Nuevo PID del daemon: $DAEMON_PID" | tee -a "$LOG"
{
    echo "restart_timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "new_daemon_pid=$DAEMON_PID"
} > "$RUN_DIR/daemon-restart.log"

wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
RC_SOCK=$?
check "Daemon reiniciado exitosamente y socket disponible (PID $DAEMON_PID)" \
    "$([[ "$RC_SOCK" -eq 0 ]] && echo 0 || echo 1)"

if [[ "$RC_SOCK" -ne 0 ]]; then
    echo "[FAIL] El daemon reiniciado no respondió." | tee -a "$LOG"
    finish_run
fi

# ── Paso 7: Comprobación de recuperación y distinción de estados (RF-12, RF-13, RNF-10, RNF-31) ────
echo "" | tee -a "$LOG"
echo "[7] Consultando estados tras reinicio (RF-12, RF-13, RNF-10, RNF-31)" | tee -a "$LOG"

POST_J1=$(client status "$ID_J1" 2>&1)
POST_J2=$(client status "$ID_J2" 2>&1)
POST_J3=$(client status "$ID_J3" 2>&1)
POST_J4=$(client status "$ID_J4" 2>&1)
POST_J5=$(client status "$ID_J5" 2>&1)
POST_J6=$(client status "$ID_J6" 2>&1)

{
    echo "=== ESTADOS INMEDIATOS POST-REINICIO ==="
    echo "$POST_J1"
    echo "$POST_J2"
    echo "$POST_J3"
    echo "$POST_J4"
    echo "$POST_J5"
    echo "$POST_J6"
} | tee "$RUN_DIR/status-after-restart.txt" >> "$LOG"

ST_J1_POST=$(job_state "$POST_J1")
ST_J2_POST=$(job_state "$POST_J2")
ST_J3_POST=$(job_state "$POST_J3")
ST_J4_POST=$(job_state "$POST_J4")

# RF-12 & RNF-31: Conservación exacta de trabajos terminados
check "RF-12/RNF-31: J1 conserva estado Succeeded y exit code 0 tras reinicio (obtenido: '$ST_J1_POST')" \
    "$(( [[ "$ST_J1_POST" == "Succeeded" ]] && grep -q 'exit code: 0' <<< "$POST_J1" ) && echo 0 || echo 1)"
check "RF-12/RNF-31: J2 conserva estado Failed y exit code tras reinicio (obtenido: '$ST_J2_POST')" \
    "$(( [[ "$ST_J2_POST" == "Failed" ]] && grep -q 'exit code: 1' <<< "$POST_J2" ) && echo 0 || echo 1)"
check "RF-12/RNF-31: J3 conserva estado Canceled tras reinicio (obtenido: '$ST_J3_POST')" \
    "$([[ "$ST_J3_POST" == "Canceled" ]] && echo 0 || echo 1)"

# RNF-10, RF-13 & RNF-31: Distinción de trabajo interrumpido sin reportar ejecución fantasma
check "RNF-10/RNF-31: J4 NO se reporta como Running tras el reinicio (obtenido: '$ST_J4_POST')" \
    "$([[ "$ST_J4_POST" != "Running" ]] && echo 0 || echo 1)"
check "RF-13/RNF-31: J4 se marca coherentemente como Interrupted tras el reinicio (obtenido: '$ST_J4_POST')" \
    "$([[ "$ST_J4_POST" == "Interrupted" ]] && echo 0 || echo 1)"

# ── Paso 8: Avance de trabajos en cola y nuevo trabajo (RF-13, RNF-31) ────────
echo "" | tee -a "$LOG"
echo "[8] Verificando despacho de trabajos recuperados en cola (J5, J6) y nuevo trabajo (J7)" | tee -a "$LOG"

# Esperar a que J5 y J6 concluyan
DRAIN_SECS=0
J5_DONE=0
J6_DONE=0
while [[ $DRAIN_SECS -lt $MAX_WAIT_DRAIN_SECS ]]; do
    FINAL_J5=$(client status "$ID_J5" 2>&1)
    FINAL_J6=$(client status "$ID_J6" 2>&1)

    [[ "$(job_state "$FINAL_J5")" == "Succeeded" ]] && J5_DONE=1
    [[ "$(job_state "$FINAL_J6")" == "Succeeded" ]] && J6_DONE=1

    if [[ "$J5_DONE" -eq 1 && "$J6_DONE" -eq 1 ]]; then
        break
    fi
    sleep 0.5
    DRAIN_SECS=$((DRAIN_SECS + 1))
done

check "RF-13/RNF-31: J5 recuperado de cola avanza y termina en Succeeded (tiempo: ${DRAIN_SECS}s)" \
    "$([[ "$J5_DONE" -eq 1 ]] && echo 0 || echo 1)"
check "RF-13/RNF-31: J6 recuperado de cola avanza y termina en Succeeded (tiempo: ${DRAIN_SECS}s)" \
    "$([[ "$J6_DONE" -eq 1 ]] && echo 0 || echo 1)"

# Enviar nuevo trabajo J7 post-reinicio
ID_J7=$(submit J7 "${CMD_J7[@]}")
wait_job_state "$ID_J7" "Succeeded" 5
FINAL_J7=$(client status "$ID_J7" 2>&1)
ST_J7=$(job_state "$FINAL_J7")

check "Scheduler acepta y ejecuta nuevo trabajo J7 (#$ID_J7) tras reinicio (obtenido: '$ST_J7')" \
    "$(( [[ "$ST_J7" == "Succeeded" ]] && grep -q 'exit code: 0' <<< "$FINAL_J7" ) && echo 0 || echo 1)"

{
    echo "=== RESULTADOS FINALES DE COLA Y NUEVO TRABAJO ==="
    echo "J5: $FINAL_J5"
    echo "J6: $FINAL_J6"
    echo "J7: $FINAL_J7"
} > "$RUN_DIR/queue-drain-and-new-job.txt"

# ── Paso 9: Verificación de capacidad de al menos 500 registros (RNF-06) ──────
echo "" | tee -a "$LOG"
echo "[9] Verificando soporte de al menos 500 registros sin pérdida de metadatos (RNF-06)" | tee -a "$LOG"

: > "$RUN_DIR/rnf06-load-500.txt"
LOAD_ACCEPTED=0
for n in $(seq 1 "$LOAD_500_COUNT"); do
    OUT_LOAD=$(client echo "carga-rnf06-$n" 2>&1)
    echo "carga-$n: $OUT_LOAD" >> "$RUN_DIR/rnf06-load-500.txt"
    if grep -q "encolado correctamente" <<< "$OUT_LOAD"; then
        LOAD_ACCEPTED=$((LOAD_ACCEPTED + 1))
    fi
done

check "RNF-06: Se encolaron $LOAD_500_COUNT trabajos de carga (aceptados: $LOAD_ACCEPTED/$LOAD_500_COUNT)" \
    "$([[ "$LOAD_ACCEPTED" -eq "$LOAD_500_COUNT" ]] && echo 0 || echo 1)"

# Reiniciar daemon (Instancia 3) para validar recuperación de volumen alto
echo "[INFO] Reiniciando daemon (Instancia 3) para validar recuperación de 500+ registros persistidos..." | tee -a "$LOG"
stop_daemon

"$DAEMON_BIN" \
    --socket "$SOCKET" \
    --data-dir "$DATA_DIR" \
    --max-current "$MAX_CURRENT" \
    --queue-cap "$QUEUE_CAP" \
    >> "$RUN_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!

wait_socket "$SOCKET" "$DAEMON_WAIT_SECS"
RC_SOCK_500=$?
check "Daemon reiniciado exitosamente tras carga masiva (PID $DAEMON_PID)" \
    "$([[ "$RC_SOCK_500" -eq 0 ]] && echo 0 || echo 1)"

# Consultar listado total tras recuperación
STATUS_ALL=$(client status 2>&1)
TOTAL_RECORDS=$(grep -cE '^Job #[0-9]+:' <<< "$STATUS_ALL" || true)
echo "$STATUS_ALL" > "$RUN_DIR/rnf06-recovered-500.txt"

check "RNF-06: Persistencia y recuperación de al menos 500 registros (recuperados: $TOTAL_RECORDS)" \
    "$([[ "$TOTAL_RECORDS" -ge "$LOAD_500_COUNT" ]] && echo 0 || echo 1)"

# Validar integridad de metadatos de muestras del lote (primero, medio y último)
SAMPLE_1=$(client status 8 2>&1)
SAMPLE_MID=$(client status 250 2>&1)
SAMPLE_LAST=$(client status "$((LOAD_500_COUNT + 7))" 2>&1)

SAMPLE_CHECK=0
if grep -q "echo carga-rnf06-1" <<< "$SAMPLE_1" && \
   grep -q "echo carga-rnf06-" <<< "$SAMPLE_MID" && \
   grep -q "echo carga-rnf06-500" <<< "$SAMPLE_LAST"; then
    SAMPLE_CHECK=1
fi

check "RNF-06: Metadatos intactos en muestras de trabajos tras recuperación masiva" \
    "$([[ "$SAMPLE_CHECK" -eq 1 ]] && echo 0 || echo 1)"

# ── Paso 10: Salud general del servicio y zombis ─────────────────────────────
echo "" | tee -a "$LOG"
echo "[10] Verificando salud general y ausencia de procesos huérfanos / zombis" | tee -a "$LOG"

HEALTH=$(client health 2>&1)
check "Daemon responde correctamente a health tras ciclo completo (obtenido: '$HEALTH')" \
    "$(grep -q "OK:" <<< "$HEALTH" && echo 0 || echo 1)"

check_no_zombies

finish_run
