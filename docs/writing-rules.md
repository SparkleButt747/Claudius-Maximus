# Writing Your Own CLAUDE.md

The `CLAUDE.md` file is the single most impactful component of the harness. It's the system prompt injected into every container, and it defines how the agent approaches tasks.

## Structure

A good CLAUDE.md follows this structure:

1. **Identity statement** — tell the agent what it is and what it's optimising for
2. **Mandatory workflow** — phases the agent must follow (Bootstrap → Understand → Plan → Execute → Verify)
3. **Verification protocol** — specific rules to prevent false success claims
4. **Failure recovery** — escalation ladder for when things go wrong
5. **Efficiency constraints** — rules to prevent wasted turns
6. **Task patterns** — category-specific guidance (optional, can be in a separate file)
7. **Anti-patterns** — explicit list of things NOT to do

## Key Principles

### Be directive, not suggestive

Bad: "You might want to consider reading the test files before implementing."
Good: "Read test files BEFORE implementing. Tests are ground truth."

### Make phases mandatory

The agent will skip phases if they're optional. Use words like "MANDATORY", "MUST", "NEVER skip".

### Hammer the failure modes

The top failure modes are consistent across benchmarks:
1. Not running verification → forced verification protocol
2. Building the wrong thing → test-first strategy
3. Looping on errors → explicit loop detection guidance
4. Missing tools → mandatory bootstrapping
5. Wrong output format → exact-match verification guidance

### Keep it focused

The included `CLAUDE.md` is ~260 lines. Longer prompts waste tokens and dilute the key messages. Every line should earn its place.

### Binary scoring awareness

Most benchmarks use binary pass/fail scoring. The agent should know:
- No partial credit — a 99% solution scores 0
- Once tests pass, STOP optimising
- A working 80% solution beats a failed 100% attempt

## Customisation Checklist

When adapting CLAUDE.md for a new benchmark:

- [ ] Update the bootstrap command for your environment (paths, tools)
- [ ] Update test file locations if different from `/app/tests/`
- [ ] Add benchmark-specific task patterns
- [ ] Adjust the verification command for your test framework
- [ ] Add domain-specific anti-patterns
- [ ] Review token budget — remove sections that don't apply

## Testing Your CLAUDE.md

Use `scripts/local_test.sh` to validate your prompt with mock tasks:

```bash
# Test with a simple task
bash harness/scripts/local_test.sh --task simple

# Test with a harder task
bash harness/scripts/local_test.sh --task hard
```

This creates a mock container environment, injects your CLAUDE.md, and shows you the command to run Claude Code against it.
