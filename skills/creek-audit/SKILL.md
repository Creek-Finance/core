---
name: creek-audit
description: >-
  Security audit skill for Creek Protocol (Sui Move). Trigger on "audit Creek",
  "review for security", "scan contracts", "find vulnerabilities", or when the
  user asks for adversarial analysis on this repo. Project-level skill — uses
  Creek's architecture, capability model, and recent Sui DeFi exploit knowledge.
---

# Creek Protocol Security Audit Skill

You are conducting a **security audit of the Creek Protocol** (Sui Move).
This skill bundles project-specific architecture, capability inventory, attack
vectors curated for Sui Move, recent real-world exploit patterns, and a strict
finding-judging rubric.

This skill is **project-level** (`.cursor/skills/creek-audit/`) and is checked
into source control so the whole team can re-run the same audit consistently.

## Goal

Produce **ONE consolidated audit report** at:

```
.cursor/skills/creek-audit/findings/creek-protocol-audit.md
```

The report is a single source of truth that overwrites itself on each new
audit run. **Do NOT generate multiple per-run reports.** The intent is that
the team always sees the latest assessment in one place; iteration during
analysis happens in-memory and is reflected only in the final report.

The report contains:

1. Executive summary (counts + top actionable items + severity definitions)
2. Scope (files reviewed, methodology references)
3. Findings (sorted by severity DESC, then confidence DESC)
4. Leads (signals worth manual review, not full exploit chains)
5. Verified-safe properties (positive findings for traceability)
6. Out-of-scope observations (informational)
7. Recommended action plan (tiered)
8. Methodology + disclaimer

See [`report-template.md`](./report-template.md) for the exact structure to
follow. The report is always written as a clean third-party assessment of the
**current** source tree — do not include carry-forward language such as
"previously CRITICAL", "after team review", or "post-fix posture". Every
severity is re-derived from scratch using the rules in `checklists.md` →
"Severity Calibration Discipline" against the code as it exists on disk.

## Required Reading Before Producing Findings

In a single parallel batch, read:

1. `.cursor/skills/creek-audit/architecture.md` — Creek module map, money flows, privileged surfaces
2. `.cursor/skills/creek-audit/attack-vectors.md` — 100+ Sui Move attack patterns (curated from public auditor knowledge)
3. `.cursor/skills/creek-audit/checklists.md` — protocol-specific checklists (lending / staking / oracle / coins / pause+limits / upgrade)
4. `.cursor/skills/creek-audit/recent-exploits.md` — 2025–2026 Sui DeFi exploit case studies (Cetus, Typus, Nemo, Scallop fixes, Monethic workshop labs)
5. `.cursor/skills/creek-audit/judging.md` — finding validation gates (refutation / reachability / trigger / impact)
6. `.cursor/skills/creek-audit/report-template.md` — output format

## Scope

### In scope (every audit pass MUST cover)

- `contracts/protocol/` — borrowing market, StakingManager, GUSD vault, app admin
- `contracts/coins/` — GR / GY / GUSD (mint / burn / denylist)
- `contracts/sui_x_oracle/` — XOracle + price rules
- `contracts/xaum_indicator/` — EMA push to oracle
- `contracts/libs/` — `one_time_lock_value`, `ac_table`, `wit_table`, math, fixed_point32 wrappers

### Out of scope (note in report as **trust boundary**)

- `contracts_other/vendor/xaum/`, `contracts_other/vendor/usdc/` — third-party token packages already audited by RWA/Circle
- `contracts_other/test/` — test harness, no production funds
- `contracts_other/creek_router/`, `contracts_other/query/`, `contracts_other/gr_price_query/` — read-only or auxiliary
- `contracts_other/rewards/` — only audit if explicitly requested (not deployed in `scripts/deploy/mainnet`)
- `backend/`, `admin-panel/`, `scripts/`, `sui-creek-frontend/`, `sui-test-client/` — off-chain code (mention separately if a finding crosses the chain↔off-chain boundary, e.g. private key handling)

### Always exclude

- `**/build/`, `**/Move.lock` — build artifacts
- `**/tests/`, `**/test/`, `**/*_test.move`, `**/*_tests.move`, `**/test_*.move` — tests

## Workflow

### Turn 1 — Discover

In a single parallel batch:

a. **Glob** in-scope `.move` paths (exclude tests).
b. **Read** the 6 reference files listed above.

