#!/bin/bash

RESULTS_DIR="verif/results/TC-001"
LOG="$RESULTS_DIR/execution.log"
SOCKET="/tmp/speedyg.sock"

TEST_PASSED=true
DAEMON_PID=""

mkdir -p "$RESULTS_DIR"

echo "========================================" | tee "$LOG"
echo "TC-001 - Envío y ejecución de un trabajo" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "Caso: TC-001" | tee -a "$LOG"
echo "Fecha de ejecución: $(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "$LOG"
echo "Entorno: $(uname -s)" | tee -a "$LOG"
echo "Kernel: $(uname -r)" | tee -a "$LOG"
echo "Arquitectura: $(uname -m)" | tee -a "$LOG"
echo "Hostname: $(hostname)" | tee -a "$LOG"
echo "Rust: $(rustc --version)" | tee -a "$LOG"
echo "Cargo: $(cargo --version)" | tee -a "$LOG"
echo "Branch: $(git branch --show-current)" | tee -a "$LOG"
echo "Commit: $(git rev-parse HEAD)" | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"

# Preparar daemon

if [ -S "$SOCKET" ]; then
    echo "[INFO] El daemon ya está ejecutándose." | tee -a "$LOG"
else
    echo "[INFO] Iniciando daemon speedyG..." | tee -a "$LOG"

    cargo run --bin speedyG > "$RESULTS_DIR/daemon.log" 2>&1 &
    DAEMON_PID=$!

    echo "[INFO] PID del daemon: $DAEMON_PID" | tee -a "$LOG"

    for i in {1..20}; do
        if [ -S "$SOCKET" ]; then
            break
        fi
        sleep 1
    done

    if [ ! -S "$SOCKET" ]; then
        echo "[FAIL] El daemon no creó el socket." | tee -a "$LOG"
        TEST_PASSED=false
    else
        echo "[PASS] Daemon disponible." | tee -a "$LOG"
    fi
fi

# Limpiar daemon al terminar

cleanup() {
    if [ -n "$DAEMON_PID" ]; then
        echo "" | tee -a "$LOG"
        echo "[INFO] Deteniendo daemon PID $DAEMON_PID..." | tee -a "$LOG"
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
        rm -f "$SOCKET"
    fi
}

trap cleanup EXIT

# Prueba 1

echo "" | tee -a "$LOG"
echo "[1] Enviando comando válido: echo hola" | tee -a "$LOG"

OUTPUT=$(cargo run --bin speedyg -- echo hola 2>&1)
echo "$OUTPUT" > "$RESULTS_DIR/valid-command.txt"
echo "$OUTPUT" | tee -a "$LOG"

JOB_ID=$(echo "$OUTPUT" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)

if [ -n "$JOB_ID" ]; then
    echo "[PASS] Job creado correctamente. ID: $JOB_ID" | tee -a "$LOG"
else
    echo "[FAIL] No se obtuvo un Job ID." | tee -a "$LOG"
    TEST_PASSED=false
fi

# Prueba 2

echo "" | tee -a "$LOG"
echo "[2] Consultando estado del Job #$JOB_ID" | tee -a "$LOG"

OUTPUT=$(cargo run --bin speedyg -- status "$JOB_ID" 2>&1)
echo "$OUTPUT" > "$RESULTS_DIR/status.txt"
echo "$OUTPUT" | tee -a "$LOG"

if echo "$OUTPUT" | grep -q "Job #$JOB_ID"; then
    echo "[PASS] El Job #$JOB_ID puede ser consultado." | tee -a "$LOG"
else
    echo "[FAIL] No se pudo consultar el Job #$JOB_ID." | tee -a "$LOG"
    TEST_PASSED=false
fi

# Prueba 3

echo "" | tee -a "$LOG"
echo "[3] Enviando comando de ejecución prolongada: sleep 10" | tee -a "$LOG"

OUTPUT=$(cargo run --bin speedyg -- sleep 10 2>&1)
echo "$OUTPUT" > "$RESULTS_DIR/running-command.txt"
echo "$OUTPUT" | tee -a "$LOG"

