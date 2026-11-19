#!/bin/bash
# verif/scripts/TC-006.sh
#
# TC-006 — Capturar stdout/stderr y código
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-006.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RF-07: Registro de tiempos (recepción, inicio, terminación) y código de salida.
#   - RF-11: Captura desacoplada de stdout y stderr sin mezclar canales y consulta.
#
# Resultados en:
#   verif/results/TC-006/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=2
QUEUE_CAP=10

J1_OUT=(echo "SOLO_STDOUT_LINEA_1")
J2_ERR=('echo "SOLO_STDERR_LINEA_1" >&2')
J3_MIX=('echo "OUT_CANAL_1"; echo "ERR_CANAL_2" >&2')
J4_FAIL=('echo "MSG_FAIL_ERR" >&2; exit 42')
J5_BIG=('for i in $(seq 1 1000); do echo "LINEA_BIG_$i"; done')
J6_NOENT=(binario_inexistente_speedyg_test_xyz)

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-006"
start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$MAX_CURRENT" "queue_cap=$QUEUE_CAP"

submit() {   # submit <nombre> <cmd...> -> imprime el ID
    local name="$1"; shift
    local out id
    out=$(client "$@" 2>&1)
    echo "$name: $* -> $out" | tee -a "$LOG" >> "$RUN_DIR/submit.txt"
    id=$(grep -oE 'Job #[0-9]+' <<< "$out" | grep -oE '[0-9]+' | head -1)
    echo "$id"
}

: > "$RUN_DIR/submit.txt"

# ── Paso 1: Salida estándar exclusiva (J1_OUT) ───────────────────────────────
echo "" | tee -a "$LOG"
echo "[1] Evaluando salida estándar exclusiva (J1_OUT)" | tee -a "$LOG"

ID_J1=$(submit J1 "${J1_OUT[@]}")
wait_job_state "$ID_J1" "Succeeded" 5
STATUS_J1=$(client status "$ID_J1" 2>&1)
echo "$STATUS_J1" | tee "$RUN_DIR/status-j1-stdout.txt" >> "$LOG"

check "J1 finalizó con estado Succeeded y exit code 0" \
    "$(( [[ "$(job_state "$STATUS_J1")" == "Succeeded" ]] && grep -q 'exit code: 0' <<< "$STATUS_J1" ) && echo 0 || echo 1)"
check "J1 contiene 'SOLO_STDOUT_LINEA_1' en [stdout]" \
    "$(grep -A 2 '\[stdout\]:' <<< "$STATUS_J1" | grep -q 'SOLO_STDOUT_LINEA_1' && echo 0 || echo 1)"
check "J1 NO contiene bloque [stderr]" \
    "$(( ! grep -q '\[stderr\]:' <<< "$STATUS_J1" ) && echo 0 || echo 1)"

# ── Paso 2: Error estándar exclusivo (J2_ERR) ────────────────────────────────
echo "" | tee -a "$LOG"
echo "[2] Evaluando error estándar exclusivo (J2_ERR)" | tee -a "$LOG"

ID_J2=$(submit J2 "${J2_ERR[@]}")
wait_job_state "$ID_J2" "Succeeded" 5
STATUS_J2=$(client status "$ID_J2" 2>&1)
echo "$STATUS_J2" | tee "$RUN_DIR/status-j2-stderr.txt" >> "$LOG"

check "J2 finalizó con estado Succeeded y exit code 0" \
    "$(( [[ "$(job_state "$STATUS_J2")" == "Succeeded" ]] && grep -q 'exit code: 0' <<< "$STATUS_J2" ) && echo 0 || echo 1)"
check "J2 contiene 'SOLO_STDERR_LINEA_1' en [stderr]" \
    "$(grep -A 2 '\[stderr\]:' <<< "$STATUS_J2" | grep -q 'SOLO_STDERR_LINEA_1' && echo 0 || echo 1)"
check "J2 NO contiene bloque [stdout]" \
    "$(( ! grep -q '\[stdout\]:' <<< "$STATUS_J2" ) && echo 0 || echo 1)"

# ── Paso 3: Salidas simultáneas no mezcladas (J3_MIX) ────────────────────────
echo "" | tee -a "$LOG"
echo "[3] Evaluando salidas concurrentes no mezcladas (J3_MIX)" | tee -a "$LOG"

ID_J3=$(submit J3 "${J3_MIX[@]}")
wait_job_state "$ID_J3" "Succeeded" 5
STATUS_J3=$(client status "$ID_J3" 2>&1)
echo "$STATUS_J3" | tee "$RUN_DIR/status-j3-mixed.txt" >> "$LOG"

STDOUT_BLOCK_J3=$(sed -n '/\[stdout\]:/,/\[stderr\]:/p' <<< "$STATUS_J3" | grep -v '\[stderr\]:')
STDERR_BLOCK_J3=$(sed -n '/\[stderr\]:/,$p' <<< "$STATUS_J3")

check "J3 contiene 'OUT_CANAL_1' exclusivamente en [stdout]" \
    "$(( grep -q 'OUT_CANAL_1' <<< "$STDOUT_BLOCK_J3" && ! grep -q 'OUT_CANAL_1' <<< "$STDERR_BLOCK_J3" ) && echo 0 || echo 1)"
check "J3 contiene 'ERR_CANAL_2' exclusivamente en [stderr]" \
    "$(( grep -q 'ERR_CANAL_2' <<< "$STDERR_BLOCK_J3" && ! grep -q 'ERR_CANAL_2' <<< "$STDOUT_BLOCK_J3" ) && echo 0 || echo 1)"

# ── Paso 4: Código de salida no cero y stderr (J4_FAIL) ──────────────────────
echo "" | tee -a "$LOG"
echo "[4] Evaluando fallo con código de salida no cero (J4_FAIL)" | tee -a "$LOG"

