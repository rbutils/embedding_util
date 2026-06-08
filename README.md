# embedding_util

Local-first text embeddings and reranking for Ruby.

`embedding_util` provides a small require-and-use API for computing embedding vectors and true reranking scores through local model runtimes. It can start local model servers on demand, or use explicitly configured llama.cpp/Ramalama-compatible HTTP endpoints.

The default model profile is `small_multilingual_v1`, pinned to Qwen3 0.6B GGUF embedding and reranker models.

This gem is in the `0.x` series. The API is intentionally unstable until `1.0`, and public method names, configuration options, return shapes, and default profiles may change between minor releases.

## Installation

Add the gem to your Gemfile:

```ruby
gem "embedding_util"
```

Then install dependencies:

```sh
bundle install
```

## Quick Start

Install either `ramalama` or `llama-server`. Ramalama is preferred; direct `llama-server` is used when Ramalama is unavailable.

Then call the Ruby API:

```ruby
require "embedding_util"

vector = EmbeddingUtil.embed("hello world")
ranked = EmbeddingUtil.rerank("Which document is about software?", [
  "Ruby is a programming language.",
  "Fresh bread is often served warm.",
  "A command-line tool can automate repetitive work."
])
```

With the default configuration, `EmbeddingUtil.embed` and `EmbeddingUtil.rerank` reuse an already-running local server when one is available. If not, they start the required local model server automatically. Auto-started servers bind to `127.0.0.1`, prefer ports `18080` for embeddings and `18081` for reranking, and choose the next free local port if the preferred port is already in use. First-time use downloads the pinned `small_multilingual_v1` GGUF files through the selected runtime.

## Application-Managed Servers

Applications can manage model servers themselves instead of using automatic self-hosting. This is useful when the embedding/reranking servers run as separate processes, system services, containers, or on another machine.

Configure the endpoints explicitly:

```ruby
require "embedding_util"

EmbeddingUtil.configure do |config|
  config.embedding_endpoint = "http://embedding.internal:18080"
  config.reranker_endpoint = "http://reranker.internal:18081"
end

vector = EmbeddingUtil.embed("hello world")
```

Configured endpoints take precedence over automatic self-hosting.

`embedding_util serve` is one convenient way to run compatible servers yourself, but it is optional. You can also run Ramalama, direct `llama-server`, containers, or service units independently as long as they expose llama.cpp-compatible embedding/reranking HTTP APIs.

```sh
embedding_util serve --model embedding-small_multilingual_v1
embedding_util serve --model reranker-small_multilingual_v1
```

`serve` starts one model server per command and runs until stopped. Add `--shutdown-idle SECONDS` only when you want that manually managed server to stop itself after idle output; omit it, set it to `nil`, or pass `0` to disable idle shutdown.

## CLI

```sh
embedding_util support
embedding_util profiles
embedding_util serve --model embedding-small_multilingual_v1
embedding_util embed "hello world"
embedding_util embed "hello world" --verbose
embedding_util rerank \
  "Which document is about software?" \
  "Ruby is a programming language." \
  "Fresh bread is often served warm." \
  "A command-line tool can automate repetitive work."
```

`embed` prints a JSON array. `rerank` prints JSON objects with `index`, `document`, `score`, and `metadata`.

`serve` starts one local model server. The default model is `embedding-small_multilingual_v1`; use `reranker-small_multilingual_v1` for the reranker server. By default, `serve` uses Ramalama when available and falls back to direct `llama-server`. It runs until stopped unless a positive `--shutdown-idle` value is provided.

Explicit `serve --port PORT` requires that exact port to be free. Without `--port`, `serve` prefers the profile default port and chooses the next free local port if needed.

Use `--verbose` on `embed` or `rerank` to print self-hosting diagnostics, including the background `serve` command and log path. First-time model downloads are expected to work with the default startup timeout; use `--startup-timeout` only when you explicitly want to shorten or extend that wait.

## API

- `EmbeddingUtil.embed(text)` returns one embedding array.
- `EmbeddingUtil.embed_many(texts)` returns one embedding array per input text.
- `EmbeddingUtil.embed_result(text_or_texts)` returns embeddings plus provider/model metadata.
- `EmbeddingUtil.rerank(query, documents)` returns ranked `EmbeddingUtil::RankedDocument` objects.
- `EmbeddingUtil.rerank_result(query, documents)` returns ranked documents plus provider/model metadata.
- `EmbeddingUtil.support` reports configured provider support.
- `EmbeddingUtil.profiles` returns known immutable model profiles.
- `embedding_util support`, `profiles`, `embed`, `rerank`, and `serve` expose the same local-first behavior from the command line.

## Default Profile

`small_multilingual_v1` is intentionally pinned because embedding vectors are model-output-specific.

Embedding model:

- repo: `Qwen/Qwen3-Embedding-0.6B-GGUF`
- file: `Qwen3-Embedding-0.6B-Q8_0.gguf`
- dimensions: `1024`
- server flags: `--embedding --pooling last`

Reranker model:

- repo: `ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF`
- file: `qwen3-reranker-0.6b-q8_0.gguf`
- server flags: `--reranking`

Do not combine embedding and reranking flags for this profile. Run separate local servers.

## Configuration

```ruby
EmbeddingUtil.configure do |config|
  config.profile = :small_multilingual_v1
  config.runtime = :auto
  config.host = "127.0.0.1"
  config.embedding_port = 18080
  config.reranker_port = 18081
  config.startup_timeout = 3600
  config.shutdown_idle = 300
  config.timeout = 60
end
```

Explicit local endpoints can still be configured when you manage servers yourself:

```ruby
EmbeddingUtil.configure do |config|
  config.embedding_endpoint = "http://127.0.0.1:18080"
  config.reranker_endpoint = "http://127.0.0.1:18081"
end
```

Environment variables are also supported:

- `EMBEDDING_UTIL_ENDPOINT` for one endpoint serving both APIs
- `EMBEDDING_UTIL_EMBEDDING_ENDPOINT`
- `EMBEDDING_UTIL_RERANKER_ENDPOINT`
- `EMBEDDING_UTIL_TIMEOUT`
- `EMBEDDING_UTIL_STARTUP_TIMEOUT`
- `EMBEDDING_UTIL_RUNTIME`
- `EMBEDDING_UTIL_SHUTDOWN_IDLE`
- `EMBEDDING_UTIL_STATE_DIR`
- `EMBEDDING_UTIL_VERBOSE`
- `EMBEDDING_UTIL_EMBEDDING_PORT`
- `EMBEDDING_UTIL_RERANKER_PORT`

## Development

```sh
bundle install
bundle exec rake
```

## Contributing

Bug reports and pull requests are welcome on GitHub at `https://github.com/rbutils/embedding_util`.

## License

The gem is available as open source under the terms of the MIT License.
