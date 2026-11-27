#!/bin/bash
# verif/scripts/TC-012.sh
#
# TC-012 — Fragmentación y desconexión
#
# Prerrequisito: cargo build (desde la raíz del repositorio) y python3.
#
# Uso:
#   bash verif/scripts/TC-012.sh
#   TC012_PENDING_PRS=1 bash verif/scripts/TC-012.sh   # ver "BLOCKED" abajo
#
# Códigos de salida: 0 = PASS, 1 = FAIL, 3 = BLOCKED.
#
# Requisitos evaluados:
#   - RF-21 : el protocolo delimita mensajes, identifica errores y tolera
#             lecturas o escrituras parciales.
#   - RF-22 : una desconexión del cliente no termina el servicio ni corrompe
#             trabajos.
#   - RNF-14: se validan longitud y formato de los mensajes de red.
#   - RNF-24: el protocolo funciona con mensajes fragmentados y múltiples
#             solicitudes secuenciales.
#
# Delimitador de mensajes: docs/protocol.md aún no existe; se toma de
# TC012_DELIM (por defecto, salto de línea) y debe ajustarse al protocolo.
#
# BLOCKED: las comprobaciones que dependen de los PR de A3-04 (framing) y
# A3-05 (validación) se registran como FAIL. Con TC012_PENDING_PRS=1 se
# registran como BLOCKED mientras esos PR no estén integrados.
#
# Resultados en:
#   verif/results/TC-012/<AAAAMMDD-HHMMSS-PID>/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROBE_PY="$SCRIPT_DIR/lib/net_probe.py"
DELIM="${TC012_DELIM:-\\n}"
OVERSIZE_BYTES=1048576   # 1 MiB

setup_run_env "TC-012"

if ! command -v python3 &>/dev/null; then
    block "python3 no disponible; no se pueden enviar mensajes fragmentados"
    finish_run
fi

PAYLOADS="$RUN_DIR/payloads"
mkdir -p "$PAYLOADS"
: > "$RUN_DIR/probes.txt"

# ── Helpers ──────────────────────────────────────────────────────────────────
# probe <nombre> <archivo-payload> <whole|byte|random> [opciones de net_probe]
# Deja la respuesta en $RUN_DIR/<nombre>.resp y los metadatos en <nombre>.meta.
probe() {
    local name="$1" payload="$2" chunk="$3"; shift 3
    PROBE_RESP="$RUN_DIR/$name.resp"
    python3 "$PROBE_PY" --socket "$SOCKET" --payload-file "$payload" \
        --chunk "$chunk" "$@" > "$PROBE_RESP" 2> "$RUN_DIR/$name.meta"
    echo "$name: chunk=$chunk $(tr '\n' ' ' < "$RUN_DIR/$name.meta")" >> "$RUN_DIR/probes.txt"
}

# El servicio sigue vivo: el proceso existe y responde health.
service_alive() {
    kill -0 "$DAEMON_PID" 2>/dev/null || return 1
    health_is_ok "$(client health 2>&1)"
}

# Comprobación que depende de PR pendientes (A3-04 / A3-05).
expect() {
    if [[ "$2" -eq 0 ]]; then
        check "$1" 0
    elif [[ "${TC012_PENDING_PRS:-0}" == "1" ]]; then
        block "$1 (depende de los PR de A3-04/A3-05)"
    else
        check "$1" 1
    fi
}

# ¿La respuesta identifica el mensaje como error?
is_rejection() { grep -qiE 'error|rechaz' "$1"; }

start_daemon

# ══ A. Mensaje fragmentado (RF-21, RNF-24) ═══════════════════════════════════
echo "" | tee -a "$LOG"
echo "[A] Mensaje fragmentado" | tee -a "$LOG"

printf 'health' > "$PAYLOADS/health.bin"
printf 'echo fragmentado' > "$PAYLOADS/echo.bin"

probe frag-whole-health "$PAYLOADS/health.bin" whole --eof
check "[A0] Referencia: 'health' en un solo envío recibe OK" \
    "$(health_is_ok "$(cat "$PROBE_RESP")" && echo 0 || echo 1)"

probe frag-byte-health "$PAYLOADS/health.bin" byte --eof
check "[A1] 'health' enviado byte a byte recibe la misma respuesta OK" \
    "$(health_is_ok "$(cat "$PROBE_RESP")" && echo 0 || echo 1)"

for seed in 1 2 3; do
    probe "frag-random-health-$seed" "$PAYLOADS/health.bin" random --seed "$seed" --eof
    check "[A2] 'health' en particiones aleatorias (semilla $seed) recibe OK" \
        "$(health_is_ok "$(cat "$PROBE_RESP")" && echo 0 || echo 1)"
done

probe frag-byte-echo "$PAYLOADS/echo.bin" byte --eof
check "[A3] 'echo fragmentado' enviado byte a byte se acepta como un único trabajo" \
    "$(grep -cE 'Job #[0-9]+' "$PROBE_RESP" | grep -qx 1 && echo 0 || echo 1)"

# ══ B. Solicitudes secuenciales en una conexión (RF-21, RNF-24) ══════════════
echo "" | tee -a "$LOG"
echo "[B] Solicitudes secuenciales en una conexión" | tee -a "$LOG"

printf "health${DELIM}health${DELIM}health${DELIM}" > "$PAYLOADS/seq.bin"

