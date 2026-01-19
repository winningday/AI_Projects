"""
Database operations for Instagram Comment Assistant.
Manages SQLite database for posts, comments, and responses.
"""

import sqlite3
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from contextlib import contextmanager
import config


@contextmanager
def get_db_connection():
    """Context manager for database connections."""
    conn = sqlite3.connect(config.DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()


def init_database():
    """Initialize database with required tables."""
    with get_db_connection() as conn:
        cursor = conn.cursor()

        # Posts table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS posts (
                url TEXT PRIMARY KEY,
                post_content TEXT,
                post_context TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_scraped_at TIMESTAMP
            )
        """)

        # Comments table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS comments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                post_url TEXT,
                comment_id TEXT UNIQUE,
                username TEXT,
                comment_text TEXT,
                timestamp TIMESTAMP,
                response_generated INTEGER DEFAULT 0,
                response_approved INTEGER DEFAULT 0,
                response_posted INTEGER DEFAULT 0,
                posted_at TIMESTAMP,
                FOREIGN KEY (post_url) REFERENCES posts(url)
            )
        """)

        # Responses table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS responses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                comment_id INTEGER,
                suggested_response_en TEXT,
                suggested_response_cn TEXT,
                comment_translation_cn TEXT,
                approved_response_en TEXT,
                status TEXT DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (comment_id) REFERENCES comments(id)
            )
        """)

        # Create indexes for better performance
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_comments_post_url ON comments(post_url)
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_comments_comment_id ON comments(comment_id)
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_responses_comment_id ON responses(comment_id)
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_responses_status ON responses(status)
        """)


# ==================== POST OPERATIONS ====================

def insert_post(url: str, post_content: str = "", post_context: str = "") -> bool:
    """Insert a new post into the database."""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO posts (url, post_content, post_context)
                VALUES (?, ?, ?)
            """, (url, post_content, post_context))
        return True
    except sqlite3.IntegrityError:
        return False  # Post already exists


def get_post(url: str) -> Optional[Dict]:
    """Get post details by URL."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM posts WHERE url = ?
        """, (url,))
        row = cursor.fetchone()
        return dict(row) if row else None


def update_post_content(url: str, post_content: str) -> bool:
    """Update post content."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE posts SET post_content = ? WHERE url = ?
        """, (post_content, url))
        return cursor.rowcount > 0


def update_post_context(url: str, post_context: str) -> bool:
    """Update post context."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE posts SET post_context = ? WHERE url = ?
        """, (post_context, url))
        return cursor.rowcount > 0


def update_last_scraped(url: str) -> bool:
    """Update the last scraped timestamp for a post."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE posts SET last_scraped_at = ? WHERE url = ?
        """, (datetime.now(), url))
        return cursor.rowcount > 0


def get_all_posts() -> List[Dict]:
    """Get all posts from the database."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM posts ORDER BY created_at DESC
        """)
        return [dict(row) for row in cursor.fetchall()]


# ==================== COMMENT OPERATIONS ====================

def insert_comment(
    post_url: str,
    comment_id: str,
    username: str,
    comment_text: str,
    timestamp: datetime
) -> Optional[int]:
    """Insert a new comment. Returns comment ID if successful, None if duplicate."""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO comments (post_url, comment_id, username, comment_text, timestamp)
                VALUES (?, ?, ?, ?, ?)
            """, (post_url, comment_id, username, comment_text, timestamp))
            return cursor.lastrowid
    except sqlite3.IntegrityError:
        return None  # Comment already exists


def get_comments_by_post(post_url: str) -> List[Dict]:
    """Get all comments for a specific post."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM comments WHERE post_url = ? ORDER BY timestamp DESC
        """, (post_url,))
        return [dict(row) for row in cursor.fetchall()]


def get_comments_without_responses() -> List[Dict]:
    """Get comments that don't have generated responses yet."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM comments WHERE response_generated = 0 ORDER BY timestamp ASC
        """)
        return [dict(row) for row in cursor.fetchall()]


def mark_comment_response_generated(comment_id: int) -> bool:
    """Mark a comment as having a response generated."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE comments SET response_generated = 1 WHERE id = ?
        """, (comment_id,))
        return cursor.rowcount > 0


def mark_comment_response_approved(comment_id: int) -> bool:
    """Mark a comment as having its response approved."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE comments SET response_approved = 1 WHERE id = ?
        """, (comment_id,))
        return cursor.rowcount > 0


def mark_comment_response_posted(comment_id: int) -> bool:
    """Mark a comment as having its response posted."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE comments SET response_posted = 1, posted_at = ? WHERE id = ?
        """, (datetime.now(), comment_id))
        return cursor.rowcount > 0


