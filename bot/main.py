import asyncio
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from aiogram import Bot, Dispatcher
from aiogram.fsm.storage.memory import MemoryStorage
from bot.config import settings
from bot.handlers import commands_router, messages_router
from bot.middleware.logging import LoggingMiddleware
from bot.llm.factory import close_provider

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

bot = Bot(token=settings.BOT_TOKEN)
storage = MemoryStorage()
dp = Dispatcher(storage=storage)

dp.workflow_data["settings"] = settings

dp.include_router(commands_router)
dp.include_router(messages_router)

dp.message.middleware(LoggingMiddleware())

polling_task: asyncio.Task | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    await on_startup()
    try:
        yield
    finally:
        await on_shutdown()


app = FastAPI(lifespan=lifespan)


async def on_startup():
    global polling_task
    logger.info("Bot starting up...")
    from aiogram.types import BotCommand
    await bot.set_my_commands([
        BotCommand(command="start", description="Start a new conversation"),
        BotCommand(command="help", description="Show help message"),
    ])
    polling_task = asyncio.create_task(dp.start_polling(bot, handle_signals=False))


async def on_shutdown():
    logger.info("Bot shutting down...")

    await dp.stop_polling()

    if polling_task is not None:
        polling_task.cancel()
        try:
            await asyncio.wait_for(polling_task, timeout=5)
        except (asyncio.CancelledError, asyncio.TimeoutError):
            pass

    try:
        await asyncio.wait_for(close_provider(), timeout=5)
    except asyncio.TimeoutError:
        logger.warning("Provider close timed out, forcing shutdown anyway.")

    try:
        await asyncio.wait_for(bot.session.close(), timeout=5)
    except asyncio.TimeoutError:
        logger.warning("Bot session close timed out, forcing shutdown anyway.")


@app.get("/health")
async def health_check():
    return {"status": "ok"}
