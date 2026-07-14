# Graph Report - .  (2026-07-14)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 95 nodes · 174 edges · 13 communities (8 shown, 5 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 4 edges (avg confidence: 0.5)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `31a9746e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- factory.py
- seed-products.py
- main.py
- Message
- messages.py
- OpenRouterProvider
- opencode.json
- __init__.py
- graphify.js
- seed-products.sh script
- setup-wp.sh

## God Nodes (most connected - your core abstractions)
1. `Message` - 24 edges
2. `ConversationMemory` - 12 edges
3. `LLMProvider` - 11 edges
4. `generate_and_send()` - 10 edges
5. `OllamaProvider` - 9 edges
6. `OpenRouterProvider` - 9 edges
7. `get_provider()` - 8 edges
8. `wp()` - 8 edges
9. `seed()` - 6 edges
10. `LoggingMiddleware` - 5 edges

## Surprising Connections (you probably didn't know these)
- `OllamaProvider` --uses--> `Message`  [INFERRED]
  bot/llm/providers/ollama.py → bot/llm/providers/base.py
- `OpenRouterProvider` --uses--> `Message`  [INFERRED]
  bot/llm/providers/openrouter.py → bot/llm/providers/base.py
- `ConversationMemory` --uses--> `LLMProvider`  [INFERRED]
  bot/memory/conversation.py → bot/llm/providers/base.py
- `cmd_help()` --references--> `Message`  [EXTRACTED]
  bot/handlers/commands.py → bot/llm/providers/base.py
- `generate_and_send()` --calls--> `get_provider()`  [EXTRACTED]
  bot/handlers/messages.py → bot/llm/factory.py

## Import Cycles
- None detected.

## Communities (13 total, 5 thin omitted)

### Community 0 - "factory.py"
Cohesion: 0.16
Nodes (9): BaseModel, BaseSettings, Config, Settings, get_provider(), ChatResponse, LLMProvider, OllamaProvider (+1 more)

### Community 1 - "seed-products.py"
Cohesion: 0.23
Nodes (15): create_variable_product(), create_variation(), ensure_category(), import_image(), product_exists(), Return product ID if a product with this SKU already exists, else None., Create the parent variable product and return its ID., Return variation ID if it already exists under this parent, else None. (+7 more)

### Community 2 - "main.py"
Cohesion: 0.24
Nodes (8): Any, BaseMiddleware, close_provider(), lifespan(), on_shutdown(), on_startup(), LoggingMiddleware, FastAPI

### Community 3 - "Message"
Cohesion: 0.30
Nodes (5): cmd_help(), cmd_start(), FSMContext, Message, ConversationMemory

### Community 4 - "messages.py"
Cohesion: 0.33
Nodes (8): generate_and_send(), handle_other(), handle_photo(), handle_text(), FSMContext, Runs the LLM on arbitrary user_content (real user text, or a synthetic note) and, Remove common Markdown syntax so raw LLM output reads as plain text., strip_markdown()

### Community 6 - "opencode.json"
Cohesion: 0.50
Nodes (3): plugin, $schema, .opencode/plugins/graphify.js

## Knowledge Gaps
- **5 isolated node(s):** `$schema`, `.opencode/plugins/graphify.js`, `Config`, `seed-products.sh script`, `setup-wp.sh script`
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Message` connect `Message` to `factory.py`, `main.py`, `messages.py`, `OpenRouterProvider`?**
  _High betweenness centrality (0.155) - this node is a cross-community bridge._
- **Why does `OpenRouterProvider` connect `OpenRouterProvider` to `factory.py`, `Message`?**
  _High betweenness centrality (0.047) - this node is a cross-community bridge._
- **Why does `OllamaProvider` connect `factory.py` to `Message`?**
  _High betweenness centrality (0.047) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `Message` (e.g. with `OllamaProvider` and `OpenRouterProvider`) actually correct?**
  _`Message` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `ConversationMemory` (e.g. with `LLMProvider` and `Message`) actually correct?**
  _`ConversationMemory` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `$schema`, `.opencode/plugins/graphify.js`, `Config` to the rest of the system?**
  _5 weakly-connected nodes found - possible documentation gaps or missing edges._