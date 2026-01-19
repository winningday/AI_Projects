"""
Instagram Comment Assistant - Main Streamlit Application
Phase 1: Post Management and Context Editing
"""

import streamlit as st
from datetime import datetime
import config
import database
import utils


def init_app():
    """Initialize the application."""
    # Set page config
    st.set_page_config(
        page_title="Instagram Comment Assistant",
        page_icon="💬",
        layout="wide",
        initial_sidebar_state="expanded"
    )

    # Initialize database
    database.init_database()

    # Validate configuration
    config_errors = config.validate_config()
    if config_errors:
        st.sidebar.error("Configuration Errors:")
        for error in config_errors:
            st.sidebar.error(f"- {error}")


def show_sidebar():
    """Display sidebar with navigation and stats."""
    st.sidebar.title("📱 Instagram Comment Assistant")

    # Navigation
    st.sidebar.header("Navigation")
    page = st.sidebar.radio(
        "Go to:",
        ["📝 Post Management", "💬 Response Management", "⚙️ Settings"],
        label_visibility="collapsed"
    )

    # Statistics
    st.sidebar.header("Statistics")
    stats = database.get_stats()

    col1, col2 = st.sidebar.columns(2)
    with col1:
        st.metric("Posts", stats['total_posts'])
        st.metric("Comments", stats['total_comments'])
    with col2:
        st.metric("Pending", stats['pending_responses'])
        st.metric("Posted", stats['posted_responses'])

    st.sidebar.divider()

    return page


def page_post_management():
    """Post Management Page - Phase 1."""
    st.title("📝 Post Management")
    st.write("Add Instagram posts and manage context for response generation.")

    # Input section
    st.header("Add New Post")

    col1, col2 = st.columns([3, 1])

    with col1:
        post_url = st.text_input(
            "Instagram Post URL",
            placeholder="https://www.instagram.com/p/xxxxx/",
            help="Enter the full URL of an Instagram post or reel"
        )

    with col2:
        st.write("")  # Spacing
        st.write("")  # Spacing
        load_button = st.button("🔍 Load Post", type="primary", use_container_width=True)

    # Validate and load post
    if load_button:
        if not post_url:
            st.error("Please enter a post URL")
        elif not utils.validate_instagram_url(post_url):
            st.error("Invalid Instagram URL. Please enter a valid post or reel URL.")
        else:
            # Normalize URL
            normalized_url = utils.normalize_instagram_url(post_url)

            # Check if post exists in database
            existing_post = database.get_post(normalized_url)

            if existing_post:
                st.success(f"✅ Post found in database!")
                st.session_state['current_post_url'] = normalized_url
                st.session_state['current_post'] = existing_post
            else:
                # Insert new post
                success = database.insert_post(normalized_url, "", "")
                if success:
                    st.success("✅ New post added to database!")
                    st.info("📝 In Phase 2, we'll automatically scrape the post content here.")
                    st.session_state['current_post_url'] = normalized_url
                    st.session_state['current_post'] = database.get_post(normalized_url)
                else:
                    st.error("Failed to add post to database")

    # Display current post if selected
    if 'current_post' in st.session_state and st.session_state['current_post']:
        st.divider()
        st.header("Current Post Details")

        post = st.session_state['current_post']

        # Display post info
        st.write(f"**URL:** {post['url']}")
        st.write(f"**Added:** {utils.format_timestamp(post['created_at'])}")
        if post['last_scraped_at']:
            st.write(f"**Last Scraped:** {utils.format_timestamp(post['last_scraped_at'])}")

        # Post content (placeholder for Phase 2)
        st.subheader("Post Content")
        post_content = st.text_area(
            "Post Caption/Description",
            value=post['post_content'] or "",
            height=100,
            help="In Phase 2, this will be automatically scraped. For now, you can manually enter it.",
            placeholder="Paste the post caption here..."
        )

        # Post context (user-editable)
        st.subheader("Additional Context")
        st.write("Add details about the video, products used, or any other relevant information:")

        post_context = st.text_area(
            "Context",
            value=post['post_context'] or "",
            height=200,
            placeholder="""Example:
- Video shows hair styling tutorial using Product X
- Products mentioned: Heat protectant spray ($29), Curling iron (linked in bio)
- Main topic: Beach waves tutorial
- Target concerns: Frizzy hair, heat damage prevention
""",
            label_visibility="collapsed"
        )

        # Save button
        col1, col2, col3 = st.columns([1, 1, 2])

        with col1:
            if st.button("💾 Save Context", type="primary", use_container_width=True):
                # Update both content and context
                database.update_post_content(post['url'], post_content)
                database.update_post_context(post['url'], post_context)
                st.success("✅ Post details saved!")
                # Refresh post data
                st.session_state['current_post'] = database.get_post(post['url'])
                st.rerun()

        with col2:
            # Placeholder for Phase 2
            if st.button("🔄 Fetch New Comments", use_container_width=True, disabled=True):
                st.info("This feature will be enabled in Phase 2")

    # Display all posts
    st.divider()
    st.header("All Posts")

    all_posts = database.get_all_posts()

    if not all_posts:
        st.info("No posts yet. Add your first post above!")
    else:
        for post in all_posts:
            with st.expander(f"📄 {post['url']}", expanded=False):
                col1, col2 = st.columns([3, 1])

                with col1:
                    st.write(f"**Added:** {utils.format_timestamp(post['created_at'])}")
                    if post['last_scraped_at']:
                        st.write(f"**Last Scraped:** {utils.format_timestamp(post['last_scraped_at'])}")

                    if post['post_context']:
                        st.write("**Context:**")
                        st.write(utils.truncate_text(post['post_context'], 200))

                    # Get comment count
                    comments = database.get_comments_by_post(post['url'])
                    st.write(f"**Comments:** {len(comments)}")

                with col2:
                    if st.button("📝 Edit", key=f"edit_{post['url']}", use_container_width=True):
                        st.session_state['current_post_url'] = post['url']
                        st.session_state['current_post'] = post
                        st.rerun()


