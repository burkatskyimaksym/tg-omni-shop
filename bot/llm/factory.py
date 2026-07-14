from bot.config import Settings
from bot.llm.providers.ollama import OllamaProvider
from bot.llm.providers.openrouter import OpenRouterProvider
from bot.llm.providers.base import LLMProvider

_provider_instance: LLMProvider | None = None


def get_provider(settings: Settings) -> LLMProvider:
    global _provider_instance
    if _provider_instance is not None:
        return _provider_instance

    if settings.LLM_PROVIDER == "ollama":
        _provider_instance = OllamaProvider(settings.OLLAMA_BASE_URL)
    elif settings.LLM_PROVIDER == "openrouter":
        if not settings.OPENROUTER_API_KEY:
            raise ValueError("OPENROUTER_API_KEY is required when using openrouter provider")
        _provider_instance = OpenRouterProvider(settings.OPENROUTER_API_KEY, settings.OPENROUTER_BASE_URL)
    else:
        raise ValueError(f"Unknown LLM provider: {settings.LLM_PROVIDER}")

    return _provider_instance


async def close_provider() -> None:
    global _provider_instance
    if _provider_instance is not None:
        await _provider_instance.close()
        _provider_instance = None
