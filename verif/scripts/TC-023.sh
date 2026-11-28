#!/bin/bash
# verif/scripts/TC-023.sh
#
# TC-023 — Compatibilidad de protocolo (RNF-32)
#
# Envía al daemon mensajes con versión de protocolo compatible, incompatible y
# con encabezado ausente o mal formado, y verifica que los incompatibles se
# rechazan de forma explícita, sin crear trabajos y sin afectar al servicio.
#
# El cliente 'speedyg' siempre adjunta la versión actual, por eso los mensajes
# con versión incorrecta se envían con verif/scripts/lib/net_probe.py.
#
# Mensajes (formato v=<major>.<minor>|<comando>, terminados en \n):
#   M-01 v=1.0|health          aceptado (versión actual)
#   M-02 v=2.0|health          rechazado (mayor superior)
#   M-03 v=0.9|health          rechazado (mayor anterior)
#   M-04 v=1.1|health          rechazado (menor superior a la soportada)
#   M-05 health                rechazado (sin encabezado)
#   M-06 1.0|health            rechazado (sin prefijo v=)
#   M-07 v=abc|health          rechazado (versión no numérica)
#   M-08 v=1|health            rechazado (sin versión menor)
#   M-09 v=2.0|sleep 5         rechazado, sin crear trabajo
#
# Requisitos evaluados:
#   - RNF-32: el protocolo define compatibilidad de versión y rechaza mensajes
#             incompatibles de forma explícita
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Resultados en:
#   verif/results/TC-023/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROBE_PY="$SCRIPT_DIR/lib/net_probe.py"
MAX_REJECT_SECS=3             # tiempo máximo de respuesta de un rechazo
SUPPORTED_RE='1\.(x|0)'       # versión soportada que debe citar el rechazo

setup_run_env "TC-023"

if ! command -v python3 &>/dev/null; then
    block "python3 no disponible; no se pueden enviar mensajes con versión arbitraria"
    finish_run
fi

PAYLOADS="$RUN_DIR/payloads"
mkdir -p "$PAYLOADS"
: > "$RUN_DIR/probes.txt"
: > "$RUN_DIR/timings.txt"

# ── Helpers ──────────────────────────────────────────────────────────────────
# probe <id> <mensaje>
# Escribe el mensaje terminado en \n, lo envía por una conexión nueva y deja:
#   $RUN_DIR/<id>.resp  respuesta literal
#   $RUN_DIR/<id>.meta  metadatos de net_probe
# Variables: PROBE_RESP (ruta de la respuesta), PROBE_SECS (tiempo en segundos).
probe() {
    local id="$1" msg="$2" t0 t1
    printf '%s\n' "$msg" > "$PAYLOADS/$id.bin"
    PROBE_RESP="$RUN_DIR/$id.resp"
    t0="$(date +%s.%N)"
    python3 "$PROBE_PY" --socket "$SOCKET" --payload-file "$PAYLOADS/$id.bin" \
        --chunk whole --eof --idle "$MAX_REJECT_SECS" \
        > "$PROBE_RESP" 2> "$RUN_DIR/$id.meta"
    t1="$(date +%s.%N)"
    PROBE_SECS="$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b - a}')"
    echo "$id: msg='$msg' $(tr '\n' ' ' < "$RUN_DIR/$id.meta")" >> "$RUN_DIR/probes.txt"
    echo "$id: ${PROBE_SECS}s" >> "$RUN_DIR/timings.txt"
}

# ¿La respuesta es un rechazo de protocolo explícito y no una respuesta de health?
is_protocol_rejection() {
    grep -q '^Error de protocolo:' "$1" && ! grep -q '^status=active$' "$1"
}

start_daemon

# ── Línea base: sin trabajos ─────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[BASE] Estado inicial" | tee -a "$LOG"

client status > "$RUN_DIR/status-before.txt" 2>&1
check "[BASE] El daemon inicia sin trabajos registrados" \
    "$(grep -q 'No hay jobs registrados' "$RUN_DIR/status-before.txt" && echo 0 || echo 1)"

# ── M-01: versión actual aceptada ────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[M-01] Versión actual" | tee -a "$LOG"

probe M-01 'v=1.0|health'
check "[M-01] v=1.0 (versión actual) es aceptado y responde health" \
    "$(health_is_ok "$(cat "$PROBE_RESP")" && echo 0 || echo 1)"

# ── M-02 a M-09: rechazos ────────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[RECHAZOS] Versiones incompatibles y encabezados inválidos" | tee -a "$LOG"

IDS=(M-02 M-03 M-04 M-05 M-06 M-07 M-08 M-09)
MSGS=('v=2.0|health' 'v=0.9|health' 'v=1.1|health' 'health' '1.0|health' 'v=abc|health' 'v=1|health' 'v=2.0|sleep 5')
KINDS=(version version version missing prefix format format version)
RECVS=('2.0' '0.9' '1.1' '' '' '' '' '2.0')
DESCS=(
    'versión mayor superior'
    'versión mayor anterior'
    'versión menor superior a la soportada'
    'sin encabezado'
    'sin prefijo v='
    'versión no numérica'
    'sin versión menor'
    'versión incompatible con un comando que crearía un trabajo'
)

