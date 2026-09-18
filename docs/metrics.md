# Metrics

Exact token metrics come only from Codex `event_msg` records where `payload.type` is `token_count`.

Supported exact fields:

- `inputTokensExact`
- `cachedInputTokensExact`
- `outputTokensExact`
- `totalTokensExact`

Estimated fields:

- `estimatedOutputTokens`
- `estimatedUserMessageTokens`

Estimate heuristic is `ceil(characters / 4)`. It is not model-tokenizer exact.

Compaction is currently heuristic only: a drop below 70% of previous exact input-token sample records `suspectedCompactions`.
