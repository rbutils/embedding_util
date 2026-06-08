# embedding_util

Local-first text embeddings and reranking for Ruby.

`embedding_util` provides a small require-and-use API for computing embedding vectors and true reranking scores through local model runtimes. The first implementation targets already-running llama.cpp/Ramalama-compatible HTTP endpoints; automatic local provisioning will be designed separately.

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

Start compatible local endpoints separately. For the default Qwen3 profile, use separate embedding and reranking servers.

### Option 1: Ramalama

Ramalama is the preferred local runtime path. It manages local model storage and, when needed, pulls the specified model before serving it. The commands below use pinned Hugging Face file URLs so the `small_multilingual_v1` profile stays tied to exact GGUF files.

Embedding server shape:

```sh
ramalama --runtime=llama.cpp serve \
  --name embedding-util-embed \
  --port 18080 \
  --runtime-args="--embedding --pooling last" \
  https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf
```

Reranker server shape:

```sh
ramalama --runtime=llama.cpp serve \
  --name embedding-util-rerank \
  --port 18081 \
  --runtime-args="--reranking" \
  https://huggingface.co/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/resolve/main/qwen3-reranker-0.6b-q8_0.gguf
```

Use `ramalama stop embedding-util-embed` and `ramalama stop embedding-util-rerank` to stop the servers.

### Option 2: llama-server

Use direct llama.cpp serving when you already have `llama-server` available. These commands also download the pinned files from Hugging Face if llama.cpp has Hugging Face download support enabled.

Embedding server shape:

```sh
llama-server \
  -hf Qwen/Qwen3-Embedding-0.6B-GGUF \
  -hff Qwen3-Embedding-0.6B-Q8_0.gguf \
  --embedding --pooling last \
  --port 18080
```

Reranker server shape:

```sh
llama-server \
  -hf ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF \
  -hff qwen3-reranker-0.6b-q8_0.gguf \
  --reranking \
  --port 18081
```

Then call the Ruby API:

```ruby
require "embedding_util"

EmbeddingUtil.configure do |config|
  config.embedding_endpoint = "http://127.0.0.1:18080"
  config.reranker_endpoint = "http://127.0.0.1:18081"
end

vector = EmbeddingUtil.embed("hello world")
ranked = EmbeddingUtil.rerank("Which document is about software?", [
  "Ruby is a programming language.",
  "Fresh bread is often served warm.",
  "A command-line tool can automate repetitive work."
])
```

## CLI

Repo-local usage:

```sh
bundle exec exe/embedding_util support \
  --embedding-endpoint http://127.0.0.1:18080 \
  --reranker-endpoint http://127.0.0.1:18081

bundle exec exe/embedding_util profiles

bundle exec exe/embedding_util embed "hello world" \
  --embedding-endpoint http://127.0.0.1:18080

bundle exec exe/embedding_util rerank \
  --reranker-endpoint http://127.0.0.1:18081 \
  "Which document is about software?" \
  "Ruby is a programming language." \
  "Fresh bread is often served warm." \
  "A command-line tool can automate repetitive work."
```

Installed gem usage:

```sh
embedding_util support --embedding-endpoint http://127.0.0.1:18080 --reranker-endpoint http://127.0.0.1:18081
embedding_util profiles
embedding_util embed "hello world" --embedding-endpoint http://127.0.0.1:18080
```

`embed` prints a JSON array. `rerank` prints JSON objects with `index`, `document`, `score`, and `metadata`.

## API

- `EmbeddingUtil.embed(text)` returns one embedding array.
- `EmbeddingUtil.embed_many(texts)` returns one embedding array per input text.
- `EmbeddingUtil.embed_result(text_or_texts)` returns embeddings plus provider/model metadata.
- `EmbeddingUtil.rerank(query, documents)` returns ranked `EmbeddingUtil::RankedDocument` objects.
- `EmbeddingUtil.rerank_result(query, documents)` returns ranked documents plus provider/model metadata.
- `EmbeddingUtil.support` reports configured provider support.
- `EmbeddingUtil.profiles` returns known immutable model profiles.
- `embedding_util support`, `profiles`, `embed`, and `rerank` expose the same endpoint-backed behavior from the command line.

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
  config.embedding_endpoint = "http://127.0.0.1:18080"
  config.reranker_endpoint = "http://127.0.0.1:18081"
  config.timeout = 60
end
```

Environment variables are also supported:

- `EMBEDDING_UTIL_ENDPOINT` for one endpoint serving both APIs
- `EMBEDDING_UTIL_EMBEDDING_ENDPOINT`
- `EMBEDDING_UTIL_RERANKER_ENDPOINT`
- `EMBEDDING_UTIL_TIMEOUT`

## Development

```sh
bundle install
bundle exec rake
```

## Contributing

Bug reports and pull requests are welcome on GitHub at `https://github.com/rbutils/embedding_util`.

## License

The gem is available as open source under the terms of the MIT License.
