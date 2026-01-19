"""
Mock Data Generator for Instagram Comments
Generates realistic demo data for testing without using Instagram API.
"""

import random
from datetime import datetime, timedelta

# Realistic comment templates by category
COMMENT_TEMPLATES = {
    "product_question": [
        "Where can I buy this product?",
        "What brand is that curling iron?",
        "Do you have a link for the heat protectant?",
        "Is this available on Amazon?",
        "What size barrel do you use?",
        "What's the name of that styling cream?",
        "Can you share the product link?",
        "Where did you get that brush?",
        "What brand is that hair dryer?",
        "Is this product cruelty-free?",
    ],
    "shipping": [
        "Do you ship to Canada?",
        "How long does shipping take?",
        "Do you ship internationally?",
        "What's the shipping cost to Australia?",
        "Can I order this from the UK?",
        "Is there express shipping available?",
        "Do you ship to Europe?",
        "How long until it arrives in the US?",
    ],
    "technique": [
        "Can I use this on straight hair?",
        "How long do the curls last?",
        "What temperature should I use?",
        "Do I need to prep my hair first?",
        "Can you do a tutorial for shorter hair?",
        "Will this work on fine hair?",
        "How do you get so much volume?",
        "What's the best way to hold the curling iron?",
        "Do you curl towards or away from your face?",
        "How do you make it last all day?",
        "Can I do this on wet hair?",
        "Should I use hairspray before or after?",
    ],
    "positive": [
        "This is so helpful! Thank you! 😍",
        "Love this! You're amazing! ❤️",
        "Been waiting for this tutorial!",
        "Your videos are the best!",
        "This changed my life! 🙌",
        "You just saved my hair!",
        "Best tutorial I've seen!",
        "Thank you so much for this!",
        "I tried this and it worked perfectly!",
        "Finally a tutorial that actually works!",
        "You're so talented! 💕",
        "I love your content!",
    ],
    "emoji_only": [
        "❤️❤️❤️",
        "🔥🔥",
        "😍",
        "🙌",
        "👏👏👏",
        "💕",
        "✨✨",
        "🥰",
        "👍👍",
        "💯",
    ],
    "questions_general": [
        "How often do you wash your hair?",
        "What's your hair care routine?",
        "Can you do a hair care video?",
        "What shampoo do you use?",
        "How did you grow your hair so long?",
        "Do you have any tips for damaged hair?",
    ]
}

USERNAMES = [
    "hairlover_22", "beautygirl_2024", "curlsfordays",
    "stylequeen", "hairgoals_daily", "canadian_beauty",
    "aussie_curls", "makeup_and_more", "tutorial_fan",
    "longtime_follower", "new_subscriber", "beauty_enthusiast",
    "hair_care_junkie", "styling_addict", "fashion_forward",
    "glamorous_life", "beauty_insider", "hairflip_queen",
    "curl_perfectionist", "sleek_and_chic", "volume_seeker"
]


def generate_mock_comments(post_url: str, count: int = 15) -> list:
    """
    Generate realistic mock Instagram comments.

    Args:
        post_url: The Instagram post URL
        count: Number of comments to generate

    Returns:
        List of comment dicts with keys: comment_id, username, comment_text, timestamp
    """
    comments = []

    # Extract a unique identifier from the URL for generating unique comment IDs
    url_hash = str(hash(post_url))[-8:]

    for i in range(count):
        # Random category weighted towards questions (more realistic)
        category = random.choices(
            list(COMMENT_TEMPLATES.keys()),
            weights=[30, 10, 30, 20, 5, 5],  # More questions, fewer emoji-only
            k=1
        )[0]

        # Generate timestamp (comments from last 48 hours)
        hours_ago = random.randint(1, 48)
        minutes_ago = random.randint(0, 59)
        comment_timestamp = datetime.now() - timedelta(hours=hours_ago, minutes=minutes_ago)

        comment = {
            "comment_id": f"mock_{url_hash}_{i}_{random.randint(1000, 9999)}",
            "username": random.choice(USERNAMES),
            "comment_text": random.choice(COMMENT_TEMPLATES[category]),
            "timestamp": comment_timestamp
        }
        comments.append(comment)

    return comments


def generate_mock_post_content(post_url: str) -> str:
    """
    Generate realistic mock post content/caption.

    Args:
        post_url: The Instagram post URL

    Returns:
        Mock post caption
    """
    templates = [
        "💇‍♀️ Beach waves tutorial! Using my favorite heat protectant and curling technique. Products linked in bio! ✨ #hairtutorial #beachwaves",
        "✨ How to get voluminous curls that last all day! Step-by-step guide using affordable products 💕 #haircare #curls",
        "🔥 Heat styling without damage! My secret technique + best products for healthy hair. Link in bio! #hairstyling #hairhealth",
        "💁‍♀️ Sleek and straight hair routine! Everything you need for that salon look at home ✨ #straighthair #hairroutine",
        "🌊 Summer hair care routine! Protecting your hair from sun, salt, and chlorine 🏖️ #summerhairstyling #haircare"
    ]

    return random.choice(templates)


def get_mock_stats() -> dict:
    """
    Generate mock statistics for a post.

    Returns:
        Dict with mock stats
    """
    return {
        "likes": random.randint(500, 5000),
        "comment_count": random.randint(50, 300),
        "views": random.randint(10000, 100000)
    }
