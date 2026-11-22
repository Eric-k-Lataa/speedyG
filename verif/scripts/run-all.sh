#!/bin/bash
# verif/scripts/run-all.sh
#
# Ejecuta todos los casos de prueba en orden.
# Uso: bash verif/scripts/run-all.sh
# Prerequisito: cargo build

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/verif/scripts"

# Fallos conocidos (TEMPORAL): formato "TC|motivo".
# Un TC listado que falle se reporta como KNOWN-FAIL y no rompe el exit code.
# Si un TC listado pasa, se avisa para retirarlo de la lista.
# La lista debe quedar vacía antes de etiquetar v1.0.0.
KNOWN_FAILS=(
    "TC-020|pendiente de implementación en PR/issue #64"
    "TC-022|bug de persistencia, issue #147"
)

PASS_TCS=()
FAIL_TCS=()
KNOWN_FAIL_TCS=()
STALE_KNOWN_TCS=()

known_fail_reason() {
    local entry
    for entry in "${KNOWN_FAILS[@]}"; do
        if [[ "${entry%%|*}" == "$1" ]]; then
            echo "${entry#*|}"
            return 0
        fi
    done
    return 1
}

run_tc() {
    local tc="$1"
    local reason
    echo ""
    echo "════════════════════════════════════════"
    echo "  Ejecutando $tc"
    echo "════════════════════════════════════════"

    if bash "$SCRIPTS_DIR/${tc}.sh"; then
        PASS_TCS+=("$tc")
        if known_fail_reason "$tc" >/dev/null; then
            STALE_KNOWN_TCS+=("$tc")
        fi
    elif reason="$(known_fail_reason "$tc")"; then
        echo "[KNOWN-FAIL] $tc: $reason"
        KNOWN_FAIL_TCS+=("$tc")
    else
        FAIL_TCS+=("$tc")
    fi
}

# ── Ejecutar todos los TCs ────────────────────────────────────────────────────
run_tc "TC-001"
run_tc "TC-002"
run_tc "TC-003"
run_tc "TC-004"
run_tc "TC-005"
run_tc "TC-006"
run_tc "TC-007"
run_tc "TC-008"
run_tc "TC-009"
run_tc "TC-016"
run_tc "TC-017"
run_tc "TC-018"
run_tc "TC-020"
run_tc "TC-021"
run_tc "TC-022"
run_tc "TC-024"

# ── Resumen global ────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  RESUMEN FINAL"
echo "════════════════════════════════════════"
echo "PASS (${#PASS_TCS[@]}): ${PASS_TCS[*]:-ninguno}"
echo "FAIL (${#FAIL_TCS[@]}): ${FAIL_TCS[*]:-ninguno}"
echo "KNOWN-FAIL (${#KNOWN_FAIL_TCS[@]}): ${KNOWN_FAIL_TCS[*]:-ninguno}"
for tc in "${KNOWN_FAIL_TCS[@]:-}"; do
    [[ -n "$tc" ]] && echo "  - $tc: $(known_fail_reason "$tc")"
done
for tc in "${STALE_KNOWN_TCS[@]:-}"; do
    [[ -n "$tc" ]] && echo "[AVISO] $tc pasó: retírelo de KNOWN_FAILS en run-all.sh"
done

# Escribir resumen para GITHUB_STEP_SUMMARY si está disponible
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "## Resultados de verificación"
        echo ""
        echo "| TC | Resultado |"
        echo "|---|---|"
        for tc in "${PASS_TCS[@]:-}"; do echo "| $tc | ✅ PASS |"; done
        for tc in "${FAIL_TCS[@]:-}"; do echo "| $tc | ❌ FAIL |"; done
        for tc in "${KNOWN_FAIL_TCS[@]:-}"; do
            [[ -n "$tc" ]] && echo "| $tc | ⚠️ KNOWN-FAIL ($(known_fail_reason "$tc")) |"
        done
        echo ""
        echo "**PASS:** ${#PASS_TCS[@]}  **FAIL:** ${#FAIL_TCS[@]}  **KNOWN-FAIL:** ${#KNOWN_FAIL_TCS[@]}"
    } >> "$GITHUB_STEP_SUMMARY"
fi

echo "════════════════════════════════════════"

[[ ${#FAIL_TCS[@]} -eq 0 ]]
