from __future__ import annotations


# Developer-editable glossary used as extra context for smart refine modes.
# Add commonly mentioned names/projects/terms that Whisper may mis-transcribe.
GLOSSARY: dict[str, list[str]] = {
    "colleague_names": [
        # "Alicia Zhang",
        # "Mateo Rivera",
    ],
    "project_names": [
        # "Whisper Clip",
        # "Phoenix Migration",
    ],
    "terms": [
        # "Kubernetes",
        # "PostgreSQL",
        # "SLO",
    ],
}


def build_glossary_context() -> str:
    sections: list[str] = []
    for section_name, entries in GLOSSARY.items():
        cleaned = [entry.strip() for entry in entries if entry and entry.strip()]
        if not cleaned:
            continue
        title = section_name.replace("_", " ").title()
        sections.append(f"{title}:")
        sections.extend(f"- {entry}" for entry in cleaned)

    if not sections:
        return ""

    return (
        "Reference glossary (use only when relevant; do not invent facts):\n"
        + "\n".join(sections)
    )
