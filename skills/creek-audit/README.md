# Creek Audit Skill

Project-level Cursor skill for security auditing Creek Protocol (Sui Move).

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Main entry — Cursor activates this when matching the description |
| `architecture.md` | Module map, capability inventory, money flow, pause surface |
| `attack-vectors.md` | Curated Sui Move attack patterns (generic + Creek-specific) |
| `checklists.md` | Per-module audit checklists |
| `recent-exploits.md` | 2025–2026 Sui DeFi case studies mapped to Creek |
| `judging.md` | Finding validation rubric (4 gates + confidence scoring) |
| `report-template.md` | Output format for audit reports |
| `findings/` | Where the canonical audit report is written (`creek-protocol-audit.md`) |
| `VERSION` | Skill semver — bump after meaningful update |

## How to invoke

In any Cursor chat in this repo, say:

- "audit Creek" — default pass
- "deep audit Creek" / "find vulnerabilities" — adversarial pass
- "audit `contracts/protocol/sources/staking/staking_manager.move`" — scoped
- "iterate audit round 3" — adversarial follow-up referencing prior report

## Iteration workflow

1. Run audit → report overwritten at `findings/creek-protocol-audit.md`
2. Review report; verify or refute each finding
3. If new patterns emerged, add them to `attack-vectors.md` / `checklists.md`
4. Bump `VERSION`
5. Re-run in adversarial mode until no new HIGH/CRITICAL findings

## Out of scope (always)

- `contracts_other/vendor/` — third-party packages (XAUM, USDC)
- `**/tests/`, `**/*_test.move` — test code
- `backend/`, `admin-panel/`, `scripts/`, frontends — off-chain (mentioned only when crossing trust boundary)

## Maintenance

Update this skill whenever:

- A new module is added or significantly refactored
- A capability changes scope (new holder, new ability)
- A new Sui DeFi exploit is published that maps onto Creek
- A finding is confirmed/refuted and the heuristic should be encoded

This skill is committed to the repo so the whole team uses the same baseline.