for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"; msg="${MSGS[$i]}"; kind="${KINDS[$i]}"; recv="${RECVS[$i]}"; desc="${DESCS[$i]}"

    probe "$id" "$msg"

    check "[$id] '$msg' ($desc) se rechaza con 'Error de protocolo:'" \
        "$(is_protocol_rejection "$PROBE_RESP" && echo 0 || echo 1)"

    case "$kind" in
        version)
            check "[$id] El rechazo indica la versión recibida ($recv)" \
                "$(grep -qF "$recv" "$PROBE_RESP" && echo 0 || echo 1)"
            check "[$id] El rechazo indica las versiones soportadas" \
                "$(grep -qE "$SUPPORTED_RE" "$PROBE_RESP" && echo 0 || echo 1)"
            ;;
        missing)
            check "[$id] El rechazo indica que el encabezado falta o está mal formado" \
                "$(grep -qiE 'ausente|mal formado' "$PROBE_RESP" && echo 0 || echo 1)"
            ;;
        prefix)
            check "[$id] El rechazo indica que falta el prefijo 'v='" \
                "$(grep -qE "prefijo|v=" "$PROBE_RESP" && echo 0 || echo 1)"
            ;;
        format)
            check "[$id] El rechazo indica el formato esperado <major>.<minor>" \
                "$(grep -qE 'formato|<major>\.<minor>' "$PROBE_RESP" && echo 0 || echo 1)"
            ;;
    esac

    check "[$id] El rechazo llega en menos de ${MAX_REJECT_SECS}s (medido: ${PROBE_SECS}s)" \
        "$(num_le "$PROBE_SECS" "$MAX_REJECT_SECS" && echo 0 || echo 1)"
done

# ── Ningún rechazo creó trabajos ─────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[ESTADO] Los rechazos no crearon trabajos" | tee -a "$LOG"

client status > "$RUN_DIR/status-after.txt" 2>&1
check "[M-09] Tras los rechazos (incluido 'sleep 5') no existe ningún trabajo" \
    "$(grep -q 'No hay jobs registrados' "$RUN_DIR/status-after.txt" && echo 0 || echo 1)"

# ── Continuidad del servicio ─────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[CONTINUIDAD] El servicio sigue activo" | tee -a "$LOG"

HEALTH_AFTER="$(client health 2>&1)"
{
    echo "== health tras los rechazos =="
    echo "$HEALTH_AFTER"
} > "$RUN_DIR/recovery.txt"
check "[CONT] El daemon sigue en ejecución" \
    "$(kill -0 "$DAEMON_PID" 2>/dev/null && echo 0 || echo 1)"
check "[CONT] 'health' responde tras los rechazos" \
    "$(health_is_ok "$HEALTH_AFTER" && echo 0 || echo 1)"

probe REC 'v=1.0|echo recuperado'
{
    echo "== v=1.0|echo recuperado =="
    cat "$PROBE_RESP"
} >> "$RUN_DIR/recovery.txt"
check "[CONT] 'v=1.0|echo recuperado' es aceptado y recibe el primer ID (los rechazos no consumen ID)" \
    "$(grep -q 'Job #1 encolado correctamente' "$PROBE_RESP" && echo 0 || echo 1)"

wait_job_state 1 "Succeeded" 10
client status > "$RUN_DIR/final-status.txt" 2>&1
JOB_IDS="$(grep -oE 'Job #[0-9]+' "$RUN_DIR/final-status.txt" | sort -u | wc -l)"
check "[CONT] Solo existe el trabajo 'echo recuperado' (trabajos distintos: $JOB_IDS)" \
    "$([[ "$JOB_IDS" -eq 1 ]] && grep -q 'Job #1' "$RUN_DIR/final-status.txt" && echo 0 || echo 1)"

# ── Registro ─────────────────────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[LOG] Registro de los rechazos" | tee -a "$LOG"

REJECT_LOGS="$(sed 's/\x1b\[[0-9;]*m//g' "$RUN_DIR/daemon.log" 2>/dev/null \
    | grep -c 'rechazada por protocolo' || true)"
echo "rechazos_en_daemon_log=$REJECT_LOGS (esperados: ${#IDS[@]})" >> "$RUN_DIR/recovery.txt"
check "[LOG] daemon.log registra los ${#IDS[@]} rechazos de protocolo (registrados: $REJECT_LOGS)" \
    "$([[ "${REJECT_LOGS:-0}" -ge "${#IDS[@]}" ]] && echo 0 || echo 1)"

# ── Procesos ─────────────────────────────────────────────────────────────────
check_no_zombies

finish_run
