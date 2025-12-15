# AFM Server

Minimal OpenAI-compatible API for Apple's on-device Foundation Models. Zero dependencies, runs as a menu bar app.

## Requirements

- macOS 26+, Apple Silicon, Apple Intelligence enabled

## Install & Run

```bash
git clone https://github.com/kulesh/afm-server.git
cd afm-server
swift run
```

Look for the 🧠 icon in your menu bar.

## API

**Base URL:** `http://127.0.0.1:11535`

```bash
# Health check
curl http://127.0.0.1:11535/health

# Chat completion
curl -X POST http://127.0.0.1:11535/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-on-device","messages":[{"role":"user","content":"Hello"}]}'
```

Works with any OpenAI client library:

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:11535/v1", api_key="x")
response = client.chat.completions.create(
    model="apple-on-device",
    messages=[{"role": "user", "content": "Hello"}]
)
```

## Limitations

- **4096 token context window**
- Best for: summarization, classification, extraction
- Not for: world knowledge, complex reasoning

## Why a menu bar app?

Apple rate-limits CLI tools using Foundation Models. GUI apps have no such limit.

## License

MIT
