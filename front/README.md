# Telegram Mini App - Flutter Frontend

This is the Flutter frontend for the XP7K Telegram Mini App.

## Setup

### Prerequisites

1. **Install Flutter** if you haven't already:

   **Option A: Automated Setup (Recommended)**
   ```bash
   bash setup_flutter.sh
   ```
   This script will guide you through downloading Flutter and configuring your PATH.

   **Option B: Manual Installation**
   - Download from: https://flutter.dev/docs/get-started/install/windows
   - Extract to a location (e.g., `C:\src\flutter`)
   - Add Flutter to your PATH:
     - **For Git Bash**: Add this to your `~/.bashrc`:
       ```bash
       export PATH="$PATH:/c/src/flutter/bin"
       ```
     - **For Windows**: Add `C:\src\flutter\bin` to your System PATH
   - Verify installation:
     ```bash
     flutter --version
     ```

2. **Install Vercel CLI** (for deployment):
   ```bash
   npm i -g vercel
   ```

### Getting Started

1. **Set up local environment variables** (for local development):
   
   Create a `.env` file in the `front` directory:
   ```bash
   cd front
   cat > .env <<'EOF'
   BOT_API_URL=http://127.0.0.1:8080
   INNER_CALLS_KEY=change-me-shared-secret
   EOF
   ```
   
   Or manually create `.env` with:
   ```
   BOT_API_URL=http://127.0.0.1:8080
   INNER_CALLS_KEY=change-me-shared-secret
   ```
   
   `BOT_API_URL` is the Bot service base URL (auth and /api/chat). Local default 8080; in production set to your bot’s public URL.
   
   > **Note**: The `.env` file is gitignored and won't be committed. For production, set the same env vars in Vercel project settings.
   > When you run the full stack via the repo **start script** (`start.sh` or `shell/start.ps1`), it sets `BOT_API_URL` and writes `front/.env` for you. If you run the frontend alone (e.g. `cd front && flutter run -d chrome`) and see "Service URL is not configured", create `front/.env` with `BOT_API_URL=...`. On production (Vercel), set `BOT_API_URL` in the project environment.

2. Get dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app in development mode:

   **Quick Dev (Git Bash / Mac / Linux):**
   ```bash
   bash dev.sh
   ```

   **Quick Dev (Windows Command Prompt / PowerShell):**
   ```cmd
   dev.bat
   ```

   **Manual Dev:**
   ```bash
   flutter run -d chrome
   ```

   **Development Options:**
   - `flutter run -d chrome` - Run in Chrome (auto-selects available port)
   - `flutter run -d edge` - Run in Edge
   - `flutter run -d chrome --web-port 8080` - Run on specific port (if available)
   - `flutter run -d chrome --devtools` - Run with DevTools

   **Hot Reload Commands (while running):**
   - Press `r` - Hot reload (apply changes instantly)
   - Press `R` - Hot restart (full restart)
   - Press `q` - Quit

   **Auto Hot Reload on Save (VS Code/Cursor):**
   - The project includes `.vscode/settings.json` with auto hot reload enabled
   - **To enable auto hot reload:**
     1. Make sure you have the **Flutter extension** installed in Cursor/VS Code
     2. **Run the app from Cursor** (F5 or use Run menu → "Flutter (Chrome)")
     3. Or if running from terminal, make sure Cursor is connected to the debug session
     4. Save your file (Ctrl+S / Cmd+S) - it should auto-reload
   - **If auto-reload doesn't work:**
     - Make sure the app is running in debug mode (not release mode)
     - Try manually pressing `r` in the terminal where Flutter is running
     - Or use the Flutter extension's "Hot Reload" button in Cursor
     - Check that `dart.flutterHotReloadOnSave` is set to `"always"` in settings

## Building for Telegram

To build the web version for Telegram Mini App:

```bash
flutter build web --release
```

The built files will be in the `build/web` directory. You can deploy these files to a web server and set the URL in your Telegram Bot configuration.

## Railway Deployment

This service is configured for Railway deployment via the monorepo setup:

- **Service config**: `railway.json` in this directory
- **Root config**: `../railway.json` (defines all services)