RUNNING_JOB_ID=$(echo "$OUTPUT" | grep -oE 'Job #[0-9]+' | grep -oE '[0-9]+' | head -1)

if [ -n "$RUNNING_JOB_ID" ]; then
    echo "[PASS] Job sleep creado correctamente. ID: $RUNNING_JOB_ID" | tee -a "$LOG"
else
    echo "[FAIL] No se obtuvo el ID del Job sleep." | tee -a "$LOG"
    TEST_PASSED=false
fi

# Prueba 4

echo "" | tee -a "$LOG"
echo "[4] Consultando estado del Job #$RUNNING_JOB_ID" | tee -a "$LOG"

sleep 1

OUTPUT=$(cargo run --bin speedyg -- status "$RUNNING_JOB_ID" 2>&1)
echo "$OUTPUT" > "$RESULTS_DIR/running-status.txt"
echo "$OUTPUT" | tee -a "$LOG"

if echo "$OUTPUT" | grep -q "\[Running\]"; then
    echo "[PASS] El Job #$RUNNING_JOB_ID está en estado Running." | tee -a "$LOG"
else
    echo "[FAIL] El Job #$RUNNING_JOB_ID no está en Running." | tee -a "$LOG"
    TEST_PASSED=false
fi

# Prueba 5

echo "" | tee -a "$LOG"
echo "[5] Esperando finalización del Job #$RUNNING_JOB_ID..." | tee -a "$LOG"

sleep 11

OUTPUT=$(cargo run --bin speedyg -- status "$RUNNING_JOB_ID" 2>&1)
echo "$OUTPUT" > "$RESULTS_DIR/final-status.txt"
echo "$OUTPUT" | tee -a "$LOG"

if echo "$OUTPUT" | grep -q "\[Succeeded\].*exit code: 0"; then
    echo "[PASS] El Job #$RUNNING_JOB_ID terminó correctamente." | tee -a "$LOG"
else
    echo "[FAIL] El Job #$RUNNING_JOB_ID no terminó correctamente." | tee -a "$LOG"
    TEST_PASSED=false
fi

# Prueba 6

echo "" | tee -a "$LOG"
echo "[6] Enviando comando no autorizado: rm archivo.txt" | tee -a "$LOG"

OUTPUT=$(cargo run --bin speedyg -- rm archivo.txt 2>&1)
echo "$OUTPUT" > "$RESULTS_DIR/invalid-command.txt"
echo "$OUTPUT" | tee -a "$LOG"

if echo "$OUTPUT" | grep -q "Comando no autorizado"; then
    echo "[PASS] El comando no autorizado fue rechazado." | tee -a "$LOG"
else
    echo "[FAIL] El comando no autorizado no fue rechazado correctamente." | tee -a "$LOG"
    TEST_PASSED=false
fi

# Prueba 7

echo "" | tee -a "$LOG"
echo "[7] Verificando que el daemon continúe disponible..." | tee -a "$LOG"

OUTPUT=$(cargo run --bin speedyg -- health 2>&1)
echo "$OUTPUT" > "$RESULTS_DIR/health-after-error.txt"
echo "$OUTPUT" | tee -a "$LOG"

if echo "$OUTPUT" | grep -q "OK: Daemon speedyg funcionando correctamente"; then
    echo "[PASS] El daemon continúa disponible." | tee -a "$LOG"
else
    echo "[FAIL] El daemon no continúa disponible." | tee -a "$LOG"
    TEST_PASSED=false
fi

# Resultado

echo "" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"

if [ "$TEST_PASSED" = true ]; then
    echo "RESULTADO TC-001: PASS" | tee -a "$LOG"
    echo "========================================" | tee -a "$LOG"
    exit 0
else
    echo "RESULTADO TC-001: FAIL" | tee -a "$LOG"
    echo "========================================" | tee -a "$LOG"
    exit 1
fi