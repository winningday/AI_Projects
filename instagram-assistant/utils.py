"""
Utility functions for Instagram Comment Assistant.
"""

import re
from datetime import datetime
from typing import Optional
from urllib.parse import urlparse


def validate_instagram_url(url: str) -> bool:
    """Validate that a URL is a valid Instagram post URL."""
    try:
        parsed = urlparse(url)
        # Check if it's an Instagram domain
        if parsed.netloc not in ['www.instagram.com', 'instagram.com']:
            return False

        # Check if it's a post URL (contains /p/ or /reel/)
        if '/p/' in parsed.path or '/reel/' in parsed.path:
            return True

        return False
    except Exception:
        return False


def extract_post_shortcode(url: str) -> Optional[str]:
    """Extract the shortcode from an Instagram post URL."""
    try:
        # Pattern to match Instagram post/reel shortcodes
        pattern = r'(?:/p/|/reel/)([A-Za-z0-9_-]+)'
        match = re.search(pattern, url)
        if match:
            return match.group(1)
        return None
    except Exception:
        return None


def normalize_instagram_url(url: str) -> str:
    """Normalize Instagram URL to a consistent format."""
    shortcode = extract_post_shortcode(url)
    if shortcode:
        return f"https://www.instagram.com/p/{shortcode}/"
    return url


def format_timestamp(dt: datetime) -> str:
    """Format a datetime object for display."""
    if isinstance(dt, str):
        try:
            dt = datetime.fromisoformat(dt)
        except Exception:
            return dt

    now = datetime.now()
    diff = now - dt

    if diff.days > 30:
        return dt.strftime("%Y-%m-%d")
    elif diff.days > 0:
        return f"{diff.days} day{'s' if diff.days > 1 else ''} ago"
    elif diff.seconds >= 3600:
        hours = diff.seconds // 3600
        return f"{hours} hour{'s' if hours > 1 else ''} ago"
    elif diff.seconds >= 60:
        minutes = diff.seconds // 60
        return f"{minutes} minute{'s' if minutes > 1 else ''} ago"
    else:
        return "just now"


def truncate_text(text: str, max_length: int = 100, suffix: str = "...") -> str:
    """Truncate text to a maximum length."""
    if len(text) <= max_length:
        return text
    return text[:max_length - len(suffix)] + suffix


def sanitize_filename(filename: str) -> str:
    """Sanitize a string to be used as a filename."""
    # Remove invalid characters
    filename = re.sub(r'[<>:"/\\|?*]', '', filename)
    # Replace spaces with underscores
    filename = filename.replace(' ', '_')
    # Limit length
    return filename[:255]


def count_words(text: str) -> int:
    """Count words in a text string."""
    return len(text.split())


def is_question(text: str) -> bool:
    """Check if a comment is likely a question."""
    # Check for question mark
    if '?' in text:
        return True

    # Check for common question words at the beginning
    question_words = [
        'what', 'when', 'where', 'who', 'why', 'how',
        'can', 'could', 'would', 'should', 'is', 'are',
        'do', 'does', 'did'
    ]

    first_word = text.strip().lower().split()[0] if text.strip() else ""
    return first_word in question_words


def format_error_message(error: Exception) -> str:
    """Format an error message for display to user."""
    error_type = type(error).__name__
    error_msg = str(error)
    return f"{error_type}: {error_msg}"


def parse_json_response(text: str) -> Optional[dict]:
    """
    Parse JSON from text that might contain markdown code blocks.
    Handles cases where LLM wraps JSON in ```json ``` blocks.
    """
    import json

    # Try direct parsing first
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Try extracting from code block
    try:
        # Look for JSON in markdown code block
        pattern = r'```(?:json)?\s*\n?(.*?)\n?```'
        match = re.search(pattern, text, re.DOTALL)
        if match:
            json_str = match.group(1).strip()
            return json.loads(json_str)
    except Exception:
        pass

    # Try finding JSON-like structure
    try:
        # Find content between first { and last }
        start = text.find('{')
        end = text.rfind('}')
        if start != -1 and end != -1:
            json_str = text[start:end+1]
            return json.loads(json_str)
    except Exception:
        pass

    return None


def load_user_profile() -> str:
    """Load user profile from file."""
    import config

    try:
        with open(config.USER_PROFILE_PATH, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return """# Brand Voice Guidelines

## About the Creator
- Content creator focusing on engaging with audience
- Friendly and helpful tone

## Response Guidelines
- Keep responses SHORT (1-2 sentences max)
- Be friendly and encouraging
- Answer questions directly

## Default Responses
- Product questions: "Thanks for asking! Check the link in my bio for details."
- General thanks: "Thank you so much! 💕"
"""


def create_status_badge(status: str) -> str:
    """Create a colored status badge for display."""
    status_colors = {
        'pending': '🟡',
        'approved': '🟢',
        'posted': '✅',
        'skipped': '⚪',
    }
    return status_colors.get(status.lower(), '❓')
