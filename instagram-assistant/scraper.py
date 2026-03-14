"""
Instagram Comment Scraper
Handles both demo mode (mock data) and real Instagram scraping.
"""

import random
from typing import Dict, List, Optional
import config
from mock_data import generate_mock_comments, generate_mock_post_content
import database


def fetch_post_comments(post_url: str, use_demo: bool = None) -> Dict:
    """
    Fetch comments for a post.

    Args:
        post_url: Instagram post URL
        use_demo: If True, use mock data. If False, use real Instagram API.
                  If None, use value from config.DEMO_MODE

    Returns:
        dict with keys:
            - success: bool
            - new_comments: int (number of new comments inserted)
            - total_comments: int (total comments found)
            - mode: str ("demo" or "live")
    """
    # Use config setting if not explicitly specified
    if use_demo is None:
        use_demo = config.DEMO_MODE

    if use_demo:
        return _fetch_comments_demo(post_url)
    else:
        return _fetch_comments_instagram(post_url)


def _fetch_comments_demo(post_url: str) -> Dict:
    """Fetch comments using mock data (demo mode)."""
    # Generate 10-20 random comments
    comment_count = random.randint(10, 20)
    mock_comments = generate_mock_comments(post_url, comment_count)

    # Insert into database (will skip duplicates)
    new_comments = 0
    for comment in mock_comments:
        result = database.insert_comment(
            post_url=post_url,
            comment_id=comment['comment_id'],
            username=comment['username'],
            comment_text=comment['comment_text'],
            timestamp=comment['timestamp']
        )
        if result is not None:  # None means duplicate
            new_comments += 1

    return {
        "success": True,
        "new_comments": new_comments,
        "total_comments": comment_count,
        "mode": "demo"
    }


def _fetch_comments_instagram(post_url: str) -> Dict:
    """Fetch comments from real Instagram API."""
    # TODO: Implement in Phase 3 with instagrapi
    # This will:
    # 1. Authenticate with Instagram
    # 2. Extract post shortcode from URL
    # 3. Use instagrapi to fetch comments
    # 4. Insert into database (skipping duplicates)
    # 5. Return counts

    raise NotImplementedError(
        "Real Instagram scraping not yet implemented. "
        "Set DEMO_MODE=true in .env to use demo mode."
    )


def fetch_post_content(post_url: str, use_demo: bool = None) -> Optional[str]:
    """
    Fetch post caption/content.

    Args:
        post_url: Instagram post URL
        use_demo: If True, use mock data. If None, use config.DEMO_MODE

    Returns:
        Post caption/content as string, or None if failed
    """
    if use_demo is None:
        use_demo = config.DEMO_MODE

    if use_demo:
        return generate_mock_post_content(post_url)
    else:
        # TODO: Implement with instagrapi in Phase 3
        raise NotImplementedError("Real Instagram scraping not yet implemented.")


def scrape_comments(post_url: str) -> List[Dict]:
    """
    Scrape all comments from an Instagram post (direct API call).
    This is a lower-level function used by fetch_post_comments.

    Returns:
        List of dicts with comment data
    """
    # TODO: Implement in Phase 3
    # This will use instagrapi to get raw comment data
    pass


def get_instagram_comment_count(post_url: str) -> int:
    """
    Get total comment count directly from Instagram.

    Returns:
        Comment count from Instagram API
    """
    # TODO: Implement in Phase 3
    # This will query Instagram API for comment count
    pass
