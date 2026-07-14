import re


def strip_markdown(text: str) -> str:
    """Remove common Markdown syntax so raw LLM output reads as plain text."""

    # Remove fenced code blocks entirely (keep the code content)
    text = re.sub(r"```(?:\w*\n)?(.*?)```", r"\1", text, flags=re.DOTALL)

    # Remove inline code backticks
    text = re.sub(r"`([^`\n]+?)`", r"\1", text)

    # Remove bold/italic markers
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"\1", text)
    text = re.sub(r"__(.+?)__", r"\1", text)

    # Convert list markers to plain dashes or nothing
    text = re.sub(r"^[ \t]*[\*\-][ \t]+", "", text, flags=re.MULTILINE)
    text = re.sub(r"^[ \t]*\d+\.[ \t]+", "", text, flags=re.MULTILINE)

    # Remove markdown headers
    text = re.sub(r"^#{1,6}[ \t]+", "", text, flags=re.MULTILINE)

    return text.strip()
