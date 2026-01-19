"""
Instagram Comment Scraper (Phase 2)
Uses instagrapi to scrape comments from Instagram posts.
"""

# TODO: Implement in Phase 2
# This module will:
# - Use instagrapi to authenticate with Instagram
# - Scrape comments from post URLs
# - Extract: comment_id, username, comment_text, timestamp
# - Compare against existing comments in database
# - Only insert new comments
# - Return count of new comments found


def scrape_post_content(post_url: str) -> dict:
    """
    Scrape post caption/description from Instagram.
    Returns: {"caption": str, "media_type": str}
    """
    # TODO: Implement
    pass


def scrape_comments(post_url: str) -> list:
    """
    Scrape all comments from an Instagram post.
    Returns: List of dicts with comment data
    """
    # TODO: Implement
    pass


def get_comment_count(post_url: str) -> int:
    """
    Get total comment count for a post.
    """
    # TODO: Implement
    pass
