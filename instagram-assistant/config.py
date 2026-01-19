"""
Configuration management for Instagram Comment Assistant.
Loads environment variables and provides application settings.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Base paths
BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"

# Ensure data directory exists
DATA_DIR.mkdir(exist_ok=True)

# API Keys
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")

# Google Drive Configuration (Optional)
GOOGLE_DRIVE_DOCUMENT_ID = os.getenv("GOOGLE_DRIVE_DOCUMENT_ID", "")
GOOGLE_DRIVE_CREDENTIALS_PATH = os.getenv("GOOGLE_DRIVE_CREDENTIALS_PATH", "credentials.json")

# Instagram Configuration
INSTAGRAM_USERNAME = os.getenv("INSTAGRAM_USERNAME", "")

# Demo Mode (set to false to use real Instagram API)
DEMO_MODE = os.getenv("DEMO_MODE", "true").lower() == "true"

# Posting Configuration
MIN_DELAY = int(os.getenv("MIN_DELAY", "8"))
MAX_DELAY = int(os.getenv("MAX_DELAY", "20"))
MAX_POSTS_PER_BATCH = int(os.getenv("MAX_POSTS_PER_BATCH", "10"))
BATCH_COOLDOWN = int(os.getenv("BATCH_COOLDOWN", "300"))  # seconds

# Database Configuration
DATABASE_PATH = DATA_DIR / os.getenv("DATABASE_PATH", "comments.db").split("/")[-1]

# Session Management
SESSION_FILE_PATH = DATA_DIR / os.getenv("SESSION_FILE_PATH", "session.json").split("/")[-1]

# User Profile
USER_PROFILE_PATH = BASE_DIR / "user_profile.md"
USER_PROFILE_CACHE_HOURS = 24


def validate_config():
    """Validate that required configuration is present."""
    errors = []

    # Only require API key if not in demo mode
    if not DEMO_MODE and not ANTHROPIC_API_KEY:
        errors.append("ANTHROPIC_API_KEY is required in .env file when DEMO_MODE=false")

    return errors


def get_config_summary():
    """Get a summary of current configuration (for debugging)."""
    return {
        "base_dir": str(BASE_DIR),
        "data_dir": str(DATA_DIR),
        "database_path": str(DATABASE_PATH),
        "session_file_path": str(SESSION_FILE_PATH),
        "user_profile_path": str(USER_PROFILE_PATH),
        "demo_mode": DEMO_MODE,
        "anthropic_api_key_set": bool(ANTHROPIC_API_KEY),
        "instagram_username": INSTAGRAM_USERNAME,
        "google_drive_enabled": bool(GOOGLE_DRIVE_DOCUMENT_ID),
        "posting_config": {
            "min_delay": MIN_DELAY,
            "max_delay": MAX_DELAY,
            "max_posts_per_batch": MAX_POSTS_PER_BATCH,
            "batch_cooldown": BATCH_COOLDOWN,
        }
    }
