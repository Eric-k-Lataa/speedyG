#!/bin/bash
# verif/scripts/TC-001.sh
#
# TC-001 — Envío y ejecución de un trabajo
#
# Prerrequisito: cargo build (desde la raíz del repositorio)
#
# Uso:
#   bash verif/scripts/TC-001.sh
#
# Resultados en:
#   verif/results/TC-001/<AAAAMMDD-HHMMSS-PID>/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ── Inicializar corrida ───────────────────────────────────────────────────────
setup_run_env "TC-001"
start_daemon

# ── Prueba 1: enviar comando válido y obtener Job ID ─────────────────────────
echo "" | tee -a "$LOG"
echo "[1] Enviando comando válido: echo hola" | tee -a "$LOG"

OUT1=$(client echo hola 2>&1)
echo "$OUT1" | tee -a "$LOG"
echo "$OUT1" > "$RUN_DIR/valid-command.txt"

JOB_ID=$(echo "$OUT1" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
assert_contains "Job ID obtenido en la respuesta" "Job #" "$OUT1"

# ── Prueba 2: consultar estado del job ───────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[2] Consultando estado del Job #$JOB_ID" | tee -a "$LOG"

OUT2=$(client status "$JOB_ID" 2>&1)
echo "$OUT2" | tee -a "$LOG"
echo "$OUT2" > "$RUN_DIR/status.txt"

assert_contains "Job #$JOB_ID aparece en status" "Job #$JOB_ID" "$OUT2"

# ── Prueba 3: enviar comando de larga duración ───────────────────────────────
echo "" | tee -a "$LOG"
echo "[3] Enviando comando de ejecución prolongada: sleep 10" | tee -a "$LOG"

OUT3=$(client sleep 10 2>&1)
echo "$OUT3" | tee -a "$LOG"
echo "$OUT3" > "$RUN_DIR/running-command.txt"

RUNNING_JOB_ID=$(echo "$OUT3" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)
assert_contains "Job sleep creado y Job ID obtenido" "Job #" "$OUT3"

# ── Prueba 4: verificar estado Running ───────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[4] Esperando estado Running del Job #$RUNNING_JOB_ID..." | tee -a "$LOG"

if wait_job_state "$RUNNING_JOB_ID" "\[Running\]" 10; then
    OUT4=$(client status "$RUNNING_JOB_ID" 2>&1)
    echo "$OUT4" | tee -a "$LOG"
    echo "$OUT4" > "$RUN_DIR/running-status.txt"
    assert_contains "Job #$RUNNING_JOB_ID está en estado Running" "[Running]" "$OUT4"
else
    echo "[FAIL] Job #$RUNNING_JOB_ID no alcanzó estado Running en 10s." | tee -a "$LOG"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── Prueba 5: verificar finalización correcta ────────────────────────────────
echo "" | tee -a "$LOG"
echo "[5] Esperando finalización del Job #$RUNNING_JOB_ID (sleep 10)..." | tee -a "$LOG"

if wait_job_state "$RUNNING_JOB_ID" "\[Succeeded\]" 20; then
    OUT5=$(client status "$RUNNING_JOB_ID" 2>&1)
    echo "$OUT5" | tee -a "$LOG"
    echo "$OUT5" > "$RUN_DIR/final-status.txt"
    assert_contains "Job #$RUNNING_JOB_ID terminó con exit code 0" "exit code: 0" "$OUT5"
else
    echo "[FAIL] Job #$RUNNING_JOB_ID no alcanzó estado Succeeded en 20s." | tee -a "$LOG"
    OUT5=$(client status "$RUNNING_JOB_ID" 2>&1)
    echo "$OUT5" > "$RUN_DIR/final-status.txt"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── Prueba 6: daemon sigue disponible ────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[6] Verificando que el daemon continúe disponible..." | tee -a "$LOG"

OUT6=$(client health 2>&1)
echo "$OUT6" | tee -a "$LOG"
echo "$OUT6" > "$RUN_DIR/health-after-error.txt"

assert_contains "Daemon responde health correctamente" "OK: Daemon speedyg funcionando correctamente" "$OUT6"

# ── Diagnóstico: fds y procesos zombie ───────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[INFO] File descriptors abiertos por daemon: $(count_open_fds)" | tee -a "$LOG"
check_no_zombies

# ── Resultado final ───────────────────────────────────────────────────────────
finish_run
