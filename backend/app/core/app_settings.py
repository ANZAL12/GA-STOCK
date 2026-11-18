import json
from pathlib import Path
from threading import Lock
from typing import Any

_SETTINGS_FILE = Path(__file__).resolve().parent.parent.parent / "app_settings.json"
_LOCK = Lock()

_DEFAULTS: dict[str, Any] = {
    "bill_edit_delete_enabled": False,
}


def get_app_settings() -> dict[str, Any]:
    with _LOCK:
        data = dict(_DEFAULTS)
        if _SETTINGS_FILE.exists():
            try:
                loaded = json.loads(_SETTINGS_FILE.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    for key in _DEFAULTS:
                        if key in loaded:
                            data[key] = bool(loaded[key])
            except Exception:
                pass
        return data


def update_app_settings(updates: dict[str, Any]) -> dict[str, Any]:
    with _LOCK:
        data = dict(_DEFAULTS)
        if _SETTINGS_FILE.exists():
            try:
                loaded = json.loads(_SETTINGS_FILE.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    for key in _DEFAULTS:
                        if key in loaded:
                            data[key] = bool(loaded[key])
            except Exception:
                pass

        for key, value in updates.items():
            if key in _DEFAULTS and value is not None:
                data[key] = bool(value)

        tmp_file = _SETTINGS_FILE.with_suffix(".json.tmp")
        tmp_file.write_text(json.dumps(data, indent=2), encoding="utf-8")
        tmp_file.replace(_SETTINGS_FILE)
        return data


def is_bill_edit_delete_enabled() -> bool:
    return bool(get_app_settings().get("bill_edit_delete_enabled", False))

