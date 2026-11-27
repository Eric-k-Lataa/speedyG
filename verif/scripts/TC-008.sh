#!/bin/bash
# verif/scripts/TC-008.sh
#
# TC-008 — Aislamiento de fallo: matar un hijo no afecta a los demás Running ni al daemon
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-008.sh
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RNF-08: Resiliencia del servicio ante fallos e incorrecciones.
#   - RNF-09: Aislamiento de fallos entre trabajos.
#
# Resultados en:
#   verif/results/TC-008/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MAX_CURRENT=3
QUEUE_CAP=10

CMD_J1=(sleep 1001)    # Trabajo testigo A (Running)
CMD_J2=(sleep 1002)    # Trabajo víctima (Running -> kill -9)
CMD_J3=(sleep 1003)    # Trabajo testigo B (Running)

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-008"

HAS_PGREP=0; command -v pgrep &>/dev/null && HAS_PGREP=1
echo "pgrep=$HAS_PGREP" >> "$RUN_DIR/environment.txt"

if [[ $HAS_PGREP -eq 0 ]]; then
    block "pgrep no disponible; identificaciones de subprocesos quedan BLOCKED"
fi

start_daemon --max-current "$MAX_CURRENT" --queue-cap "$QUEUE_CAP"
require_daemon_config "max_current=$MAX_CURRENT" "queue_cap=$QUEUE_CAP"

echo "$DAEMON_PID" > "$RUN_DIR/daemon-pid.txt"

submit() {   # submit <nombre> <cmd...> -> imprime el ID
    local name="$1"; shift
    local out id
    out=$(client "$@" 2>&1)
    echo "$name: $* -> $out" | tee -a "$LOG" >> "$RUN_DIR/submit-jobs.txt"
    id=$(grep -oE 'Job #[0-9]+' <<< "$out" | grep -oE '[0-9]+' | head -1)
    echo "$id"
}

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 1: Lanzamiento de trabajos concurrentes
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 1] Lanzamiento de trabajos concurrentes J1, J2, J3" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

: > "$RUN_DIR/submit-jobs.txt"
ID_J1=$(submit J1 "${CMD_J1[@]}")
ID_J2=$(submit J2 "${CMD_J2[@]}")
ID_J3=$(submit J3 "${CMD_J3[@]}")

{
    echo "J1=$ID_J1"
    echo "J2=$ID_J2"
    echo "J3=$ID_J3"
} > "$RUN_DIR/jobs-map.txt"

DISTINCT=$(printf '%s\n' "$ID_J1" "$ID_J2" "$ID_J3" | grep -v '^$' | sort -u | grep -c .)
check "Los 3 trabajos fueron aceptados con IDs válidos y distintos (distintos: $DISTINCT)" \
    "$([[ "$DISTINCT" -eq 3 ]] && echo 0 || echo 1)"

if [[ "$DISTINCT" -ne 3 ]]; then
    echo "[ERROR] No se obtuvieron los 3 IDs requeridos para la prueba." | tee -a "$LOG"
    finish_run
fi

# Esperar estabilización para que los 3 trabajos pasen a Running
sleep 2

STATUS_PRE=$(client status 2>&1)
echo "$STATUS_PRE" > "$RUN_DIR/status-pre-kill.txt"

ST_J1_PRE=$(job_state "$(client status "$ID_J1" 2>&1)")
ST_J2_PRE=$(job_state "$(client status "$ID_J2" 2>&1)")
ST_J3_PRE=$(job_state "$(client status "$ID_J3" 2>&1)")

check "J1 (${CMD_J1[*]}) está en estado Running (obtenido: '$ST_J1_PRE')" \
    "$([[ "$ST_J1_PRE" == "Running" ]] && echo 0 || echo 1)"
check "J2 (${CMD_J2[*]}) está en estado Running (obtenido: '$ST_J2_PRE')" \
    "$([[ "$ST_J2_PRE" == "Running" ]] && echo 0 || echo 1)"
