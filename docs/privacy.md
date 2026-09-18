# Privacy

Default behavior stores metadata, not full content.

Stored:

- session IDs
- timestamps
- token counts from Codex metadata
- output byte/character counts
- estimated token counts
- tool names and first command word
- hashes and byte sizes for `AGENTS.md` and `hooks.json`

Not stored:

- full prompts
- full assistant responses
- full command outputs
- API keys, cookies, bearer tokens, passwords, or environment values
- copies of Codex session files

The monitor reads Codex files read-only and writes only under this repository `data/` directory.
