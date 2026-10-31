#!/bin/bash
# verif/scripts/run-all.sh
#
# Ejecuta todos los casos de prueba en orden.
# Uso: bash verif/scripts/run-all.sh
# Prerequisito: cargo build

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/verif/scripts"

PASS_TCS=()
FAIL_TCS=()

run_tc() {
    local tc="$1"
    echo ""
    echo "════════════════════════════════════════"
    echo "  Ejecutando $tc"
    echo "════════════════════════════════════════"

    if bash "$SCRIPTS_DIR/${tc}.sh"; then
        PASS_TCS+=("$tc")
    else
        FAIL_TCS+=("$tc")
    fi
}

# ── Ejecutar todos los TCs ────────────────────────────────────────────────────
run_tc "TC-001"
run_tc "TC-002"
# run_tc "TC-003"
# run_tc "TC-004" S e descomentaran cuando A2-07 este terminado
run_tc "TC-016"

# ── Resumen global ────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  RESUMEN FINAL"
echo "════════════════════════════════════════"
echo "PASS (${#PASS_TCS[@]}): ${PASS_TCS[*]:-ninguno}"
echo "FAIL (${#FAIL_TCS[@]}): ${FAIL_TCS[*]:-ninguno}"

# Escribir resumen para GITHUB_STEP_SUMMARY si está disponible
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "## Resultados de verificación"
        echo ""
        echo "| TC | Resultado |"
        echo "|---|---|"
        for tc in "${PASS_TCS[@]:-}"; do echo "| $tc | ✅ PASS |"; done
        for tc in "${FAIL_TCS[@]:-}"; do echo "| $tc | ❌ FAIL |"; done
        echo ""
        echo "**PASS:** ${#PASS_TCS[@]}  **FAIL:** ${#FAIL_TCS[@]}"
    } >> "$GITHUB_STEP_SUMMARY"
fi

echo "════════════════════════════════════════"

[[ ${#FAIL_TCS[@]} -eq 0 ]]