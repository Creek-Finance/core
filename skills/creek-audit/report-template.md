# Report Template

The audit produces **exactly one** report file at a stable path:

```
.cursor/skills/creek-audit/findings/creek-protocol-audit.md
```

This file is **overwritten** on every audit run. Each run produces a fresh
assessment of the current source tree — there is no carry-forward state
between runs. The report must read as a clean third-party assessment; do
not include "previously CRITICAL" / "after team review" / "post-fix"
narrative.

---

```markdown
# Creek Protocol Security Audit Report

**Audit date**: {YYYY-MM-DD}
**Last revised**: {YYYY-MM-DD HH:MM UTC+8}
**Skill version used**: {VERSION file content}
**Auditor**: AI-assisted audit using the `creek-audit` skill

---

## Executive Summary

Top concerns + counts table. Used as a 1-page snapshot.

## Audit Scope

|                                  |                                                            |
| -------------------------------- | ---------------------------------------------------------- |
| **Framework**                    | Sui Move 2024 (mainnet-v1.60.1)                            |
| **Files reviewed**               | {N files; list grouped by package}                         |
| **Attack vectors checked**       | {N} ({base} generic Sui Move + {Creek-specific})           |
| **Lenses applied**               | access-control · math · economic · invariant · execution · first-principles · sui-protocol |
| **Confidence threshold**         | 75                                                         |
| **Out of scope**                 | vendor/, tests/, contracts_other/                          |

### Files reviewed

- `contracts/protocol/sources/app/app.move`
- `contracts/protocol/sources/market/market.move`
- ... (group by directory; 3 per line acceptable)

### Out of scope (trust boundary)

- `contracts_other/vendor/xaum/`
- `contracts_other/vendor/usdc/`
- ...

---

## Summary

|  | Count |
|---|---|
| CRITICAL | N |
| HIGH | N |
| MEDIUM | N |
| LOW | N |
| INFO / LEAD | N |
| ADMIN-RISK | N |

Top concerns:

1. ...
2. ...
3. ...

---

## Findings

### [{confidence}] {NN}. {Title}

**Location**: `module::function_name`
**Confidence**: {NN}/100  ·  **Severity**: {CRITICAL|HIGH|MEDIUM|LOW}
**Tags**: `{class-1}` `{class-2}`  ·  Optional: `[ADMIN-RISK]` `[OFF-CHAIN]` `[KEEPER-DEPENDENT]` `[POST-UPGRADE]`

**Description**
One sentence: the vulnerable code pattern + why it's exploitable.

**Code reference**

```{startLine}:{endLine}:{filepath}
// actual vulnerable code
```

**Proof / exploit path**
1. Attacker calls X with input Y
2. State Z mutates
3. Attacker withdraws / drains via W

Concrete values: `amount = 1`, `pool = 100`, etc.

**Fix** (only if confidence ≥ 80)

```diff
- vulnerable line(s)
+ fixed line(s)
```

Alternative fix options or trade-offs (if relevant).

---

### [{lower-conf}] {NN+1}. {Title}

(below threshold — description + proof only, no Fix block)

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path
could not be completed in one analysis pass. These are not false positives —
they are high-signal leads for manual review. Not scored._

- **{Title}** — `module::function` — Code smells: `{...}` — {1-2 sentence trail and what remains unverified}.

---

## Out-of-Scope Observations (informational)

- ...

---

## Findings Index

| # | Severity | Confidence | Title | Location |
|---|---|---|---|---|
| 1 | CRITICAL | 95 | ... | ... |
| 2 | HIGH | 88 | ... | ... |
| 3 | MEDIUM | 78 | ... | ... |

---

## Methodology Notes

- Audit performed by AI assistant using `.cursor/skills/creek-audit` v{VERSION}.
- {N} attack vectors evaluated (see `attack-vectors.md`).
- Domain checklists applied for: lending, staking, oracle, coins, pause+limits, upgrade.
- All findings passed the 4-gate validation in `judging.md`.

---

> This review was performed by an AI assistant. AI analysis can never verify the
> complete absence of vulnerabilities and no guarantee of security is given.
> Independent professional audit, formal verification (Sui Prover where
> applicable), bug bounty programs, and continuous on-chain monitoring are
> strongly recommended.
```
