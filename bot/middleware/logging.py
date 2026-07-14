import logging
from aiogram import BaseMiddleware
from aiogram.types import Message
from typing import Callable, Dict, Any, Awaitable

logger = logging.getLogger(__name__)

class LoggingMiddleware(BaseMiddleware):
    async def __call__(self, handler: Callable[[Message, Dict[str, Any]], Awaitable[Any]], event: Message, data: Dict[str, Any]) -> Any:
        logger.info(f"Incoming message from {event.from_user.id}: {event.text}")
        result = await handler(event, data)
        logger.info(f"Handler completed for message from {event.from_user.id}")
        return result
