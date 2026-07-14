# Telegram Bot — Stage 1 Specification
## Basic Chatbot with LLM + Conversation Memory

---

### 1. System Overview

**What it does:**
- Runs a Telegram bot using aiogram 3.x inside a FastAPI application (single container)
- Provides a universal LLM provider abstraction (Ollama local → OpenRouter → extensible)
- Maintains conversation memory with summarization (keep recent raw, summarize older)
- Responds to all private chat messages with streaming token output
- Implements `/start` and `/help` commands
- Configured entirely via `.env` (provider, model, API keys, Ollama host URL)

**What it does NOT do (Stage 1):**
- No pgvector / vector database (Stage 2)
- No document ingestion / RAG (Stage 2)
- No WooCommerce product sync / API integration (Stage 2+)
- No checkout / payment flows (Stage 3)
- No webhook handling from WordPress (Stage 2+)

---

### 2. Data Models

```python
# bot/config.py
class Settings(BaseSettings):
    # Telegram
    BOT_TOKEN: str
    
    # LLM Provider
    LLM_PROVIDER: Literal["ollama", "openrouter"] = "ollama"
    LLM_MODEL: str = "llama3:8b"
    
    # Ollama
    OLLAMA_BASE_URL: str = "http://host.docker.internal:11434"
    
    # OpenRouter
    OPENROUTER_API_KEY: str | None = None
    OPENROUTER_BASE_URL: str = "https://openrouter.ai/api/v1"
    
    # Memory
    MEMORY_MAX_RAW_MESSAGES: int = 10
    MEMORY_SUMMARIZE_THRESHOLD: int = 20
    MEMORY_SUMMARY_MODEL: str | None = None  # defaults to LLM_MODEL
    
    # Streaming
    STREAM_CHUNK_DELAY_MS: int = 50
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"

# bot/llm/providers/base.py
class Message(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str

class ChatResponse(BaseModel):
    content: str
    model: str
    usage: dict | None = None

# bot/memory/conversation.py
class ConversationMemory:
    user_id: int
    raw_messages: list[Message]  # recent messages kept verbatim
    summary: str | None          # summarized older history
    updated_at: datetime
    
    def add_message(self, message: Message) -> None: ...
    def get_context(self, system_prompt: str) -> list[Message]: ...
    def maybe_summarize(self, llm_provider: LLMProvider) -> None: ...
```

---

### 3. Function Signatures

```python
# bot/llm/providers/base.py
class LLMProvider(Protocol):
    async def chat(
        self, 
        messages: list[Message], 
        model: str, 
        stream: bool = False,
        temperature: float = 0.7,
        max_tokens: int | None = None
    ) -> AsyncIterator[str] | str:
        """Returns stream of tokens if stream=True, else full response string."""
    
    async def embed(
        self, 
        texts: list[str], 
        model: str
    ) -> list[list[float]]:
        """Returns embeddings for each input text. Not used in Stage 1."""

# bot/llm/providers/ollama.py
class OllamaProvider:
    def __init__(self, base_url: str): ...
    async def chat(...) -> AsyncIterator[str] | str: ...
    async def embed(...) -> list[list[float]]: ...

# bot/llm/providers/openrouter.py
class OpenRouterProvider:
    def __init__(self, api_key: str, base_url: str): ...
    async def chat(...) -> AsyncIterator[str] | str: ...
    async def embed(...) -> list[list[float]]: ...

# bot/llm/factory.py
def get_provider(settings: Settings) -> LLMProvider:
    """Factory: returns OllamaProvider or OpenRouterProvider based on settings.LLM_PROVIDER."""

# bot/memory/conversation.py
class ConversationMemory:
    def __init__(self, user_id: int, max_raw: int = 10, summarize_threshold: int = 20): ...
    def add_message(self, message: Message) -> None: ...
    def get_context(self, system_prompt: str) -> list[Message]:
        """Returns [system_prompt, summary (if exists), recent raw messages]."""
    async def maybe_summarize(self, provider: LLMProvider, model: str) -> None:
        """If raw_messages > threshold, summarize oldest half via LLM, prepend to summary."""

# bot/handlers/commands.py
async def cmd_start(message: Message, state: FSMContext, memory: ConversationMemory) -> None:
    """Sends welcome + personality intro, initializes memory for user."""
    
async def cmd_help(message: Message) -> None:
    """Lists available commands with brief descriptions."""

# bot/handlers/messages.py
async def handle_text(message: Message, state: FSMContext, memory: ConversationMemory, provider: LLMProvider, settings: Settings) -> None:
    """Main message handler:
    1. Add user message to memory
    2. Build context (system_prompt + summary + recent raw)
    3. Call provider.chat(stream=True)
    4. Stream tokens to Telegram via message.answer() + edits
    5. Save assistant response to memory
    6. Trigger maybe_summarize()"""

# bot/main.py
async def on_startup(dispatcher: Dispatcher, settings: Settings) -> None:
    """Initialize provider, register handlers, set bot commands."""

async def on_shutdown(dispatcher: Dispatcher) -> None:
    """Cleanup."""

def create_app(settings: Settings) -> FastAPI:
    """Create FastAPI app with aiogram webhook endpoint (or polling for dev)."""
```

---

### 4. File Structure

