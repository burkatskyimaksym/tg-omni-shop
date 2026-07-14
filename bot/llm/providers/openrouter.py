import json
import httpx
from bot.llm.providers.base import Message

class OpenRouterProvider:
    def __init__(self, api_key: str, base_url: str):
        self.api_key = api_key
        self.base_url = base_url.rstrip('/')
        self.client = httpx.AsyncClient(timeout=120.0)

    async def close(self):
        await self.client.aclose()

    async def chat(self, messages: list[Message], model: str, stream: bool = False, temperature: float = 0.7, max_tokens: int | None = None):
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://omni-shop.local",
            "X-Title": "Omni Shop Bot"
        }
        payload = {
            "model": model,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
            "stream": stream,
            "temperature": temperature
        }
        if max_tokens:
            payload["max_tokens"] = max_tokens

        try:
            if stream:
                async def token_generator():
                    async with self.client.stream("POST", f"{self.base_url}/chat/completions", headers=headers, json=payload) as response:
                        response.raise_for_status()
                        async for line in response.aiter_lines():
                            if line.startswith("data: "):
                                data_str = line[6:]
                                if data_str == "[DONE]":
                                    break
                                data = json.loads(data_str)
                                delta = data.get("choices", [{}])[0].get("delta", {})
                                if "content" in delta:
                                    yield delta["content"]
                return token_generator()
            else:
                response = await self.client.post(f"{self.base_url}/chat/completions", headers=headers, json=payload)
                response.raise_for_status()
                data = response.json()
                return data["choices"][0]["message"]["content"]
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 401:
                raise ValueError("Invalid OpenRouter API key")
            elif e.response.status_code == 404:
                raise ValueError(f"Model not found: {model}")
            raise

    async def embed(self, texts: list[str], model: str) -> list[list[float]]:
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        results = []
        for text in texts:
            response = await self.client.post(f"{self.base_url}/embeddings", headers=headers, json={"model": model, "input": text})
            response.raise_for_status()
            data = response.json()
            results.append(data["data"][0]["embedding"])
        return results
