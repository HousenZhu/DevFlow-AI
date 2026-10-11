# Local DevFlow AI configuration

The local chat model is `qwen3:8b`, served by Ollama at `http://localhost:11434/v1`.
Ollama runs the model with a context length of 32,768 tokens. DevFlow AI keeps a fixed input budget of 24,000 tokens and reserves 3,000 tokens for responses.
The local API key value `ollama` is a placeholder, not a paid provider credential.

Knowledge documents use the separate `Qwen/Qwen3-Embedding-0.6B` embedding model with 1,024-dimensional vectors. These vectors are stored in Milvus. Local heuristic reranking does not require a cloud API.

PostgreSQL stores repositories, conversations, and document metadata. Milvus uses etcd and MinIO-compatible Silo object storage. The included `devflow-memory-mcp` stdio server exposes conversation memory tools without requiring a separate plugin installation.

Start the complete application with `scripts/start_project.ps1`. Open `http://localhost:3000` for the frontend and `http://localhost:8000/docs` for API documentation. Stop application processes with `scripts/stop_project.ps1`; persistent infrastructure data is retained.