The audit is always re-derived from scratch against the current source tree.
There is no carry-forward state between runs — the canonical report at
`findings/creek-protocol-audit.md` is overwritten on every run with a fresh
assessment.

Print one short banner line:
`Creek Audit · mode=<default|adversarial|scoped> · ts=<YYYY-MM-DD HH:MM UTC+8>`

### Turn 2 — Analyze (internal, multi-lens, no intermediate output)

Read all in-scope source files. Build finding candidates **in-memory** —
**DO NOT write intermediate files**. The user has explicitly requested a
single deliverable.

Run all seven specialist lenses on each suspicious code site:

1. **Access control** — every capability, every `tx_context::sender` check, every `public(package)` boundary
2. **Math / precision** — rounding direction, decimal mismatch, `mul_div` overflow, `FixedPoint32` truncation
3. **Economic security** — oracle staleness, flash-loan composability, MEV, donation attacks
4. **Invariants** — conservation laws (sum of balances, supply ≤ minted, pool ≥ user claims), capacity caps
5. **Execution trace** — what state mutates, what order, what assertions fire
6. **First principles** — would the protocol behave as documented?
7. **Sui protocol checklist** — apply `checklists.md` items by domain

Internally iterate as many adversarial passes as needed until convergence
(no new HIGH/CRITICAL emerges). **Do not surface these passes as separate
reports.**

### Turn 3 — Judge

For every candidate, run `judging.md`'s 4 gates (Refutation → Reachability →
Trigger → Impact). Start confidence at 100, deduct per the rubric. Below 80 →
description only, no Fix block.

### Turn 4 — Report (overwrite the canonical file)

Write the final report to (overwriting any prior content):

```
.cursor/skills/creek-audit/findings/creek-protocol-audit.md
```

Use the template in `report-template.md`. Sort findings by severity then
confidence DESC. The report MUST read as a clean third-party assessment.
Never use carry-forward language such as "previously CRITICAL", "after
team review", or "post-fix posture". If a finding's severity is calibrated
DOWN by contextual factors (transitional placeholder, deploy SOP, etc.),
the finding starts at the lower severity AND briefly explains the
calibrating context in its description.

## Adversarial Mode

When the user asks for an **attacker perspective** or this is iteration ≥ 2:

- Disable the "do not report admin-rug" rule. Document admin-side risks
  as `[ADMIN-RISK]` findings (separate from user-exploitable ones).
- Try every cross-module composition (PTB chains): `stake → borrow → liquidate`,
  `oracle update → flash mint → redeem`, etc.
- Try every degenerate input: 0, 1, `u64::MAX`, MIN_STAKE_AMOUNT, MIN_STAKE_AMOUNT + 1.
- Read every `_t.move` / `_test.move` companion to learn intended invariants,
  then break each one.
- Compare every privileged path (`AdminCap`-gated) with every adjacent path
  hitting the same shared object. Find the weakest guard. Use it.

## Skill Maintenance (separate from audit runs)

The skill itself evolves over time. When the team observes a new pattern OR
a new public Sui DeFi exploit is published:

1. Add the new pattern to `attack-vectors.md` (numbered sequentially).
2. Add the case study to `recent-exploits.md` if applicable.
3. Update `checklists.md` if the pattern maps to a specific domain check.
4. Bump `VERSION` (semver).

These maintenance updates are separate from audit runs. Audit runs always
produce ONE consolidated report at `findings/creek-protocol-audit.md`.

## Output Discipline

- Never narrate progress in chat. The deliverable is the report file.
- Quote code with line numbers (`startLine:endLine:filepath`) in every finding.
- Every finding MUST have a `proof:` — a concrete sequence or value. No proof = LEAD.
- One root cause = one finding. Same fix needed across N modules = one finding with N locations.
- Do not flag: linter warnings, deprecation warnings, naming, missing events
  unless the missing event blocks a documented monitoring path.

## Quick Triggers

| User says | Mode |
|-----------|------|
| "audit Creek" / "scan contracts" | default |
| "deep audit" / "find vulnerabilities" | adversarial (still produces ONE report) |
| "audit `<filename>`" | scoped to that file, still overwrites the canonical report (note scope at top) |
| "re-audit" / "update audit" | re-run; overwrite report with fresh assessment based on current code |
