import asyncio
from typing import AsyncIterator

async def stream_with_throttle(tokens: AsyncIterator[str], delay_ms: float = 50) -> AsyncIterator[str]:
    async for token in tokens:
        yield token
        await asyncio.sleep(delay_ms / 1000)
