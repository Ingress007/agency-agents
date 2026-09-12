#!/usr/bin/env bash
#
# convert-pi.sh — Convert The Agency agent .md files into Pi (pi-coding-agent) subagents.
#
# Pi is NOT (yet) an upstream-supported target, so this converter lives alongside
# convert.sh. It maps each agency persona onto pi's subagent file format:
# markdown with YAML frontmatter { name, description, aliases, tools,
# systemPromptMode: replace } + the original persona body as the system prompt.
# See README-pi.md at the repo root for how to invoke the installed agents.
#
# GENERATE:  ./scripts/convert-pi.sh                     # -> integrations/pi/agents/
# INSTALL:   ./scripts/convert-pi.sh --install           # -> ~/.pi/agent/agents/ (user scope)
#            ./scripts/convert-pi.sh --install --dest ./pi-export
# FILTER:    ./scripts/convert-pi.sh --division engineering,security
# PREVIEW:   ./scripts/convert-pi.sh --dry-run           # show what would be written, write nothing
#
# Tool grants (child tool allowlists):
#   * Advisory divisions  -> read-only (read, grep, find, ls)
#   * Code-heavy divisions -> + bash (read, grep, find, ls, bash)
#   * Per-agent read-only exceptions inside code divisions.
# These are safe defaults; edit any installed file to tune.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths & helpers
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/integrations/pi/agents}"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

DIVISIONS=(academic design engineering finance game-development gis marketing paid-media product project-management sales security spatial-computing specialized support testing)

# Read-only divisions: advice/creative/ops personas that only need to inspect.
READ_ONLY_DIVISIONS="academic design finance marketing paid-media product project-management sales support"

# Extra read-only agents inside otherwise code-capable divisions (accurate basenames).
READ_ONLY_AGENTS="engineering-code-reviewer engineering-codebase-onboarding-engineer engineering-technical-writer engineering-prompt-engineer testing-reality-checker game-designer narrative-designer level-designer business-strategist change-management-consultant chief-financial-officer corporate-training-designer customer-service customer-success-manager data-privacy-officer esg-sustainability-officer government-digital-presales-consultant grant-writer healthcare-customer-service healthcare-marketing-compliance hospitality-guest-services hr-onboarding language-translator legal-billing-time-tracking legal-client-intake legal-document-review loan-officer-assistant ma-integration-manager medical-billing-coding-specialist operations-manager organizational-psychologist personal-growth-mentor real-estate-buyer-seller recruitment-specialist retail-customer-returns sales-outreach specialized-chief-of-staff specialized-cultural-intelligence-strategist specialized-french-consulting-market specialized-korean-business-navigator specialized-pricing-analyst specialized-strategy-duel-agent study-abroad-advisor supply-chain-strategist"

# ---------------------------------------------------------------------------
# YAML-safe single-line scalar (double-quoted when needed)
# ---------------------------------------------------------------------------
yaml_scalar() {
  local s="$1"
  # Always quote and escape backslashes / double quotes. Avoids brittle
  # regex detection of YAML-special chars and remains valid single-line YAML.
  local out="${s//\\/\\\\}"
  out="${out//\"/\\\"}"
  printf '"%s"' "$out"
}

# ---------------------------------------------------------------------------
# Per-file conversion
# ---------------------------------------------------------------------------
# convert_file <src> <name> <display_name> <tools> <dest> [package]
convert_file() {
  local src="$1" name="$2" display="$3" tools="$4" dest="$5" package="${6:-}"
  local desc body
  desc="$(get_field description "$src")"
  body="$(get_body "$src")"
  {
    echo "---"
    echo "name: $name"
    [[ -n "$package" ]] && echo "package: $package"
    echo "description: $(yaml_scalar "$desc")"
    echo "aliases: $(yaml_scalar "$display")"
    echo "tools: $tools"
    echo "systemPromptMode: replace"
    echo "---"
    printf '%s\n' "$body"
  } > "$dest"
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
INSTALL=0
DEST=""
PACKAGE=""
DRY=0
SELECTED_DIVISIONS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)    INSTALL=1 ;;
    --dest)       DEST="$2"; shift ;;
    --package)    PACKAGE="$2"; shift ;;
    --division)   IFS=',' read -r -a SELECTED_DIVISIONS <<< "$2"; shift ;;
    --dry-run)    DRY=1 ;;
    --help|-h)    usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
  shift
done

if [[ ${#SELECTED_DIVISIONS[@]} -gt 0 ]]; then
  DIVISIONS=("${SELECTED_DIVISIONS[@]}")
fi

if [[ -n "$PACKAGE" ]]; then
  PACKAGE_LINE="package: $PACKAGE"
else
  PACKAGE_LINE=""
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
[[ $DRY -eq 1 ]] || mkdir -p "$OUT_DIR"
total=0; skipped=0

for div in "${DIVISIONS[@]}"; do
  dir="$REPO_ROOT/$div"
  [[ -d "$dir" ]] || { echo "  [skip] unknown division '$div'" >&2; continue; }
  while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue
    is_agent_file "$file" || { continue; }
    name="$(basename "$file" .md)"
    display="$(get_field name "$file")"
    desc="$(get_field description "$file")"
    [[ -n "$name" && -n "$desc" ]] || { skipped=$((skipped+1)); continue; }

    if [[ " $READ_ONLY_DIVISIONS " == *" $div "* || " $READ_ONLY_AGENTS " == *" $name "* ]]; then
      tools="read, grep, find, ls"
    else
      tools="read, grep, find, ls, bash"
    fi

    if [[ $DRY -eq 1 ]]; then
      printf '  %-42s -> %s  [tools: %s]\n' "$div/$name" "$OUT_DIR/$name.md" "$tools"
      total=$((total+1))
      continue
    fi

    convert_file "$file" "$name" "${display:-$name}" "$tools" "$OUT_DIR/$name.md" "$PACKAGE"
    total=$((total+1))
  done < <(find "$dir" -name "*.md" -type f -print0 2>/dev/null)
done

echo ""
echo "Converted $total agent(s) to $OUT_DIR${PACKAGE_LINE:+ (package: $PACKAGE)}${skipped:+ — skipped $skipped non-agent files}."

if [[ $INSTALL -eq 1 && $DRY -eq 0 ]]; then
  # Guard: do not run the main conversion when this script is sourced.
  [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || { echo " sourced: skipping install" >&2; return 0; }

  target="${DEST:-$HOME/.pi/agent/agents}"
  mkdir -p "$target"
  if ! cp "$OUT_DIR"/*.md "$target"/; then
    echo "Error: failed to install agents from $OUT_DIR to $target" >&2
    exit 1
  fi
  echo "Installed to $target — run: subagent({ action: \\"list\\" }) in Pi to verify."
elif [[ $DRY -eq 1 && $INSTALL -eq 1 ]]; then
  echo "(--dry-run: nothing installed.)"
fi