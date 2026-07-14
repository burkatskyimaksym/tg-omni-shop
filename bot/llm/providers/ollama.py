import json
import httpx
from bot.llm.providers.base import Message


class OllamaProvider:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip('/')
        self.client = httpx.AsyncClient(timeout=120.0)

    async def close(self):
        await self.client.aclose()

    async def chat(self, messages: list[Message], model: str, stream: bool = False, temperature: float = 0.7, max_tokens: int | None = None):
        payload = {
            "model": model,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
            "stream": stream,
            "think": False,
            "options": {"temperature": temperature}
        }
        if max_tokens:
            payload["options"]["num_predict"] = max_tokens

        try:
            if stream:
                async def token_generator():
                    async with self.client.stream("POST", f"{self.base_url}/api/chat", json=payload) as response:
                        response.raise_for_status()
                        async for line in response.aiter_lines():
                            if not line:
                                continue
                            data = json.loads(line)
                            content = data.get("message", {}).get("content", "")
                            if content:
                                yield content
                return token_generator()
            else:
                response = await self.client.post(f"{self.base_url}/api/chat", json=payload)
                response.raise_for_status()
                data = response.json()
                return data["message"]["content"]
        except httpx.ConnectError as e:
            raise ConnectionError(f"Ollama service unavailable at {self.base_url}: {e}")
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                raise ValueError(f"Model not found: {model}")
            raise

    async def embed(self, texts: list[str], model: str) -> list[list[float]]:
        results = []
        for text in texts:
            response = await self.client.post(f"{self.base_url}/api/embeddings", json={"model": model, "prompt": text})
            response.raise_for_status()
            data = response.json()
            results.append(data["embedding"])
        return results
