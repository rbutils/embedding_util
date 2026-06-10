## [0.1.2] - 2026-06-10

- Add self-hosted reranker recovery for llama.cpp physical batch-size failures
- Start managed reranker servers with `--ubatch-size 1024`
- Restart managed reranker servers once with `--ubatch-size 4096` when larger rerank requests require it
- Add configuration and CLI options for reranker ubatch defaults and maximums
- Add clearer guidance for app-managed reranker endpoints that need a larger `--ubatch-size`

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
