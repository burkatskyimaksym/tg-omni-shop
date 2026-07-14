from typing import Literal
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    BOT_TOKEN: str
    LLM_PROVIDER: Literal["ollama", "openrouter"] = "ollama"
    LLM_MODEL: str = "gemma4:e2b"
    OLLAMA_BASE_URL: str = "http://127.0.0.1:11434"
    OPENROUTER_API_KEY: str | None = None
    OPENROUTER_BASE_URL: str = "https://openrouter.ai/api/v1"
    MEMORY_MAX_RAW_MESSAGES: int = 10
    MEMORY_SUMMARIZE_THRESHOLD: int = 20
    MEMORY_SUMMARY_MODEL: str | None = None

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"

settings = Settings()
