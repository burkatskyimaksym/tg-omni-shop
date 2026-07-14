from typing import Protocol, AsyncIterator
from pydantic import BaseModel

class Message(BaseModel):
    role: str
    content: str

class ChatResponse(BaseModel):
    content: str
    model: str
    usage: dict | None = None

class LLMProvider(Protocol):
    async def chat(self, messages: list[Message], model: str, stream: bool = False, temperature: float = 0.7, max_tokens: int | None = None) -> AsyncIterator[str] | str:
        ...
    
    async def embed(self, texts: list[str], model: str) -> list[list[float]]:
        ...
