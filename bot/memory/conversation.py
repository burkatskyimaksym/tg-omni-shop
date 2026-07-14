from datetime import datetime
from bot.llm.providers.base import Message, LLMProvider

class ConversationMemory:
    def __init__(self, user_id: int, max_raw: int = 10, summarize_threshold: int = 20):
        self.user_id = user_id
        self.raw_messages: list[Message] = []
        self.summary: str | None = None
        self.updated_at = datetime.utcnow()
        self.max_raw = max_raw
        self.summarize_threshold = summarize_threshold
    
    def add_message(self, message: Message) -> None:
        self.raw_messages.append(message)
        self.updated_at = datetime.utcnow()
    
    def get_context(self, system_prompt: str) -> list[Message]:
        context = [Message(role="system", content=system_prompt)]
        if self.summary:
            context.append(Message(role="system", content=f"Previous conversation summary: {self.summary}"))
        recent = self.raw_messages[-self.max_raw:] if len(self.raw_messages) > self.max_raw else self.raw_messages
        context.extend(recent)
        return context
    
    async def maybe_summarize(self, provider: LLMProvider, model: str) -> None:
        if len(self.raw_messages) < self.summarize_threshold:
            return
        half = len(self.raw_messages) // 2
        to_summarize = self.raw_messages[:half]
        summary_prompt = "Summarize the following conversation briefly:\n\n"
        for msg in to_summarize:
            summary_prompt += f"{msg.role}: {msg.content}\n"
        
        messages = [Message(role="user", content=summary_prompt)]
        result = await provider.chat(messages, model, stream=False)
        
        if self.summary:
            self.summary = f"{self.summary}\n{result}"
        else:
            self.summary = result
        
        self.raw_messages = self.raw_messages[half:]
        self.updated_at = datetime.utcnow()
