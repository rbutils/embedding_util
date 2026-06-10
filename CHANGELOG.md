## [0.1.5] - 2026-06-10

- Add lean Ramalama defaults with bounded `--ctx-size 4096` and disabled llama.cpp prompt cache via `--cache-ram 0`
- Split self-hosted embedding arrays into smaller endpoint batches to keep local document indexing within bounded context
- Preserve embedding output order across self-hosted batches

## [0.1.4] - 2026-06-10

- Stabilize managed Ramalama reranker startup, restart, and idle cleanup
- Add request-aware idle tracking so active embedding/reranking requests are not stopped during quiet server output
- Add `ramalama_device` configuration, CLI, and environment support for hosts that need `--device none`
- Retry managed reranker EOF/connection-drop failures once after escalating batch settings
- Verify stability through repeated `index_util/examples/ruby_api` queries

## [0.1.3] - 2026-06-10

- Set self-hosted reranker `--batch-size` and `--ubatch-size` together
- Retry managed reranker batch-size failures with both values raised to `4096`
- Update endpoint guidance to recommend increasing both llama.cpp batch-size settings for app-managed rerankers

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
