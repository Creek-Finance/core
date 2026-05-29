# Finding Validation Rubric

Every candidate finding passes four sequential gates. Fail any gate →
**REJECTED** or **DEMOTED** to LEAD. Later gates are not evaluated for
failed findings.

## Gate 1 — Refutation

Construct the strongest argument that the finding is wrong. Find the guard,
assertion, capability check, ability restriction that kills the attack — quote
the exact line and trace how it blocks the claimed step.

- Concrete refutation (specific guard blocks exact claimed step) → **REJECTED**
  (or **DEMOTE** if a code smell remains)
- Speculative refutation ("probably wouldn't happen") → clears, continue

## Gate 2 — Reachability

Prove the vulnerable state is reachable in a live deployment. Consider:

- Shared objects accessible by any tx; owned objects only by owner
- `public(package)` callable from same-package modules — not "private"
- Dynamic field access — anyone can read; mutation gated by parent access

Outcomes:
- Structurally impossible (enforced invariant or ability restriction) → **REJECTED**
- Requires privileged actions outside normal operation (AdminCap, UpgradeCap, multisig) → **DEMOTE to ADMIN-RISK**
- Achievable through normal usage, PTB composition, or common Coin behaviors → clears, continue

## Gate 3 — Trigger

Prove an unprivileged actor can execute the attack profitably.

- Only cap-holders can trigger → **DEMOTE** (or keep as ADMIN-RISK)
- Costs exceed extraction → **REJECTED** (note as INFO if interesting)
- Unprivileged actor triggers profitably → clears, continue

## Gate 4 — Impact

Prove material harm to an identifiable victim.

- Self-harm only (user shoots own foot) → **REJECTED**
- Dust-level, no compounding → **DEMOTE**
- Material loss to identifiable victim → **CONFIRMED**

## Confidence Scoring

Start at **100**, deduct:

- partial attack path traced: **-20**
- bounded non-compounding impact: **-15**
- requires specific (but achievable) state: **-10**
- requires keeper/admin inaction window: **-10**
- requires another vector chained: **-5** (per chain step)

Confidence ≥ 80 → include description + `proof` + Fix block.
Confidence 60–79 → description + `proof`, no Fix block.
Confidence < 60 → demote to LEAD (no scoring).

## Severity Labels

For the report's table-of-contents, map confidence → severity:

| Confidence | Label | Meaning |
|---|---|---|
| 95–100 | CRITICAL | Direct fund theft, fully unprivileged trigger |
| 85–94 | HIGH | Material loss, partial chain or specific state |
| 75–84 | MEDIUM | Locking funds, DoS, indirect loss, transitional design risk |
| 60–74 | LOW | Edge case, requires alignment, operational concern |
| <60 | INFO / LEAD | Smell, hardening, design choice |

Before assigning a severity label, run the **severity calibration** in
`checklists.md` — placeholder/transitional configurations and operationally-
mitigated init windows must be calibrated DOWN (not up). The report should
never display a CRITICAL finding that is then "explained away" in the same
finding; if context downgrades it, assign the lower severity from the start
and state the calibrating fact briefly in the description.

Special tags (orthogonal to confidence):

- **`[ADMIN-RISK]`** — exploit requires admin cooperation (rug)
- **`[OFF-CHAIN]`** — exploit crosses the Move boundary (e.g. key compromise)
- **`[KEEPER-DEPENDENT]`** — exploit window opens if keeper is offline
- **`[POST-UPGRADE]`** — exploit becomes reachable if a future upgrade omits a check
- **`[TRANSITIONAL]`** — finding describes a launch-phase configuration with a documented migration plan (severity already calibrated)

## Do NOT Report

- Linter / compiler warnings
- Gas micro-optimizations
- Naming / documentation
- Missing events unless they block a documented monitoring path
- `AdminCap` doing admin things (capability-gated by design) — unless it
  diverges from documented privileged paths
- Standard Move arithmetic abort (it's by design)
- Self-harm-only (user shoots own foot)
- "Multisig can rug" without a concrete privilege divergence

## Safe Patterns

The following are NOT findings on their own:

- Hot potato pattern (no `drop`, no `store`)
- Owned-object isolation
- `assert!` guards covering the attack path
- Virtual shares / minimum deposit for first-depositor inflation
- Consistent protocol-favoring rounding (unless compounding or zero-rounding)
- `OneTimeLockValue` timelock pattern
- Capability transferred from `init` to deployer

## Lead Promotion

Before finalizing, promote LEADs where warranted:

- **Cross-module echo** — same root cause CONFIRMED in module A → promote in
  every module where the identical pattern appears.
- **Multi-lens convergence** — 2+ lenses (access-control + invariant +
  math, etc.) flagged the same area → promote to FINDING at confidence 75.
- **Partial-path completion** — only weakness is incomplete trace, but path
  is reachable and unguarded → promote to FINDING at confidence 75 (no Fix).
