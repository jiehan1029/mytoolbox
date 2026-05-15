Setup that helps my workflows.

### Background tools

| Tool | Category | Purpose | Scope |
|------|----------|---------|-------|
| [caveman](https://github.com/JuliusBrussee/caveman) | context/token efficiency | Ultra-compressed communication mode. Reduces response verbosity; saves tokens on routine tasks. | global |
| [context-mode](https://github.com/mksglu/context-mode) | context/token efficiency | Stores command output in a sandbox instead of context window to prevent large outputs from flooding context. | global |
| [RTK (Rust Token Killer)](https://github.com/rtk-ai/rtk) | contex/token efficiency | rtk filters and compresses command outputs before they reach your LLM context. | global |
| [ccstatusline](https://github.com/sirmalloc/ccstatusline) | Claude Code tool | Enrich Claude Code status bar. | global |
| [claude-devtools](https://github.com/matt1398/claude-devtools) | Claude Code tool | The debugging tool for Claude Code. Read session transcripts, inspect tool calls, track token usage. | global |
| [context7](https://github.com/upstash/context7) | coding correctness | Ensure the agent uses correct API contract for a dependency | global |


### Things I choose to use

#### Superpowers
https://github.com/obra/superpowers

My default when need to do something serious.

#### Matt Pocock's skills
https://github.com/mattpocock/skills

Lightweight. /tdd is handy when fixing a bug. /improve-codebase-architecture is useful to find areas worth a refactor.

#### Gitnexus
https://github.com/abhigyanpatwari/GitNexus

When I need impact analysis and see the blast radius of the code change. Useful in reviews and refactors.

### Things I'm trying

#### Truecourse
https://github.com/truecourse-ai/truecourse

A curated list of checks. Language specific, only supports Python and JS/TS currently. Seems to be a low cost option to run better security/bug/quality/architecture checks (can work without LLM).

#### Graphify
https://github.com/safishamsi/graphify

A structured 'Karpathy method'. Good for large codebases and docs. But I do not like to store docs in codebase -- they drift from implementation easily. Still trying to figure out the best use case.

#### Shipguard
[Shipguard](./skills/shipguard/README.md) is a skill I made to gain confidence in releases. 

It's value proposition:

> I need to feel safe to release the code which I have not reviewed fully. The focus is not on feature completeness but on release safety -- full self-consistency, no migration risk, no cross-service contract violation, clear deploy dependency and rollback plan.

Still new and testing. In fact, /gitnexus-pr-review already does some of these works. Truecourse's checklist covered some as well. But this skill is more flexible (supposedly) than truecourse.


### Things I seldom or no longer use

#### Spec Kit
https://github.com/github/spec-kit

I like the concept, especially cross checks with 'constitution'. But the user flow isn't as smooth as superpowers and is heavier.

#### Devdocs
https://github.com/freeCodeCamp/devdocs

Useful only for a small collection of docs. Not good coverage.

### Gstack
https://github.com/garrytan/gstack

Too many tools I do not need, too self-convoluted. I hesitate to dive in before reading what all those skills are doing (but no time yet).