def page_response_management():
    """Response Management Page - Placeholder for Phase 2+."""
    st.title("💬 Response Management")
    st.info("🚧 This page will be implemented in Phase 4: Response approval interface")

    st.write("Features coming in future phases:")
    st.write("- View all comments with generated responses")
    st.write("- Filter by status (Pending, Approved, Posted)")
    st.write("- Edit and approve responses")
    st.write("- Bulk post approved responses")


def page_settings():
    """Settings Page."""
    st.title("⚙️ Settings")

    st.header("Configuration Status")

    config_summary = config.get_config_summary()

    # API Keys
    st.subheader("API Keys")
    col1, col2 = st.columns(2)

    with col1:
        api_status = "✅ Configured" if config_summary['anthropic_api_key_set'] else "❌ Not configured"
        st.write(f"**Anthropic API:** {api_status}")

    with col2:
        gdrive_status = "✅ Enabled" if config_summary['google_drive_enabled'] else "⚪ Optional (Not configured)"
        st.write(f"**Google Drive:** {gdrive_status}")

    st.divider()

    # Instagram Settings
    st.subheader("Instagram Settings")
    st.write(f"**Username:** {config_summary['instagram_username'] or 'Not set'}")
    st.write(f"**Session File:** {config_summary['session_file_path']}")

    st.info("🚧 Instagram authentication will be implemented in Phase 6")

    st.divider()

    # Posting Configuration
    st.subheader("Posting Configuration")
    posting_config = config_summary['posting_config']

    col1, col2 = st.columns(2)
    with col1:
        st.write(f"**Delay Range:** {posting_config['min_delay']}-{posting_config['max_delay']} seconds")
        st.write(f"**Max Posts per Batch:** {posting_config['max_posts_per_batch']}")

    with col2:
        st.write(f"**Batch Cooldown:** {posting_config['batch_cooldown']} seconds")

    st.divider()

    # Database Info
    st.subheader("Database")
    st.write(f"**Location:** {config_summary['database_path']}")

    stats = database.get_stats()
    st.write(f"**Total Records:** {stats['total_posts']} posts, {stats['total_comments']} comments")

    st.divider()

    # User Profile
    st.subheader("User Profile / Brand Guidelines")

    if config.USER_PROFILE_PATH.exists():
        st.success(f"✅ Profile found at: {config.USER_PROFILE_PATH}")

        with st.expander("View Profile Content"):
            profile_content = utils.load_user_profile()
            st.text(profile_content)
    else:
        st.warning(f"⚠️ Profile not found at: {config.USER_PROFILE_PATH}")
        st.info("A template will be created when you first run response generation.")


def main():
    """Main application entry point."""
    # Initialize app
    init_app()

    # Show sidebar and get selected page
    page = show_sidebar()

    # Route to appropriate page
    if page == "📝 Post Management":
        page_post_management()
    elif page == "💬 Response Management":
        page_response_management()
    elif page == "⚙️ Settings":
        page_settings()


if __name__ == "__main__":
    main()
