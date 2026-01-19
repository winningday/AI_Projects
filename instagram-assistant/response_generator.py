"""
Response Generator (Phase 3)
Uses Claude API to generate contextual responses to comments.
"""

# TODO: Implement in Phase 3
# This module will:
# - Load user profile guidelines from Google Drive or local file
# - For each new comment without a generated response:
#   - Build prompt with post content, context, and brand guidelines
#   - Call Claude API to generate response
#   - Parse JSON response with comment translation and response
# - Store in responses table


PROMPT_TEMPLATE = """You are helping respond to Instagram comments on behalf of a content creator.

POST CONTEXT:
{post_content}

USER-PROVIDED DETAILS:
{post_context}

BRAND GUIDELINES:
{brand_guidelines}

NEW COMMENT:
From: @{username}
Comment: {comment_text}

Generate a response that:
1. Matches the brand voice (friendly, concise, helpful)
2. Answers the question using post context
3. Is 1-2 sentences maximum
4. Sounds natural and conversational

Also provide:
1. Chinese translation of the original comment (so user understands what was asked)
2. Chinese translation of your suggested response

Format as JSON:
{{
  "comment_cn": "...",
  "response_en": "...",
  "response_cn": "..."
}}
"""


def generate_response_for_comment(comment_id: int) -> dict:
    """
    Generate AI response for a single comment.
    Returns: {"comment_cn": str, "response_en": str, "response_cn": str}
    """
    # TODO: Implement
    pass


def generate_responses_batch(comment_ids: list) -> list:
    """
    Generate responses for multiple comments in batch.
    """
    # TODO: Implement
    pass
