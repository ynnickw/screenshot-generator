# Screenshot Generator

Automated iOS screenshot generation service for App Store optimization.

## Overview

This service accepts IPA file uploads and automatically generates screenshots for:
- iPhone 15 Pro Max
- iPad Pro 12.9-inch (6th generation)

It uses:
- **GitHub Actions** macOS runners for iOS Simulator
- **Accessibility-based exploration** to navigate apps automatically
- **Caching** to avoid regenerating screenshots for the same app version
- **Job queue** for rate limiting and priority processing

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Main App      │────▶│  Screenshot API  │────▶│  GitHub Actions │
│   (Vercel)      │     │  (Railway)       │     │  (macOS Runner) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │                         │
                               ▼                         ▼
                        ┌──────────────────────────────────────┐
                        │           Supabase                    │
                        │  - IPA Storage                       │
                        │  - Screenshot Storage                │
                        │  - Cache Table                       │
                        │  - Jobs Queue Table                  │
                        └──────────────────────────────────────┘
```

## API Endpoints

### POST /generate
Upload an IPA file and queue screenshot generation.

### GET /status/:jobId
Check the status of a screenshot generation job.

### POST /webhook/complete
Internal webhook called by GitHub Actions when job completes.

## Repository Structure

```
screenshot-generator/
├── .github/workflows/    # GitHub Actions workflows
├── scripts/              # Swift and shell scripts for screenshot generation
├── fastlane/             # Fastlane configuration
├── api/                  # API server (deployed separately)
│   ├── src/              # API source code
│   ├── package.json      # API dependencies
│   ├── tsconfig.json     # TypeScript config
│   └── Dockerfile        # Docker config for API
└── README.md
```

## Setup

### For GitHub Actions (this repository)
1. Push this repository to GitHub
2. Configure repository secrets:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_KEY`
   - `WEBHOOK_SECRET`
   - `GITHUB_TOKEN`

### For API Server (separate deployment)
1. Navigate to `api/` directory
2. Copy `.env.example` to `.env` and fill in values
3. Install dependencies: `npm install`
4. Run development server: `npm run dev`

## Deployment

### API Server (Railway/Render)
```bash
cd api
npm run build
npm start
```

### API Server (Docker)
```bash
cd api
docker build -t screenshot-generator-api .
docker run -p 3001:3001 screenshot-generator-api
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PORT` | Server port (default: 3001) |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Supabase service role key |
| `GITHUB_TOKEN` | GitHub Personal Access Token |
| `GITHUB_REPO` | GitHub repository (owner/repo) |
| `WEBHOOK_SECRET` | Secret for webhook verification |
| `API_KEYS` | Comma-separated list of valid API keys |

## Cost

- **GitHub Actions (macOS)**: $0.08/minute × ~10 min = ~$0.80/job
- **With caching**: ~$0.40 average (50% cache hit rate)

