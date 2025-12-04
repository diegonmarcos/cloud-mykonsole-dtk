# AI Usage Dashboard Specification

> **Updated**: 2025-12-04
> **Integration**: Part of Cloud Dashboard (Section 12A.5 in Cloud-spec_.md)
> **Primary Tool**: `ccusage` (npm package) - Use directly, no wrapper needed

## Overview

Multi-provider AI usage monitoring dashboard for budget control and real-time usage tracking. Supports Claude (primary) and Gemini (planned) with multiple views: Now (5h window), Daily, Weekly, Monthly.

**This module is the AI Cost portion of the Cloud Dashboard Cost Tab.**

## Primary Tool: ccusage

**Installation:** `npm install -g ccusage`
**Source:** https://github.com/ryoppippi/ccusage
**Data:** Reads `~/.claude/projects/*.jsonl` files

### ccusage Commands (all support --json)

| Command | Purpose | Key Output |
|---------|---------|------------|
| `ccusage blocks -a` | Current 5h window | tokens, costs, burnRate, projection |
| `ccusage blocks --live` | Real-time TUI | Live updating terminal display |
| `ccusage daily -b` | Daily breakdown | per-day totals with model breakdown |
| `ccusage weekly -b` | Weekly totals | aggregated by week |
| `ccusage monthly -b` | Monthly totals | aggregated by month |
| `ccusage session` | Per-conversation | individual session costs |

### Key Flags

| Flag | Effect |
|------|--------|
| `--json` or `-j` | JSON output (required for API) |
| `-b` or `--breakdown` | Include per-model cost breakdown |
| `-a` or `--active` | Active block only (with projections) |
| `--live` | Real-time monitoring mode |
| `-s YYYYMMDD` | Filter from date |
| `-u YYYYMMDD` | Filter until date |

### Example: Current Session Status
```bash
ccusage blocks -a --json
```
```json
{
  "blocks": [{
    "isActive": true,
    "tokenCounts": { "inputTokens": 67340, "outputTokens": 68757 },
    "costUSD": 26.06,
    "burnRate": { "tokensPerMinute": 192394, "costPerHour": 10.47 },
    "projection": { "totalCost": 51.82, "remainingMinutes": 148 },
    "models": ["claude-opus-4-5-20251101", "claude-sonnet-4-5-20250929"]
  }]
}
```

### Example: Monthly with Model Breakdown
```bash
ccusage monthly --json -b
```
```json
{
  "monthly": [{
    "month": "2025-12",
    "totalCost": 345.92,
    "modelBreakdowns": [
      { "modelName": "claude-opus-4-5-20251101", "cost": 340.47 },
      { "modelName": "claude-sonnet-4-5-20250929", "cost": 4.93 },
      { "modelName": "claude-haiku-4-5-20251001", "cost": 0.51 }
    ]
  }],
  "totals": { "totalCost": 1071.38 }
}
```

## Goals

1. Real-time monitoring of expensive model usage (Opus, Gemini Pro)
2. Budget control with projections and alerts
3. Multi-provider architecture ready for Gemini integration
4. Dual interface: CLI (ccusage) + Flask API (web dashboard)
5. **Use ccusage directly** - no wrapper module needed for basic functionality

---

## Data Sources

### Claude (Current)
- **Tool**: `ccusage` CLI (npm package)
- **Data**: `~/.claude/projects/*.jsonl`
- **Features**: Daily/weekly/monthly aggregation, model breakdown, burn rate, projections