check "J3 (${CMD_J3[*]}) está en estado Running (obtenido: '$ST_J3_PRE')" \
    "$([[ "$ST_J3_PRE" == "Running" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 2: Identificación de subprocesos en el SO
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 2] Identificación de subprocesos en el SO" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

PID_J1=""
PID_J2=""
PID_J3=""

if [[ $HAS_PGREP -eq 1 ]]; then
    PID_J1=$(pgrep -f "sleep 1001" | head -1 || true)
    PID_J2=$(pgrep -f "sleep 1002" | head -1 || true)
    PID_J3=$(pgrep -f "sleep 1003" | head -1 || true)
fi

{
    echo "daemon_pid=$DAEMON_PID"
    echo "pid_j1=$PID_J1"
    echo "pid_j2=$PID_J2"
    echo "pid_j3=$PID_J3"
} > "$RUN_DIR/pids-pre-kill.txt"

echo "[INFO] PIDs identificados: Daemon=$DAEMON_PID J1=$PID_J1 J2=$PID_J2 J3=$PID_J3" | tee -a "$LOG"

check "Subproceso de trabajo testigo J1 identificado en el SO (PID: '${PID_J1:-ninguno}')" \
    "$([[ -n "$PID_J1" ]] && echo 0 || echo 1)"
check "Subproceso de trabajo víctima J2 identificado en el SO (PID: '${PID_J2:-ninguno}')" \
    "$([[ -n "$PID_J2" ]] && echo 0 || echo 1)"
check "Subproceso de trabajo testigo J3 identificado en el SO (PID: '${PID_J3:-ninguno}')" \
    "$([[ -n "$PID_J3" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 3: Inyección de terminación anormal a J2 (kill -9)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 3] Inyección de kill -9 al subproceso víctima J2 (PID: $PID_J2)" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

if [[ -n "$PID_J2" ]]; then
    {
        echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S.%N')"
        echo "target_pid=$PID_J2"
        echo "signal=SIGKILL (9)"
    } > "$RUN_DIR/kill-victim.log"

    kill -9 "$PID_J2" 2>/dev/null || true
    # Matar cualquier proceso asociado al marcador sleep 1002 para garantizar muerte
    pkill -9 -f "sleep 1002" 2>/dev/null || true
    echo "[INFO] Señal SIGKILL enviada a subproceso de J2." | tee -a "$LOG"
else
    echo "[WARN] No se pudo obtener PID para J2; kill directo omitido." | tee -a "$LOG"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 4: Verificación de aislamiento de fallo (RNF-09)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 4] Verificación de aislamiento de fallo (RNF-09)" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

# Pausa de observación
sleep 2

# 1. Comprobar que el daemon no se cayó
DAEMON_ALIVE=0
if [[ -n "$DAEMON_PID" ]] && kill -0 "$DAEMON_PID" 2>/dev/null; then
    DAEMON_ALIVE=1
fi
check "[RNF-09] Daemon continúa ejecutándose con su PID original ($DAEMON_PID) tras el kill de J2" \
    "$([[ "$DAEMON_ALIVE" -eq 1 ]] && echo 0 || echo 1)"

# 2. Comprobar que los subprocesos testigos siguen vivos en el SO
J1_ALIVE=0
J3_ALIVE=0

if [[ -n "$PID_J1" ]] && kill -0 "$PID_J1" 2>/dev/null; then
    J1_ALIVE=1
fi
if [[ -n "$PID_J3" ]] && kill -0 "$PID_J3" 2>/dev/null; then
    J3_ALIVE=1
fi

{
    echo "j1_pid=$PID_J1 alive=$J1_ALIVE"
    echo "j3_pid=$PID_J3 alive=$J3_ALIVE"
} > "$RUN_DIR/witness-alive.txt"

