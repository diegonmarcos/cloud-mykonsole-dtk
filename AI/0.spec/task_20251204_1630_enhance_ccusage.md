# Task: Enhance ccusage_report.py for AI Usage Dashboard

**Created**: 2025-12-04 16:30
**Assignee**: Sonnet
**Spec**: AI_Usage_Dashboard_Spec.md

---

## Context

The current `ccusage_report.py` script provides Claude usage monitoring but lacks:
1. Model-level breakdown (can't see Opus vs Sonnet vs Haiku usage)
2. Budget tracking (no MTD totals, no alerts)
3. Flask API module interface (needs refactoring)
4. Multi-provider readiness (Gemini support planned)

**Important**: The script has TWO modes:
1. **CLI mode**: Run directly with `--now`, `--daily`, `--csv`, `--md` flags
2. **Flask API mode**: Imported as a module to return JSON data

Both modes must continue working after changes.

---

## Files to Modify

- `/home/diego/Documents/Git/ops-Tooling/AI/ccusage_report.py`

## Files to Read (Reference)

- `/home/diego/Documents/Git/ops-Tooling/AI/0.spec/AI_Usage_Dashboard_Spec.md` - Full specification
- `/home/diego/Documents/Git/ops-Tooling/AI/exports/ccusage_report.md` - Current output format

---

## Tasks

### Task 1: Add Model Breakdown Support

**Goal**: Extract per-model token counts from ccusage data or raw JSONL files.

**Steps**:
1. Check if `ccusage --json` includes model info in its output
2. If not, add function to parse raw JSONL files from `~/.claude/projects/*/`
3. Look for `model` field in JSONL entries (likely `claude-3-5-sonnet`, `claude-opus-4-5`, etc.)
4. Create `get_model_breakdown(data: dict) -> dict` that returns:
   ```python
   {
       "haiku": {"tokens_in": X, "tokens_out": Y, "cost": Z},
       "sonnet": {"tokens_in": X, "tokens_out": Y, "cost": Z},
       "opus": {"tokens_in": X, "tokens_out": Y, "cost": Z},
       "unknown": {"tokens_in": X, "tokens_out": Y, "cost": Z}
   }
   ```
5. Update `output_now_detailed()` to show model breakdown section
6. Update `output_table()` to add model distribution column

**Acceptance Criteria**:
- `--now` shows model % distribution with Opus alert if > 10%
- `--daily` shows model split per day
- CSV/MD exports include model columns

---

### Task 2: Add Budget Tracking

**Goal**: Track month-to-date spending with projections and alerts.

**Steps**:
1. Add configuration constants at top of file:
   ```python
   MONTHLY_BUDGET = 100.00  # USD
   ALERT_THRESHOLDS = [50, 75, 90, 100]
   ```
2. Create `calculate_mtd_budget(rows: list) -> dict`:
   ```python
   {
       "mtd_cost": float,
       "mtd_days": int,
       "daily_avg": float,
       "projected_eom": float,
       "budget_pct": float,
       "alert_level": str  # "ok", "warning", "danger", "exceeded"
   }
   ```
3. Add budget section to `--daily` output
4. Add `--budget` flag for standalone budget report

**Acceptance Criteria**:
- `--daily` shows MTD totals and budget %
- `--budget` shows dedicated budget report
- Alert displayed when thresholds crossed

---

### Task 3: Refactor for Flask API Module Interface

**Goal**: Clean module interface for importing into Flask.

**Steps**:
1. Add module-level functions that return JSON-serializable dicts:
   ```python
   def get_now_json() -> dict:
       """Return current 5h block as dict for API."""
       pass

   def get_daily_json() -> list[dict]:
       """Return daily rows as list of dicts for API."""
       pass

   def get_budget_json() -> dict:
       """Return budget status as dict for API."""
       pass

   def get_models_json() -> dict:
       """Return model breakdown as dict for API."""
       pass
   ```
2. Ensure these functions don't print anything (pure data return)
3. Keep existing CLI functions unchanged
4. Add `if __name__ == "__main__":` guard properly

**Acceptance Criteria**:
- Script can be imported: `from ccusage_report import get_now_json`
- Import doesn't cause side effects (no prints, no sys.exit)
- All JSON functions return valid Python dicts/lists

---

### Task 4: Add Pricing for All Models

**Goal**: Complete pricing table for accurate cost calculation.

**Steps**:
1. Add all model pricing constants:
   ```python
   # Claude Pricing (per 1M tokens)
   PRICING = {
       "claude-3-5-haiku": {"input": 0.80, "output": 4.00, "cache_read": 0.08, "cache_create": 1.00},
       "claude-sonnet-4-5": {"input": 3.00, "output": 15.00, "cache_read": 0.30, "cache_create": 3.75},
       "claude-opus-4-5": {"input": 15.00, "output": 75.00, "cache_read": 1.50, "cache_create": 18.75},
   }
   ```
2. Update `calculate_cost()` to use model-specific pricing
3. Maintain backward compatibility (default to Sonnet if model unknown)

**Acceptance Criteria**:
- Costs calculated per-model when model info available
- Falls back to Sonnet pricing for unknown models

---

## Testing

Run these commands after changes:

```bash
# Test CLI mode
python ccusage_report.py --now
python ccusage_report.py --daily
python ccusage_report.py --csv --md

# Test import mode (in Python)
python3 -c "from ccusage_report import get_now_json; print(get_now_json())"
python3 -c "from ccusage_report import get_daily_json; print(get_daily_json()[:2])"
```

---

## Notes

- Keep the script self-contained (no new dependencies)
- The `ccusage` CLI is required (npm install -g ccusage)
- Raw JSONL files location: `~/.claude/projects/*/`
- DO NOT break existing CLI functionality
- Maintain the box-drawing ASCII art style for `--now` output

---

## Priority Order

1. **Task 3** (Flask refactor) - Enables integration
2. **Task 1** (Model breakdown) - Core new feature
3. **Task 4** (Pricing) - Accuracy improvement
4. **Task 2** (Budget) - Nice to have