### Gemini (Planned)
- **Source**: TBD (likely Google Cloud billing API or local logs)
- **Context Window**: 1M tokens (vs Claude's 200k)
- **Reset**: 24h (vs Claude's 5h windows)

---

## Views

### View 1: NOW (Real-time 5h Window)
**Purpose**: Monitor current session, avoid hitting rate limits

| Metric | Description |
|--------|-------------|
| Block Start/End | 5h window timestamps |
| Elapsed/Remaining | Time in current window |
| **Model Breakdown** | Tokens per model (Haiku/Sonnet/Opus) |
| Token Breakdown | Input, Output, Cache Read, Cache Create |
| Cost Breakdown | Per token type with API pricing |
| Usage Bar | % of plan limit (visual) |
| Burn Rate | Tokens/min, $/hour |
| Projections | Time to limit, Time to $X, End-of-block estimates |

**Key Enhancement**: Model-level breakdown to track expensive Opus usage.

### View 2: DAILY (Monthly Budget Control)
**Purpose**: Track spending trends, budget alerts

| Metric | Description |
|--------|-------------|
| Date | Calendar day |
| **Model Distribution** | % Haiku / Sonnet / Opus per day |
| Token Totals | Plan (In+Out), API (all) |
| Cost Totals | $Plan, $API |
| Time | Actual session hours |
| Burn Rate | $/hr, tokens/hr |
| **MTD Totals** | Month-to-date accumulation |
| **Budget Alert** | % of monthly budget used |

---

## Model Pricing Reference

### Claude (per 1M tokens)
| Model | Input | Output | Cache Read | Cache Create |
|-------|------:|-------:|-----------:|-------------:|
| Haiku 4.5 | $0.80 | $4.00 | $0.08 | $1.00 |
| **Sonnet 4.5** | $3.00 | $15.00 | $0.30 | $3.75 |
| **Opus 4.5** | $15.00 | $75.00 | $1.50 | $18.75 |

### Gemini (per 1M tokens) - Planned
| Model | Input | Output | Cache Read | Cache Create |
|-------|------:|-------:|-----------:|-------------:|
| Flash 3.0 | $1.25 | $5.00 | $0.31 | $1.25 |
| **Pro 3.0** | $1.25 | $5.00 | $0.31 | $1.25 |

### Plan Limits
| Provider | Plan | Messages/Window | Tokens/Window | Window |
|----------|------|-----------------|---------------|--------|
| Claude | Pro | 45 | ~90k | 5h |
| Claude | Max 5x | 225 | ~450k | 5h |
| Claude | Max 20x | 900 | ~1.8M | 5h |
| Gemini | Flash | 166 | ~332k | 24h |
| Gemini | Pro | 33 | ~66k | 24h |

---

## Architecture

### Dual Mode Operation

```
ccusage_report.py
    ├── CLI Mode (--now, --daily, --csv, --md)
    │   └── Direct terminal output + file exports
    │
    └── Flask API Mode (imported as module)
        └── Returns JSON for web dashboard
```

### Data Flow

```
~/.claude/projects/*.jsonl
    │
    └── ccusage CLI
            │
            ├── get_ccusage_data()      → Daily aggregates
            ├── get_blocks_data()        → 5h window blocks
            └── get_daily_time_from_blocks() → Session hours
                    │
                    ├── CLI Output (table, csv, md)
                    └── JSON API Response
```

### Module Interface (Flask Integration)

```python
# Functions to expose for Flask
def get_now_data() -> dict:
    """Return current 5h block status as JSON-serializable dict."""
    pass

def get_daily_data() -> list[dict]:
    """Return daily usage rows as JSON-serializable list."""
    pass

def get_model_breakdown() -> dict:
    """Return per-model token/cost breakdown (NEW)."""
    pass
```

---

## Enhancements Required

### Phase 1: Model Breakdown
1. Parse model info from ccusage output (if available)
2. If not available from ccusage, parse raw JSONL files directly
3. Add model column to all outputs
4. Flag expensive model usage (Opus > 10% of tokens)

### Phase 2: Budget Alerts
1. Add configurable monthly budget ($100 default)
2. Calculate MTD spending
3. Project end-of-month cost based on burn rate
4. Alert thresholds: 50%, 75%, 90%, 100%

### Phase 3: Gemini Integration
1. Abstract provider interface
2. Implement Gemini data source
3. Unified dashboard with provider tabs/filters

### Phase 4: Web Dashboard
1. Flask API endpoints matching CLI outputs
2. Real-time refresh (auto-update NOW view)
3. Charts: usage bar, daily trend, model pie chart

---

## File Structure

```
ops-Tooling/AI/
├── ccusage_report.py          # Main script (CLI + module)
├── 0.spec/
│   ├── AI_Usage_Dashboard_Spec.md   # This file
│   ├── ccusage_report.xlsx          # Reference spreadsheet
│   └── ccusage_report.html          # HTML export
├── exports/
│   ├── ccusage_report.csv           # Daily export
│   └── ccusage_report.md            # Markdown export
└── (future)
    ├── api.py                       # Flask API wrapper
    ├── gemini_usage.py              # Gemini data source
    └── config.py                    # Budget settings, pricing
```

---

## Configuration

**IMPORTANT**: All configuration is stored in `cloud_dash.json`, NOT hardcoded in Python.

### Config Location
```
/back-System/cloud/0.spec/cloud_dash.json → costs.ai.claude
```

### JSON Schema (in cloud_dash.json)
```json
{
  "costs": {
    "ai": {
      "claude": {
        "name": "Claude (Anthropic)",
        "plan": "max5x",
        "monthlyBudget": 100.00,
        "alertThresholds": [50, 75, 90, 100],
        "expensiveModelAlert": 10,
        "planLimits": {
          "pro": { "messages": 45, "tokens": 90000, "window": "5h" },
          "max5x": { "messages": 225, "tokens": 450000, "window": "5h" },
          "max20x": { "messages": 900, "tokens": 1800000, "window": "5h" }
        },
        "pricing": {
          "haiku": { "input": 0.80, "output": 4.00, "cacheRead": 0.08, "cacheCreate": 1.00 },
          "sonnet": { "input": 3.00, "output": 15.00, "cacheRead": 0.30, "cacheCreate": 3.75 },
          "opus": { "input": 15.00, "output": 75.00, "cacheRead": 1.50, "cacheCreate": 18.75 }
        },
        "dataSource": "ccusage"
      },
      "gemini": {
        "status": "planned"
      }
    }
  }
}
```

### Loading Config in Python
```python
def load_ai_config():
    config_path = Path(__file__).parent.parent / "cloud_dash.json"
    with open(config_path) as f:
        return json.load(f).get("costs", {}).get("ai", {})

def get_monthly_budget():
    return load_ai_config().get("claude", {}).get("monthlyBudget", 100.00)

def get_pricing(model="sonnet"):
    return load_ai_config().get("claude", {}).get("pricing", {}).get(model, {})
```

---

## API Endpoints (Flask)

**Base Path**: `/api/costs/ai/*` (integrated with cloud_dash.py)

| Endpoint | ccusage Command | Description |
|----------|-----------------|-------------|
| `/api/costs/ai/now` | `ccusage blocks -a --json` | Current 5h block with projections |
| `/api/costs/ai/daily` | `ccusage daily --json -b` | Daily breakdown with model costs |
| `/api/costs/ai/weekly` | `ccusage weekly --json -b` | Weekly aggregation |
| `/api/costs/ai/monthly` | `ccusage monthly --json -b` | Monthly totals |
| `/api/costs/infra` | - | Infra costs from cloud_dash.json |

**Flask Implementation (simple subprocess wrapper):**
```python
import subprocess, json

def run_ccusage(args):
    """Run ccusage command and return JSON."""
    result = subprocess.run(
        ['ccusage'] + args + ['--json'],
        capture_output=True, text=True, timeout=30
    )
    return json.loads(result.stdout) if result.returncode == 0 else {"error": result.stderr}

@app.route('/api/costs/ai/now')
def api_costs_ai_now():
    return jsonify(run_ccusage(['blocks', '-a']))

@app.route('/api/costs/ai/daily')
def api_costs_ai_daily():
    return jsonify(run_ccusage(['daily', '-b']))

@app.route('/api/costs/ai/monthly')
def api_costs_ai_monthly():
    return jsonify(run_ccusage(['monthly', '-b']))
```

**Note**: ccusage handles all the heavy lifting - pricing calculations, model breakdown, projections. Flask just wraps the CLI output.

---

## Dashboard Wireframe

```
┌─────────────────────────────────────────────────────────────┐
│  AI USAGE DASHBOARD                    [NOW] [DAILY] [MTD]  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CURRENT SESSION (5h Window)                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Elapsed: 2h 15m  │  Remaining: 2h 45m               │   │
│  │ [████████████░░░░░░░░░░░░░░░░░░░░░░░░░░] 35%        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  TOKEN BREAKDOWN          │  MODEL DISTRIBUTION            │
│  ┌──────────────────────┐ │  ┌────────────────────────┐   │
│  │ Input:     15k  $0.05│ │  │ Haiku:  0%   [░░░░░░]  │   │
│  │ Output:    45k  $0.68│ │  │ Sonnet: 85%  [████████] │   │
│  │ Cache Rd: 150k  $0.05│ │  │ Opus:   15%  [██░░░░░]  │   │
│  │ Cache Cr:  10k  $0.04│ │  │         ⚠️ Opus alert   │   │
│  │ ───────────────────  │ │  └────────────────────────┘   │
│  │ Total:    220k  $0.82│ │                               │
│  └──────────────────────┘ │                               │
│                                                             │
│  PROJECTIONS                                                │
│  • Time to limit: 4h 30m                                    │
│  • End of window: ~450k tokens, ~$1.85                      │
│  • Burn rate: 1.2k/min, $0.36/hr                            │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  MONTHLY BUDGET                         MTD: $45.30 / $100  │
│  [██████████████████████████░░░░░░░░░░░░░░░░░░] 45%        │
│  Projected EOM: $78.50 (OK)                                 │
└─────────────────────────────────────────────────────────────┘
```
