# inventory-rag-lab

Deterministic RAG lab for structured inventory/components using real JSON files from `../components` as primary memory source.

## Goals

- Structured entity memory (not raw giant text)
- Explicit relationship graph
- Separate document memory
- Deterministic retrieval and ranking
- Deterministic context assembly

## Architecture

- `models/`: domain types and result containers
- `data/`: JSON loader, normalization, alias resolver
- `memory/`: entity/document memory facades
- `relationships/`: relationship graph and builder
- `retrieval/`: pipeline and engine orchestration
- `context/`: context assembly
- `console/`: runnable demo
- `tests/`: smoke tests

## Build

```bat
build.bat
```

## Run demo

```bat
build\InventoryRagLabConsole.exe "esse Ryzen 5600 funciona nessa B450?"
```

## Notes

- No embeddings/vector DB/langchain/agent framework.
- No async.
- No runtime Yakko core changes required.
- Ranking rules are explicit and auditable.
