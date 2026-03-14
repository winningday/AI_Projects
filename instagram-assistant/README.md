# Instagram Comment Assistant 💬

An AI-powered system to help content creators manage and respond to Instagram comments efficiently. Built for Chinese creators posting English content who need assistance crafting appropriate English responses.

## Features

### Phase 1: Post Management ✅ (Current)
- Add Instagram post URLs to database
- Manage post context and details
- Edit additional information about videos/products

### Upcoming Phases
- **Phase 2:** Comment scraping with instagrapi
- **Phase 3:** AI response generation with Claude API
- **Phase 4:** Response approval interface
- **Phase 5:** Automated posting with Playwright
- **Phase 6:** Google Drive integration for brand guidelines

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                  Streamlit Web Interface                │
├─────────────────────────────────────────────────────────┤
│  1. Add Post URL                                        │
│  2. Scrape Comments (instagrapi)                        │
│  3. Generate Responses (Claude API)                      │
│  4. Review & Approve (with Chinese translations)         │
│  5. Auto-Post to Instagram (Playwright)                  │
└─────────────────────────────────────────────────────────┘
                            │
                    ┌───────┴────────┐
                    │  SQLite DB     │
                    │  - Posts       │
                    │  - Comments    │
                    │  - Responses   │
                    └────────────────┘
```

## Prerequisites

- Python 3.10 or higher
- Anthropic Claude API key
- Instagram account credentials
- (Optional) Google Drive API credentials

## Installation

### 1. Clone or Download

```bash
cd instagram-assistant
```

### 2. Create Virtual Environment

```bash
# Create virtual environment
python -m venv venv

# Activate virtual environment
# On Windows:
venv\Scripts\activate
# On macOS/Linux:
source venv/bin/activate
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Install Playwright Browsers

```bash
playwright install chromium
```

### 5. Set Up Environment Variables

```bash
# Copy the example file
cp .env.example .env

# Edit .env with your actual credentials
```

Edit `.env` file:

```env
# Required
ANTHROPIC_API_KEY=your_anthropic_api_key_here

# Optional (for future phases)
GOOGLE_DRIVE_DOCUMENT_ID=your_document_id
INSTAGRAM_USERNAME=your_username

# Posting configuration (defaults are fine)
MIN_DELAY=8
MAX_DELAY=20
MAX_POSTS_PER_BATCH=10
BATCH_COOLDOWN=300
```

### 6. Customize Your Brand Profile

Edit `user_profile.md` with your information:

```bash
# Open in your text editor
nano user_profile.md
# or
code user_profile.md
```

Fill in:
- Your name and content focus
- Tone and style preferences
- Common product information
- Example responses
- FAQs

This profile is used by Claude to generate responses that match your brand voice.

## Getting API Keys

### Anthropic Claude API Key