probe seq-whole "$PAYLOADS/seq.bin" whole
SEQ_OK="$(grep -c '^status=active$' "$PROBE_RESP" || true)"
expect "[B1] 3 solicitudes en una conexión reciben 3 respuestas, una por solicitud (recibidas: $SEQ_OK)" \
    "$([[ "$SEQ_OK" -eq 3 ]] && echo 0 || echo 1)"

probe seq-byte "$PAYLOADS/seq.bin" byte
SEQ_OK2="$(grep -c '^status=active$' "$PROBE_RESP" || true)"
expect "[B2] Las mismas 3 solicitudes enviadas byte a byte reciben 3 respuestas (recibidas: $SEQ_OK2)" \
    "$([[ "$SEQ_OK2" -eq 3 ]] && echo 0 || echo 1)"

# ══ C. Mensajes inválidos (RNF-14, RF-21) ════════════════════════════════════
echo "" | tee -a "$LOG"
echo "[C] Mensajes inválidos" | tee -a "$LOG"

{ printf 'echo '; head -c "$OVERSIZE_BYTES" /dev/zero | tr '\0' 'a'; } > "$PAYLOADS/oversize.bin"
probe invalid-oversize "$PAYLOADS/oversize.bin" whole --eof --idle 5
expect "[C1] Mensaje de $OVERSIZE_BYTES bytes identificado como error (RNF-14, longitud)" \
    "$(is_rejection "$PROBE_RESP" && echo 0 || echo 1)"
check "[C1] El protocolo se recupera: la siguiente solicitud válida responde OK" \
    "$(service_alive && echo 0 || echo 1)"

printf 'echo \xff\xfe\xfd' > "$PAYLOADS/utf8.bin"
probe invalid-utf8 "$PAYLOADS/utf8.bin" whole --eof
expect "[C2] UTF-8 inválido identificado como error (RNF-14, formato)" \
    "$(is_rejection "$PROBE_RESP" && echo 0 || echo 1)"
check "[C2] El protocolo se recupera: la siguiente solicitud válida responde OK" \
    "$(service_alive && echo 0 || echo 1)"

: > "$PAYLOADS/empty.bin"
probe invalid-empty "$PAYLOADS/empty.bin" whole --eof
expect "[C3] Mensaje vacío identificado como error (RNF-14, formato)" \
    "$(is_rejection "$PROBE_RESP" && echo 0 || echo 1)"
check "[C3] El protocolo se recupera: la siguiente solicitud válida responde OK" \
    "$(service_alive && echo 0 || echo 1)"

# ══ D. Desconexión del cliente (RF-22) ═══════════════════════════════════════
echo "" | tee -a "$LOG"
echo "[D] Desconexión del cliente" | tee -a "$LOG"

# Un trabajo aceptado antes de las desconexiones: no debe corromperse.
OUT_JOB="$(client sleep 30 2>&1)"
JOB_ID="$(grep -oE 'Job #[0-9]+' <<< "$OUT_JOB" | grep -oE '[0-9]+' | head -1 || true)"
echo "$OUT_JOB" > "$RUN_DIR/job-before.txt"
check "[D0] Trabajo de referencia aceptado antes de desconectar clientes (id: ${JOB_ID:-ninguno})" \
    "$([[ -n "$JOB_ID" ]] && echo 0 || echo 1)"

# D1. Corte antes de enviar: conecta y cierra sin enviar nada.
: > "$PAYLOADS/none.bin"
probe disc-before "$PAYLOADS/none.bin" whole --idle 0.2
check "[D1] Servicio activo tras un cliente que se desconecta antes de enviar" \
    "$(service_alive && echo 0 || echo 1)"

# D2. Corte a medias: envía medio mensaje y cierra.
printf 'ech' > "$PAYLOADS/half.bin"
probe disc-half "$PAYLOADS/half.bin" whole --idle 0.2
check "[D2] Servicio activo tras un cliente que se desconecta a medio mensaje" \
    "$(service_alive && echo 0 || echo 1)"

# D3. Corte esperando respuesta: envía mensaje completo y cierra sin leer.
probe disc-waiting "$PAYLOADS/echo.bin" whole --idle 0.0
check "[D3] Servicio activo tras un cliente que se desconecta esperando respuesta" \
    "$(service_alive && echo 0 || echo 1)"

# El trabajo de referencia sigue en un estado coherente.
if [[ -n "$JOB_ID" ]]; then
    ST_AFTER="$(client status "$JOB_ID" 2>&1)"
    echo "$ST_AFTER" > "$RUN_DIR/job-after.txt"
    check "[D4] El trabajo #$JOB_ID sigue consultable en un estado válido tras las desconexiones" \
        "$(grep -qE "^Job #$JOB_ID:.*\[(Queued|Running|Succeeded|Failed|Canceled|Interrupted)" <<< "$ST_AFTER" && echo 0 || echo 1)"
fi

OUT_FINAL="$(client echo final 2>&1)"
echo "$OUT_FINAL" > "$RUN_DIR/final-echo.txt"
check "[D5] Se acepta un trabajo nuevo tras las desconexiones" \
    "$(grep -qE 'Job #[0-9]+' <<< "$OUT_FINAL" && echo 0 || echo 1)"

[[ -n "$JOB_ID" ]] && client cancel "$JOB_ID" >/dev/null 2>&1

finish_run
