from __future__ import annotations

import os
from typing import Any

from .codex_cli_wrapper import ask_codex, check_codex_authentication, is_codex_installed, run_codex_login

LLM_PROVIDER_CODEX_CLI = "codex_cli"
LLM_PROVIDER_OPENAI_API = "openai_api"
LLM_PROVIDER_AZURE_OPENAI = "azure_openai"
SUPPORTED_PROVIDERS = {
    LLM_PROVIDER_CODEX_CLI,
    LLM_PROVIDER_OPENAI_API,
    LLM_PROVIDER_AZURE_OPENAI,
}


def _selected_provider() -> str:
    provider = (os.getenv("WHISPER_CLIP_LLM_PROVIDER", LLM_PROVIDER_CODEX_CLI) or "").strip().lower()
    return provider if provider in SUPPORTED_PROVIDERS else LLM_PROVIDER_CODEX_CLI


def _query_with_codex_cli(user_query: str) -> str:
    response = ask_codex(user_query=user_query)
    return (response or "").strip()


def _query_with_openai_api(user_query: str) -> str:
    api_key = (os.getenv("WHISPER_CLIP_OPENAI_API_KEY", "") or "").strip()
    if not api_key:
        raise RuntimeError(
            "OpenAI API key is missing. Use 'Set API Credentials' in the app menu first."
        )

    model = (os.getenv("WHISPER_CLIP_OPENAI_MODEL", "gpt-4o-mini") or "").strip() or "gpt-4o-mini"
    try:
        from openai import OpenAI
    except Exception as exc:  # pragma: no cover - import guard
        raise RuntimeError("The 'openai' package is not installed. Add it to requirements.txt.") from exc

    client = OpenAI(api_key=api_key)
    response = client.responses.create(model=model, input=user_query)
    text = (getattr(response, "output_text", "") or "").strip()
    if text:
        return text

    raise RuntimeError("OpenAI returned an empty response.")


def _query_with_azure_openai(user_query: str) -> str:
    raise NotImplementedError(
        "Azure OpenAI placeholder: implement _query_with_azure_openai in backend/stt_backend/user_llm_bridge.py."
    )


def codex_status() -> dict[str, Any]:
    installed = is_codex_installed()
    if not installed:
        return {
            "installed": False,
            "authenticated": False,
            "message": "Codex CLI not installed. Install it first: brew install codex",
        }

    authenticated, detail = check_codex_authentication()
    if authenticated:
        return {
            "installed": True,
            "authenticated": True,
            "message": "Codex is active.",
        }

    return {
        "installed": True,
        "authenticated": False,
        "message": f"Codex installed but not active yet. {detail}",
    }


def activate_codex() -> dict[str, Any]:
    current = codex_status()
    if current["authenticated"]:
        return current

    if not current["installed"]:
        return {
            "installed": False,
            "authenticated": False,
            "message": "Codex CLI not installed. Install it first: brew install codex",
        }

    login = run_codex_login()
    if not login["ok"]:
        return {
            "installed": is_codex_installed(),
            "authenticated": False,
            "message": f"Codex login failed. {login['message']}",
        }

    updated = codex_status()
    if updated["authenticated"]:
        return updated

    return {
        "installed": updated["installed"],
        "authenticated": updated["authenticated"],
        "message": "Codex login command finished, but activation is still pending. Please complete login and try again.",
    }


def query_llm(user_query: str) -> str:
    """Route smart refine requests to the selected LLM backend."""
    if not user_query.strip():
        return ""

    provider = _selected_provider()
    if provider == LLM_PROVIDER_CODEX_CLI:
        return _query_with_codex_cli(user_query)
    if provider == LLM_PROVIDER_OPENAI_API:
        return _query_with_openai_api(user_query)
    if provider == LLM_PROVIDER_AZURE_OPENAI:
        return _query_with_azure_openai(user_query)

    raise RuntimeError(f"Unsupported LLM provider: {provider}")
