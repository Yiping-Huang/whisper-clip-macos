from __future__ import annotations


def query_llm(user_query: str) -> str:
    """User-implemented LLM hook.

    You should replace this function with your own Azure OpenAI (or other LLM) call.
    Contract:
    - Input: user_query (str)
    - Output: refined plain text (str)
    """

    raise NotImplementedError(
        "Implement query_llm(user_query: str) in backend/stt_backend/user_llm_bridge.py"
    )