```
bot/
├── Dockerfile
├── requirements.txt
├── .env.example
├── main.py                    # FastAPI app entrypoint, aiogram setup
├── config.py                  # Pydantic Settings
├── llm/
│   ├── __init__.py
│   ├── providers/
│   │   ├── __init__.py
│   │   ├── base.py            # LLMProvider protocol
│   │   ├── ollama.py
│   │   └── openrouter.py
│   └── factory.py             # get_provider()
├── memory/
│   ├── __init__.py
│   └── conversation.py        # ConversationMemory class
├── handlers/
│   ├── __init__.py
│   ├── commands.py            # /start, /help
│   └── messages.py            # Text message handler
├── middleware/
│   ├── __init__.py
│   └── logging.py             # Request/response logging
└── utils/
    ├── __init__.py
    └── streaming.py           # Token streaming helpers
```

**Docker files (repo root):**
```
docker-compose.yml              # Updated with bot service
docker-compose.wp.yml           # WP stack only (db, wordpress, nginx, phpmyadmin)
docker-compose.bot.yml          # Bot stack only (bot, postgres-pgvector for Stage 2)
.env.example                    # Updated with bot variables
```

---

### 5. Integration Points

| Component | Calls / Depends On |
|-----------|-------------------|
| `main.py` | `config.Settings`, `llm.factory.get_provider`, `handlers.commands`, `handlers.messages` |
| `handlers.messages` | `memory.ConversationMemory`, `llm.factory.get_provider`, `utils.streaming` |
| `memory.ConversationMemory` | `llm.providers.base.LLMProvider` (for summarization) |
| `llm.factory.get_provider` | `llm.providers.ollama.OllamaProvider`, `llm.providers.openrouter.OpenRouterProvider` |
| `OllamaProvider` | `httpx.AsyncClient` → `OLLAMA_BASE_URL` (host.docker.internal:11434) |
| `OpenRouterProvider` | `httpx.AsyncClient` → `OPENROUTER_BASE_URL` + `OPENROUTER_API_KEY` |
| `docker-compose.yml` | `bot` service depends on `wordpress` (network only, for future API calls) |

---

### 6. Edge Cases & Error States

| Scenario | Handling |
|----------|----------|
| Ollama not reachable | Catch `httpx.ConnectError`, reply "LLM service unavailable, try again later" |
| OpenRouter API key invalid | Catch 401, reply "Invalid API key, check configuration" |
| Model not found on provider | Catch 404, reply "Model not available, check LLM_MODEL" |
| Stream interrupted mid-response | Send partial response, log error, preserve memory |
| Conversation memory grows unbounded | `maybe_summarize()` triggered automatically at threshold |
| User sends message while previous streaming | Queue or ignore (aiogram handles via FSM/locks) |
| `.env` missing required vars | Pydantic validation error on startup, clear message |
| Telegram API rate limit | aiogram built-in retry, log warning |
| System prompt injection attempt | User messages never treated as system role; only prepended system prompt |

---

### 7. Docker Compose Changes

**`docker-compose.yml` (add to existing):**
```yaml
services:
  bot:
    build: ./bot
    container_name: tg_omni_bot
    restart: unless-stopped
    environment:
      - BOT_TOKEN=${BOT_TOKEN}
      - LLM_PROVIDER=${LLM_PROVIDER:-ollama}
      - LLM_MODEL=${LLM_MODEL:-llama3:8b}
      - OLLAMA_BASE_URL=${OLLAMA_BASE_URL:-http://host.docker.internal:11434}
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
      - OPENROUTER_BASE_URL=${OPENROUTER_BASE_URL:-https://openrouter.ai/api/v1}
      - MEMORY_MAX_RAW_MESSAGES=${MEMORY_MAX_RAW_MESSAGES:-10}
      - MEMORY_SUMMARIZE_THRESHOLD=${MEMORY_SUMMARIZE_THRESHOLD:-20}
    volumes:
      - ./bot:/app:delegated
    depends_on:
      - wordpress
    networks:
      - tg_omni_net
```

**`docker-compose.wp.yml`** (extract existing WP stack):
```yaml
services:
  db: ...
  wordpress: ...
  nginx: ...
  phpmyadmin: ...
volumes: ...
networks: ...
```

**`docker-compose.bot.yml`** (for independent bot dev):
```yaml
services:
  bot:
    build: ./bot
    environment: ...  # same as above
    volumes:
      - ./bot:/app:delegated
    networks:
      - tg_omni_net
  # postgres-pgvector added in Stage 2
networks:
  tg_omni_net:
    external: true
```

---

### 8. .env.example Additions

```ini
# Telegram Bot
BOT_TOKEN=your_bot_token_from_botfather

# LLM Provider (ollama | openrouter)
LLM_PROVIDER=ollama
LLM_MODEL=llama3:8b

# Ollama (local)
OLLAMA_BASE_URL=http://host.docker.internal:11434

# OpenRouter
OPENROUTER_API_KEY=sk-or-v1-...
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1

# Memory
MEMORY_MAX_RAW_MESSAGES=10
MEMORY_SUMMARIZE_THRESHOLD=20
```

---

### 9. Personality / System Prompt

```python
SYSTEM_PROMPT = """You are a helpful shopping assistant for Omni Shop.
You help customers find products, answer questions about the store, and provide recommendations.
Be friendly, concise, and knowledgeable. If you don't know something, say so honestly."""
```

Injected as first message in every conversation context.

---

### 10. Acceptance Criteria (Stage 1 Complete When)

1. `make up` starts all services including `bot` container
2. Bot responds to `/start` with welcome message
3. Bot responds to `/help` with command list
4. Bot replies to any text message in private chat with streaming tokens
5. Conversation memory persists across messages (last 10 raw + summary)
6. Switching `LLM_PROVIDER=ollama` ↔ `openrouter` in `.env` works without code changes
7. Ollama on host accessible via `host.docker.internal:11434`
8. No pgvector, no product sync, no checkout code present