Railway will automatically:
1. Build the Flutter app using Nixpacks
2. Serve the built files using a Python HTTP server
3. Deploy as a separate service named "frontend"

## Deploying to Vercel (Alternative)

This project is also configured for easy deployment on Vercel. Here are the deployment options:

### Option 1: Deploy with Vercel CLI (Easiest)

**Quick Deploy (Git Bash / Mac / Linux):**
```bash
bash deploy.sh
```
This automatically regenerates `assets/favicon.ico` and `web/favicon.ico` from `assets/HyperlinksSpace.svg` before build.

Or if you've made it executable:
```bash
./deploy.sh
```

**Quick Deploy (Windows Command Prompt / PowerShell):**
```cmd
deploy.bat
```
This also auto-regenerates favicon from `assets/HyperlinksSpace.svg` before build.

**Manual Deploy:**

1. Install Vercel CLI if you haven't already:
   ```bash
   npm i -g vercel
   ```

2. Build the Flutter web app:
   ```bash
   python scripts/svg_to_favicon.py
   flutter build web --release
   ```

3. Copy vercel.json to build directory and deploy:
   ```bash
   copy vercel.json build\web\vercel.json  # Windows
   # OR
   cp vercel.json build/web/vercel.json    # Mac/Linux
   
   cd build/web
   vercel --prod
   ```

### Option 2: Deploy via Vercel Dashboard

1. Build the Flutter web app:
   ```bash
   flutter build web --release
   ```

2. Go to [Vercel Dashboard](https://vercel.com/dashboard)

3. Click "Add New..." → "Project"

4. Either:
   - **Drag and drop** the `build/web` folder, or
   - **Import Git Repository** (if you've pushed to GitHub/GitLab)

5. If importing from Git, set:
   - **Root Directory**: `build/web` (or deploy the whole repo and configure accordingly)
   - Vercel will automatically detect the `vercel.json` configuration

## Notes

- This app is designed to run in Telegram's webview
- The Telegram Web App SDK script is included in `web/index.html`
- The app automatically expands to fill the screen when loaded in Telegram
- The `vercel.json` configuration handles routing for the Flutter SPA

## Telegram Webhook Gateway (Vercel JS + Grammy)

This repo includes a Telegram webhook receiver under `front/api/bot.js`, using [Grammy](https://grammy.dev) for command and message handling (`front/bot-service/grammy-bot.js`).

- Endpoint: `POST /api/bot`
- Local commands: `/start`, `/help`, `/ping`
- Antifragile `/start`: checks `AI_HEALTH_URL` with bounded timeout and falls back safely when AI is unavailable

Supporting logic lives in `front/bot-service/*` for clean discoverability.

### Env Vars (Gateway)

- `BOT_TOKEN` - required
- `TELEGRAM_WEBHOOK_SECRET` - recommended
- `AI_HEALTH_URL` - optional
- `AI_HEALTH_TIMEOUT_MS` - default `1200`, clamped to `200..1500`
- `AI_HEALTH_CACHE_TTL_MS` - default `30000`
- `TELEGRAM_BODY_LIMIT_BYTES` - default `262144`
- `APP_URL` - optional mini app button for `/start`

### Webhook Scripts

```bash
node scripts/set-telegram-webhook.mjs
node scripts/delete-telegram-webhook.mjs
```

Expected `TELEGRAM_WEBHOOK_URL` example:
- `https://<your-vercel-domain>/api/bot`

## Bot Run Modes

### Local mode (polling, no ngrok)

Required env:
- `BOT_TOKEN`

Run:

```bash
cd front
npm ci
npm run bot:local
```

### Server mode (set webhook to Vercel)

Required env:
- `BOT_TOKEN`
- `VERCEL_URL`

Run:

```bash
cd front
npm run bot:deploy
```

`VERCEL_URL` examples:
- `your-project.vercel.app`
- `https://your-project.vercel.app`

Script computes webhook URL as:
- `https://<VERCEL_URL>/api/bot`

### Safety warning

Do not run local polling with the same token while webhook is active in production.
Use a separate dev bot token or temporarily remove webhook:

```bash
npm run bot:webhook:delete
```
