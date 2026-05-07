Setup that helps my workflows.

### Background tools

| Tool | Category | Purpose | Scope | Source |
|------|----------|---------|-------|--------|
| caveman | context/token efficiency | Ultra-compressed communication mode. Reduces response verbosity; saves tokens on routine tasks. | global | https://github.com/JuliusBrussee/caveman |
| context-mode | context/token efficiency | Stores command output in a sandbox instead of context window to prevent large outputs from flooding context. | global | https://github.com/mksglu/context-mode |
| RTK (Rust Token Killer) | contex/token efficiency | rtk filters and compresses command outputs before they reach your LLM context. | global | https://github.com/rtk-ai/rtk |
| ccstatusline | Claude Code tool | Enrich Claude Code status bar. | global | https://github.com/sirmalloc/ccstatusline |
| claude-devtools | Claude Code tool | The debugging tool for Claude Code. Read session transcripts, inspect tool calls, track token usage. | global | https://github.com/matt1398/claude-devtools |


### Things I choose to use

#### Superpowers
My default when need to do something serious.

#### Matt Pocock's skills
Lightweight. /tdd is handy when fixing a bug.

### Things I'm trying

#### Gitnexus
When I need impact analysis and see the blast radius of the code change.

#### Graphify
A structured 'Karpathy method'. Good for large codebases and docs. But I do not like to store docs in codebase -- they drift from implementation easily. Still trying to figure out the best use case.

#### Devdocs
Looks like an alternative to context7.

### Things I no longer (or seldom) use

#### Spec Kit
I like the concept, especially cross checks with 'constitution'. But the user flow isn't as smooth as superpowers and is heavier.
