import asyncio
import logging
from aiogram import Router, F
from aiogram.types import Message
from aiogram.fsm.context import FSMContext
from bot.memory.conversation import ConversationMemory
from bot.llm.providers.base import Message as LLMMessage
from bot.llm.factory import get_provider
from bot.config import settings
from bot.utils.formating import strip_markdown

router = Router()
logger = logging.getLogger(__name__)

GENERIC_ERROR_MESSAGE = "Hmm, something went wrong on my end 😅 mind trying again in a bit?"


async def generate_and_send(message: Message, state: FSMContext, user_content: str, store_in_memory: bool = True):
    """Runs the LLM on arbitrary user_content (real user text, or a synthetic note) and sends the reply."""
    data = await state.get_data()
    memory: ConversationMemory = data.get("memory")
    if not memory:
        memory = ConversationMemory(
            user_id=message.from_user.id,
            max_raw=settings.MEMORY_MAX_RAW_MESSAGES,
            summarize_threshold=settings.MEMORY_SUMMARIZE_THRESHOLD
        )
        await state.set_data({"memory": memory})

    memory.add_message(LLMMessage(role="user", content=user_content))
    provider = get_provider(settings)
    from bot.handlers.commands import SYSTEM_PROMPT
    context = memory.get_context(SYSTEM_PROMPT)

    context.append(LLMMessage(
            role="user",
            content="[Reminder: reply in the same language as my message above, no matter what language you used before.]"
        ))

    full_response = ""

    async def keep_typing():
        while True:
            await message.bot.send_chat_action(message.chat.id, "typing")
            await asyncio.sleep(4)

    typing_task = asyncio.create_task(keep_typing())
    try:
        stream = await provider.chat(context, settings.LLM_MODEL, stream=True)
        async for token in stream:
            full_response += token
    finally:
        typing_task.cancel()
        try:
            await typing_task
        except asyncio.CancelledError:
            pass

    if not full_response.strip():
        logger.warning("Empty response from model for user %s", message.from_user.id)
        await message.answer(GENERIC_ERROR_MESSAGE)
        return

    await message.answer(strip_markdown(full_response))

    if store_in_memory:
        memory.add_message(LLMMessage(role="assistant", content=full_response))
        await memory.maybe_summarize(provider, settings.MEMORY_SUMMARY_MODEL or settings.LLM_MODEL)


@router.message(F.photo)
async def handle_photo(message: Message, state: FSMContext):
    caption = message.caption

    if caption:
        user_content = (
            f"[System note: the user sent an image along with this caption: \"{caption}\". "
            "You cannot view or process images yet, only text. Respond naturally to what they wrote in the caption, "
            "in their language, matching your usual tone, and briefly mention you can't see the image itself yet "
            "if it seems relevant to what they're asking.]"
        )
    else:
        user_content = (
            "[System note: the user just sent an image with no caption. You cannot view or process images yet. "
            "Let them know briefly, in their language, matching your usual tone, and suggest they describe what they need in text instead.]"
        )

    try:
        await generate_and_send(message, state, user_content=user_content, store_in_memory=bool(caption))
    except ConnectionError:
        logger.exception("LLM connection error while handling photo from %s", message.from_user.id)
        await message.answer(GENERIC_ERROR_MESSAGE)
    except Exception:
        logger.exception("Unexpected error while handling photo from %s", message.from_user.id)
        await message.answer(GENERIC_ERROR_MESSAGE)


@router.message(F.text)
async def handle_text(message: Message, state: FSMContext):
    try:
        await generate_and_send(message, state, user_content=message.text)
    except ConnectionError:
        logger.exception("LLM connection error for user %s", message.from_user.id)
        await message.answer(GENERIC_ERROR_MESSAGE)
    except ValueError:
        logger.exception("LLM value error for user %s", message.from_user.id)
        await message.answer(GENERIC_ERROR_MESSAGE)
    except Exception:
        logger.exception("Unexpected error handling message from %s", message.from_user.id)
        await message.answer(GENERIC_ERROR_MESSAGE)


@router.message()
async def handle_other(message: Message, state: FSMContext):
    try:
        await generate_and_send(
            message, state,
            user_content="[System note: the user sent a message type you can't handle yet (voice, sticker, document, "
                         "location, etc). Let them know briefly, in their language, matching your usual tone, and ask them to type instead.]",
            store_in_memory=False
        )
    except Exception:
        logger.exception("Unexpected error while handling unsupported content from %s", message.from_user.id)
        await message.answer(GENERIC_ERROR_MESSAGE)