1. Go to [Anthropic Console](https://console.anthropic.com/)
2. Sign up or log in
3. Navigate to API Keys section
4. Create a new API key
5. Copy and paste into your `.env` file

### Google Drive API (Optional - Phase 7)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable Google Drive API
4. Create credentials (OAuth 2.0 Client ID)
5. Download `credentials.json` to project root
6. First run will prompt for authorization

## Usage

### Running the Application

```bash
# Make sure virtual environment is activated
streamlit run app.py
```

The application will open in your browser at `http://localhost:8501`

### Workflow (Phase 1 - Current)

1. **Add a Post**
   - Navigate to "Post Management" page
   - Paste Instagram post URL
   - Click "Load Post"

2. **Add Context**
   - Enter or paste the post caption/description
   - Add additional context about:
     - Products used and mentioned
     - Video topics covered
     - Special instructions
   - Click "Save Context"

3. **Future: Fetch Comments** (Phase 2)
   - Click "Fetch New Comments" to scrape
   - New comments will be added to database

4. **Future: Review Responses** (Phase 4)
   - Go to "Response Management" page
   - Review AI-generated responses
   - See Chinese translations
   - Edit if needed
   - Approve for posting

5. **Future: Post Responses** (Phase 5)
   - Click "Post All Approved"
   - System will automatically reply to comments
   - Random delays for natural behavior

## Project Structure

```
instagram-assistant/
├── app.py                      # Main Streamlit application
├── config.py                   # Configuration management
├── database.py                 # SQLite operations
├── utils.py                    # Helper functions
├── scraper.py                  # (Phase 2) Instagram scraping
├── response_generator.py       # (Phase 3) Claude API integration
├── poster.py                   # (Phase 5) Playwright automation
├── gdrive_sync.py             # (Phase 7) Google Drive sync
├── requirements.txt           # Python dependencies
├── .env                       # Environment variables (create from .env.example)
├── .env.example              # Template for environment variables
├── user_profile.md           # Your brand guidelines
├── README.md                 # This file
└── data/
    ├── comments.db           # SQLite database (auto-created)
    └── session.json          # Instagram session (auto-created)
```

## Database Schema

### Posts Table
- `url` - Instagram post URL (primary key)
- `post_content` - Post caption/description
- `post_context` - User-added context
- `created_at` - When added to system
- `last_scraped_at` - Last comment scrape time

### Comments Table
- `id` - Auto-increment ID
- `post_url` - Foreign key to posts
- `comment_id` - Instagram comment ID (unique)
- `username` - Commenter's username
- `comment_text` - Comment content
- `timestamp` - When comment was posted
- `response_generated` - Boolean flag
- `response_approved` - Boolean flag
- `response_posted` - Boolean flag
- `posted_at` - When response was posted

### Responses Table
- `id` - Auto-increment ID
- `comment_id` - Foreign key to comments
- `suggested_response_en` - AI-generated English response
- `suggested_response_cn` - Chinese translation of response
- `comment_translation_cn` - Chinese translation of comment
- `approved_response_en` - Final approved response (editable)
- `status` - pending, approved, posted, skipped
- `created_at` - When generated

## Configuration

### Posting Delays (to avoid detection)

Edit in `.env`:

```env
MIN_DELAY=8          # Minimum seconds between posts
MAX_DELAY=20         # Maximum seconds between posts
MAX_POSTS_PER_BATCH=10  # Max posts before cooldown
BATCH_COOLDOWN=300   # Cooldown in seconds (5 minutes)
```

### Database Location

Default: `data/comments.db`

To change:
```env
DATABASE_PATH=data/comments.db
```

## Troubleshooting

### "ANTHROPIC_API_KEY is required"
- Make sure you've created a `.env` file (copy from `.env.example`)
- Add your Anthropic API key to `.env`

### Instagram Login Issues (Future Phases)
- Session cookies expire after ~90 days
- Use "Re-authenticate Instagram" in Settings
- Manual browser login window will appear

### Comment Scraping Fails (Future Phases)
- Instagram may rate-limit requests
- Wait 30-60 minutes before trying again
- Consider using private Instagram API library or Apify service

### Database Locked Error
- Close other applications accessing the database
- Restart the Streamlit app

### Import Errors
- Make sure virtual environment is activated
- Run `pip install -r requirements.txt` again
- Check Python version is 3.10+

## Development Roadmap

- [x] **Phase 1:** Database setup and basic Streamlit structure
- [x] **Phase 1:** Post management and context editing
- [ ] **Phase 2:** Comment scraping integration (instagrapi)
- [ ] **Phase 3:** Response generation with Claude API
- [ ] **Phase 4:** Response approval interface
- [ ] **Phase 5:** Posting automation with Playwright
- [ ] **Phase 6:** Session management and re-authentication
- [ ] **Phase 7:** Google Drive integration (optional)
- [ ] **Phase 8:** Error handling and rate limiting
- [ ] **Phase 9:** UI polish and improvements

## Security Notes

- Never commit `.env` file (contains API keys)
- Never commit `session.json` (contains Instagram login)
- Never commit `credentials.json` (Google Drive credentials)
- All sensitive files are in `.gitignore`

## Contributing

This is a personal project for a specific use case. However, if you'd like to adapt it for your needs:

1. Fork the repository
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## License

MIT License - feel free to use and modify for your needs.

## Support

For issues or questions:
1. Check this README first
2. Review the Settings page in the app for configuration status
3. Check the troubleshooting section above

## Credits

Built with:
- [Streamlit](https://streamlit.io/) - Web interface
- [Anthropic Claude](https://www.anthropic.com/) - AI response generation
- [instagrapi](https://github.com/adw0rd/instagrapi) - Instagram API
- [Playwright](https://playwright.dev/) - Browser automation

---

**Current Status:** Phase 1 Complete - Post Management Working ✅

Ready to proceed to Phase 2: Comment Scraping
