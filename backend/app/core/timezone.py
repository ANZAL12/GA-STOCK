"""
Timezone utilities for Global Agencies Godown Management.
Configures Indian Standard Time (IST, UTC+05:30) across all printed reports, exports, and displays.
Uses Python's standard library timezone/timedelta to avoid external OS tzdata package requirements.
"""

from datetime import date, datetime, timedelta, timezone
from typing import Optional

# Indian Standard Time: UTC +05:30
IST = timezone(timedelta(hours=5, minutes=30), name="IST")


def now_ist() -> datetime:
    """Returns the current datetime in Indian Standard Time (IST, UTC+05:30)."""
    return datetime.now(IST)


def today_ist() -> date:
    """Returns today's date in Indian Standard Time (IST, UTC+05:30)."""
    return datetime.now(IST).date()


def to_ist(dt: Optional[datetime]) -> Optional[datetime]:
    """
    Converts a datetime object to Indian Standard Time (IST).
    If dt is timezone-naive, assumes UTC (standard for PostgreSQL timestamptz columns).
    """
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(IST)


def format_ist_time(dt: Optional[datetime], fmt: str = "%I:%M %p") -> str:
    """
    Formats a datetime into an IST time string (e.g. '07:14 PM').
    Returns '-' if dt is None.
    """
    local_dt = to_ist(dt)
    return local_dt.strftime(fmt) if local_dt else "-"


def format_ist_datetime(dt: Optional[datetime], fmt: str = "%d %b %Y, %I:%M %p") -> str:
    """
    Formats a datetime into an IST date & time string (e.g. '27 Oct 2026, 07:14 PM').
    Returns '-' if dt is None.
    """
    local_dt = to_ist(dt)
    return local_dt.strftime(fmt) if local_dt else "-"
