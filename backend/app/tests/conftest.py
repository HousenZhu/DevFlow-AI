"""Keep regression tests independent of the developer's local deployment.

Set these before collection imports the application settings and database engine.
Individual tests supply their own fake models, HTTP servers, and vector stores.
"""

import os

os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
os.environ["LLM_API_KEY"] = ""
os.environ["GITHUB_TOKEN"] = ""
os.environ["AUTO_SYNC_ENABLED"] = "false"
os.environ["CONTEXT_MODEL_WINDOW_TOKENS"] = "0"
os.environ["CONTEXT_DYNAMIC_MODEL_WINDOW_ENABLED"] = "true"
# Vector indexing tests need the enabled code path and install a fake store.
os.environ["MILVUS_ENABLED"] = "true"