ID_J4=$(submit J4 "${J4_FAIL[@]}")
wait_job_state "$ID_J4" "Failed" 5
STATUS_J4=$(client status "$ID_J4" 2>&1)
echo "$STATUS_J4" | tee "$RUN_DIR/status-j4-failed-code.txt" >> "$LOG"

check "J4 clasificado como Failed con exit code: 42" \
    "$(( [[ "$(job_state "$STATUS_J4")" == "Failed" ]] && grep -q 'exit code: 42' <<< "$STATUS_J4" ) && echo 0 || echo 1)"
check "J4 contiene 'MSG_FAIL_ERR' en [stderr]" \
    "$(grep -A 2 '\[stderr\]:' <<< "$STATUS_J4" | grep -q 'MSG_FAIL_ERR' && echo 0 || echo 1)"

# ── Paso 5: Salida voluminosa / 1000 líneas (J5_BIG) ─────────────────────────
echo "" | tee -a "$LOG"
echo "[5] Evaluando captura de salida voluminosa de 1000 líneas (J5_BIG)" | tee -a "$LOG"

ID_J5=$(submit J5 "${J5_BIG[@]}")
wait_job_state "$ID_J5" "Succeeded" 10
STATUS_J5=$(client status "$ID_J5" 2>&1)
echo "$STATUS_J5" > "$RUN_DIR/status-j5-big-output.txt"

STDOUT_BLOCK_J5=$(sed -n '/\[stdout\]:/,$p' <<< "$STATUS_J5")

LINES_COUNT=$(grep -c 'LINEA_BIG_' <<< "$STDOUT_BLOCK_J5" || true)
HAS_FIRST=$(grep -q 'LINEA_BIG_1$' <<< "$STDOUT_BLOCK_J5" && echo 1 || echo 0)
HAS_LAST=$(grep -q 'LINEA_BIG_1000$' <<< "$STDOUT_BLOCK_J5" && echo 1 || echo 0)

{
    echo "total_lines_found=$LINES_COUNT"
    echo "has_first_line=$HAS_FIRST"
    echo "has_last_line=$HAS_LAST"
} > "$RUN_DIR/big-output-stats.txt"
cat "$RUN_DIR/big-output-stats.txt" | tee -a "$LOG"

check "J5 capturó las 1000 líneas completas (líneas encontradas: $LINES_COUNT)" \
    "$([[ "$LINES_COUNT" -eq 1000 ]] && echo 0 || echo 1)"
check "J5 contiene la primera y última línea sin truncamiento" \
    "$([[ "$HAS_FIRST" -eq 1 && "$HAS_LAST" -eq 1 ]] && echo 0 || echo 1)"

# ── Paso 6: Comando inexistente (J6_NOENT) ───────────────────────────────────
echo "" | tee -a "$LOG"
echo "[6] Evaluando ejecución de comando inexistente (J6_NOENT)" | tee -a "$LOG"

ID_J6=$(submit J6 "${J6_NOENT[@]}")
wait_job_state "$ID_J6" "Failed" 5
STATUS_J6=$(client status "$ID_J6" 2>&1)
echo "$STATUS_J6" | tee "$RUN_DIR/status-j6-noent.txt" >> "$LOG"

check "J6 clasificado como Failed ante comando inexistente" \
    "$([[ "$(job_state "$STATUS_J6")" == "Failed" ]] && echo 0 || echo 1)"
check "J6 reporta mensaje de error en [stderr]" \
    "$(grep -A 2 '\[stderr\]:' <<< "$STATUS_J6" | grep -qiE 'not found|no such file|no se encontr|127|error' && echo 0 || echo 1)"

# ── Paso 7: Mapeo consolidado de trabajos ────────────────────────────────────
{
    echo "J1_OUT=$ID_J1"
    echo "J2_ERR=$ID_J2"
    echo "J3_MIX=$ID_J3"
    echo "J4_FAIL=$ID_J4"
    echo "J5_BIG=$ID_J5"
    echo "J6_NOENT=$ID_J6"
} > "$RUN_DIR/jobs-map.txt"

# ── Paso 8: Validación de marcas temporales y cronología (RF-07) ─────────────
echo "" | tee -a "$LOG"
echo "[8] Verificando marcas temporales cronológicas (RF-07)" | tee -a "$LOG"

TS_REC=$(ts_field "$STATUS_J1" "Recibido")
TS_INI=$(ts_field "$STATUS_J1" "Iniciado")
TS_FIN=$(ts_field "$STATUS_J1" "Finalizado")

EP_REC=$(to_epoch "$TS_REC")
EP_INI=$(to_epoch "$TS_INI")
EP_FIN=$(to_epoch "$TS_FIN")

check "J1 registra marcas temporales completas (Recibido, Iniciado, Finalizado)" \
    "$([[ -n "$TS_REC" && -n "$TS_INI" && -n "$TS_FIN" ]] && echo 0 || echo 1)"
check "J1 cumple la relación de orden cronológico (Recibido <= Iniciado <= Finalizado)" \
    "$(( num_le "$EP_REC" "$EP_INI" && num_le "$EP_INI" "$EP_FIN" ) && echo 0 || echo 1)"

# ── Paso 9: Salud del daemon y procesos zombis ───────────────────────────────
echo "" | tee -a "$LOG"
echo "[9] Verificando salud del daemon y ausencia de procesos zombis" | tee -a "$LOG"

HEALTH=$(client health 2>&1)
check "Daemon responde a health con OK (obtenido: '$HEALTH')" \
    "$(grep -q "OK:" <<< "$HEALTH" && echo 0 || echo 1)"

check_no_zombies

finish_run
