## [0.1.1] - 2026-06-08

- Fix local server lifecycle cleanup for Ramalama and direct `llama-server`
- Stop named Ramalama servers after idle shutdown and fall back to Podman/Docker cleanup when needed
- Ensure direct `llama-server` child processes are terminated on idle shutdown and interruption

## [0.1.0] - 2026-06-08

- Initial release
- Add local-first embedding and true reranking API
- Add pinned `small_multilingual_v1` Qwen3 embedding/reranker profile
- Add endpoint provider for llama.cpp-compatible embedding/reranking APIs
- Add self-hosted local server management through Ramalama or direct `llama-server`
- Add `embedding_util` CLI with `support`, `profiles`, `embed`, `rerank`, and `serve`
