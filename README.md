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

### Tool Use (OpenAI-style)

AFM Server supports OpenAI-compatible `tools`, `tool_choice`, and assistant `tool_calls`.

Built-in tools in this server:
- `current_time` - returns current time in optional IANA timezone.
- `math_add` - adds a list of numbers.
- `echo` - returns input text (useful for integration testing).

Discover built-ins:

```bash
curl http://127.0.0.1:11535/v1/tools
```

Python example:

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:11535/v1", api_key="x")

resp = client.chat.completions.create(
    model="apple-on-device",
    messages=[{"role": "user", "content": "What time is it in Los Angeles?"}],
    tools=[
        {
            "type": "function",
            "function": {
                "name": "current_time",
                "description": "Get current time by timezone",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "timezone": {"type": "string"}
                    }
                }
            }
        }
    ],
    tool_choice="auto",
)

print(resp.choices[0].message)
```

### What Tools Exist on macOS/iOS?

Apple Foundation Models does not provide a fixed built-in catalog of app-level tools. You define tools in your app (Swift `Tool` types) and can back them with platform capabilities you already have access to, for example:
- EventKit (calendar/reminders)
- Contacts
- CoreLocation/MapKit
- WeatherKit
- Local app data/services

AFM Server intentionally restricts this to its curated built-in tool registry for safety.

## Limitations

- **4096 token context window**
- Best for: summarization, classification, extraction
- Not for: world knowledge, complex reasoning

## Why a menu bar app?

Apple rate-limits CLI tools using Foundation Models. GUI apps have no such limit.

## License

MIT
