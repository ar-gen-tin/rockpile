# Rockpile — Development Guidelines

## Development Methodology

This project follows the **Ten Development Rules** (see `SKILL.md`).

Every task — feature, bugfix, refactor, review — must follow this workflow:

1. **Boundary** — State what the task solves and what it does NOT solve. Tighten scope before coding.
2. **Contract** — Define types/interfaces/APIs other work depends on. Freeze before parallel work.
3. **Dependency order** — Build foundations (Models → Services → Views). Never build consumers before providers are stable.
4. **Stage** — Split into small phases with clear outputs. Contract → Schema → Service → UI → Review → Verify.
5. **Isolate** — New logic in new files. Don't pollute shared core. Abstract only after repeated pressure.
6. **Review loop** — Implementation + review + fix + re-verify = one loop. Not done until verified.
7. **Failure paths** — Timeouts, retries, rate limits, auth failures, partial data. Unhappy paths are first-class.
8. **Compress docs** — Minimum docs that restore context. Living specs, not historical novels.
9. **Verify reality** — Runtime behavior, not just builds. State what was tested, skipped, and risky.
10. **Distill** — Extract reusable principles. End with a formula.

## Anti-Patterns (DO NOT)

- Don't design the full future when the task is narrow
- Don't let UI drive contracts that Services haven't stabilized
- Don't abstract early because two things "look similar"
- Don't treat review/tests as ceremonial checkboxes
- Don't write docs that preserve history but hide current truth

## Project Conventions

- **Language**: Swift 6, macOS 15+, strict concurrency (@MainActor + @Observable)
- **Build**: `xcodegen generate && xcodebuild -project Rockpile.xcodeproj -scheme Rockpile`
- **Version source**: `project.yml` → `MARKETING_VERSION`
- **Architecture**: AppDelegate → StateMachine → SessionStore → UI (SwiftUI)
- **Hook system**: `~/.claude/hooks/rockpile-hook.sh` → Unix socket `/tmp/rockpile.sock`
- **Deploy**: Security check → `git commit` → `git push origin main`

## Security Checklist (Before Every Push)

- [ ] No API keys, tokens, or secrets in code
- [ ] No personal paths (`/Users/artin`), IPs, or account IDs
- [ ] No `.env`, `.key`, `.pem` files tracked
- [ ] `.gitignore` covers sensitive paths
- [ ] Public repo — treat every line as visible to the world

## Commit Style

```
type: 简短中文描述

## 详细内容 (if needed)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```

Types: `feat`, `fix`, `refactor`, `docs`, `release`, `chore`