{
    echo "daemon_alive=$DAEMON_ALIVE"
    echo "pid_j1=$PID_J1 alive=$J1_ALIVE"
    echo "pid_j2=$PID_J2 alive=$(kill -0 "$PID_J2" 2>/dev/null && echo 1 || echo 0)"
    echo "pid_j3=$PID_J3 alive=$J3_ALIVE"
} > "$RUN_DIR/pids-post-kill.txt"

check "[RNF-09] Subproceso testigo J1 (PID $PID_J1) sigue vivo en el SO tras el fallo de J2" \
    "$([[ "$J1_ALIVE" -eq 1 ]] && echo 0 || echo 1)"
check "[RNF-09] Subproceso testigo J3 (PID $PID_J3) sigue vivo en el SO tras el fallo de J2" \
    "$([[ "$J3_ALIVE" -eq 1 ]] && echo 0 || echo 1)"

# 3. Comprobar estados en el daemon
STATUS_POST=$(client status 2>&1)
echo "$STATUS_POST" > "$RUN_DIR/status-post-kill.txt"

ST_J1_POST=$(job_state "$(client status "$ID_J1" 2>&1)")
ST_J2_POST=$(job_state "$(client status "$ID_J2" 2>&1)")
ST_J3_POST=$(job_state "$(client status "$ID_J3" 2>&1)")

check "[RNF-09] Trabajo testigo J1 continúa en estado Running en el daemon (estado: '$ST_J1_POST')" \
    "$([[ "$ST_J1_POST" == "Running" ]] && echo 0 || echo 1)"
check "[RNF-09] Trabajo testigo J3 continúa en estado Running en el daemon (estado: '$ST_J3_POST')" \
    "$([[ "$ST_J3_POST" == "Running" ]] && echo 0 || echo 1)"
check "[RNF-09] Trabajo víctima J2 transicionó a estado terminal tras kill (estado: '$ST_J2_POST')" \
    "$([[ "$ST_J2_POST" != "Running" && "$ST_J2_POST" != "Queued" ]] && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 5: Verificación de resiliencia ante solicitudes inválidas y salud (RNF-08)
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 5] Verificación de resiliencia ante solicitudes inválidas y salud (RNF-08)" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

INVALID_CMD="comando_invalido_xyz_999"
INVALID_OUT=$(client "$INVALID_CMD" 2>&1 || true)
echo "$INVALID_OUT" > "$RUN_DIR/invalid-request.txt"
echo "[INFO] Solicitud inválida enviada: '$INVALID_CMD' -> '$INVALID_OUT'" | tee -a "$LOG"

# Comprobar que el daemon sigue vivo tras comando inválido
DAEMON_AFTER_INVALID=0
if [[ -n "$DAEMON_PID" ]] && kill -0 "$DAEMON_PID" 2>/dev/null; then
    DAEMON_AFTER_INVALID=1
fi
check "[RNF-08] Daemon no termina tras recibir solicitud inválida" \
    "$([[ "$DAEMON_AFTER_INVALID" -eq 1 ]] && echo 0 || echo 1)"

# Comprobar comando health
HEALTH=$(client health 2>&1)
echo "$HEALTH" > "$RUN_DIR/health-check.txt"
echo "[INFO] Respuesta de health: '$HEALTH'" | tee -a "$LOG"

check "[RNF-08] Daemon responde satisfactoriamente a health tras anomalías (obtenido: '$HEALTH')" \
    "$(health_is_ok "$HEALTH" && echo 0 || echo 1)"

# ═══════════════════════════════════════════════════════════════════════════════
# FASE 6: Limpieza y comprobación de procesos zombis
# ═══════════════════════════════════════════════════════════════════════════════
echo "" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"
echo "[FASE 6] Limpieza de trabajos activos y verificación de procesos" | tee -a "$LOG"
echo "════════════════════════════════════════" | tee -a "$LOG"

# Cancelar trabajos restantes J1 y J3
client cancel "$ID_J1" >/dev/null 2>&1 || true
client cancel "$ID_J3" >/dev/null 2>&1 || true

sleep 1

check_no_zombies

finish_run