# ==================== RESPONSE OPERATIONS ====================

def insert_response(
    comment_id: int,
    suggested_response_en: str,
    suggested_response_cn: str,
    comment_translation_cn: str
) -> Optional[int]:
    """Insert a new response suggestion."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO responses (
                comment_id,
                suggested_response_en,
                suggested_response_cn,
                comment_translation_cn,
                approved_response_en,
                status
            )
            VALUES (?, ?, ?, ?, ?, 'pending')
        """, (comment_id, suggested_response_en, suggested_response_cn,
              comment_translation_cn, suggested_response_en))
        return cursor.lastrowid


def get_response_by_comment_id(comment_id: int) -> Optional[Dict]:
    """Get response for a specific comment."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM responses WHERE comment_id = ? ORDER BY created_at DESC LIMIT 1
        """, (comment_id,))
        row = cursor.fetchone()
        return dict(row) if row else None


def update_response_status(response_id: int, status: str) -> bool:
    """Update response status (pending, approved, skipped, posted)."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE responses SET status = ? WHERE id = ?
        """, (status, response_id))
        return cursor.rowcount > 0


def update_approved_response(response_id: int, approved_response_en: str) -> bool:
    """Update the approved response text."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE responses SET approved_response_en = ? WHERE id = ?
        """, (approved_response_en, response_id))
        return cursor.rowcount > 0


def get_responses_by_status(status: str) -> List[Dict]:
    """Get all responses with a specific status."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT r.*, c.username, c.comment_text, c.post_url, c.comment_id as instagram_comment_id
            FROM responses r
            JOIN comments c ON r.comment_id = c.id
            WHERE r.status = ?
            ORDER BY r.created_at ASC
        """, (status,))
        return [dict(row) for row in cursor.fetchall()]


def get_all_responses() -> List[Dict]:
    """Get all responses with their associated comment data."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT r.*, c.username, c.comment_text, c.post_url, c.comment_id as instagram_comment_id, c.timestamp
            FROM responses r
            JOIN comments c ON r.comment_id = c.id
            ORDER BY c.timestamp DESC
        """)
        return [dict(row) for row in cursor.fetchall()]


def get_response_counts() -> Dict[str, int]:
    """Get counts of responses by status."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT status, COUNT(*) as count
            FROM responses
            GROUP BY status
        """)
        counts = {row['status']: row['count'] for row in cursor.fetchall()}

        # Ensure all statuses are present
        for status in ['pending', 'approved', 'posted', 'skipped']:
            if status not in counts:
                counts[status] = 0

        return counts


# ==================== COMBINED QUERIES ====================

def get_comments_with_responses(post_url: Optional[str] = None) -> List[Dict]:
    """Get comments with their responses. Optionally filter by post URL."""
    with get_db_connection() as conn:
        cursor = conn.cursor()

        if post_url:
            cursor.execute("""
                SELECT
                    c.*,
                    r.id as response_id,
                    r.suggested_response_en,
                    r.suggested_response_cn,
                    r.comment_translation_cn,
                    r.approved_response_en,
                    r.status as response_status
                FROM comments c
                LEFT JOIN responses r ON c.id = r.comment_id
                WHERE c.post_url = ?
                ORDER BY c.timestamp DESC
            """, (post_url,))
        else:
            cursor.execute("""
                SELECT
                    c.*,
                    r.id as response_id,
                    r.suggested_response_en,
                    r.suggested_response_cn,
                    r.comment_translation_cn,
                    r.approved_response_en,
                    r.status as response_status
                FROM comments c
                LEFT JOIN responses r ON c.id = r.comment_id
                ORDER BY c.timestamp DESC
            """)

        return [dict(row) for row in cursor.fetchall()]


def get_stats() -> Dict:
    """Get overall statistics."""
    with get_db_connection() as conn:
        cursor = conn.cursor()

        # Total posts
        cursor.execute("SELECT COUNT(*) as count FROM posts")
        total_posts = cursor.fetchone()['count']

        # Total comments
        cursor.execute("SELECT COUNT(*) as count FROM comments")
        total_comments = cursor.fetchone()['count']

        # Response counts
        response_counts = get_response_counts()

        return {
            'total_posts': total_posts,
            'total_comments': total_comments,
            'pending_responses': response_counts.get('pending', 0),
            'approved_responses': response_counts.get('approved', 0),
            'posted_responses': response_counts.get('posted', 0),
            'skipped_responses': response_counts.get('skipped', 0),
        }
