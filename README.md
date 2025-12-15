# AFM Server

A minimal Swift daemon that exposes Apple's on-device Foundation Models via an OpenAI-compatible API.

## Features

- **OpenAI-compatible API** - Works with any OpenAI client library
- **On-device inference** - No cloud, no API keys, no costs
- **Privacy-first** - All processing happens locally
- **Minimal** - Just the essentials, nothing more

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (M1 or later)
- Apple Intelligence enabled (Settings → Apple Intelligence & Siri)
- Xcode 26 or later (for building from source)

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/v1/models` | GET | List available models |
| `/v1/chat/completions` | POST | Chat completions (streaming & non-streaming) |

## Usage

### Start the server

1. Build and run the app from Xcode
2. The server starts automatically on `http://127.0.0.1:11535`

### Example: cURL

```bash
# Health check
curl http://127.0.0.1:11535/health

# List models
curl http://127.0.0.1:11535/v1/models

# Chat completion
curl -X POST http://127.0.0.1:11535/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-on-device",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Streaming
curl -X POST http://127.0.0.1:11535/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-on-device",
    "messages": [{"role": "user", "content": "Tell me a joke"}],
    "stream": true
  }'
```

### Example: Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:11535/v1",
    api_key="not-needed"  # No API key required
)

response = client.chat.completions.create(
    model="apple-on-device",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is the capital of France?"}
    ]
)

print(response.choices[0].message.content)
```

### Example: Rust (with async-openai)

```rust
use async_openai::{Client, config::OpenAIConfig};

let config = OpenAIConfig::new()
    .with_api_base("http://127.0.0.1:11535/v1")
    .with_api_key("not-needed");

let client = Client::with_config(config);

let request = CreateChatCompletionRequestArgs::default()
    .model("apple-on-device")
    .messages(vec![
        ChatCompletionRequestMessage::User(
            ChatCompletionRequestUserMessage::from("Hello!")
        ),
    ])
    .build()?;

let response = client.chat().create(request).await?;
```

## Building from Source

```bash
git clone https://github.com/yourusername/afm-server.git
cd afm-server
open Package.swift  # Opens in Xcode
# Build and run from Xcode
```

## Why a GUI App?

Apple rate-limits CLI tools using the Foundation Models framework, but foreground GUI apps have no such limit. This is why AFM Server runs as a minimal SwiftUI app rather than a command-line tool.

## Supported Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | string | required | Model ID (use "apple-on-device") |
| `messages` | array | required | Conversation messages |
| `temperature` | float | 0.7 | Sampling temperature (0.0-2.0) |
| `max_tokens` | int | - | Maximum response length |
| `stream` | bool | false | Enable streaming responses |

## Limitations

- Requires macOS 26+ (currently in beta)
- Only supports text generation (no images, embeddings, etc.)
- The on-device model (~3B parameters) is optimized for:
  - Summarization
  - Classification
  - Extraction
  - Simple Q&A
- Not suitable for:
  - World knowledge queries
  - Advanced reasoning
  - Long-form content generation

## License

MIT

## Acknowledgments

- Inspired by [apple-on-device-openai](https://github.com/gety-ai/apple-on-device-openai)
- Built with [Hummingbird](https://github.com/hummingbird-project/hummingbird)
