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

## App Store and Google Play

**Current setup:** The app is a **Telegram Mini App** (Flutter web) deployed to **Vercel**. Users open it inside Telegram; there is no standalone store listing for that.

**If you want App Store and Google Play listings:** Use the **same Flutter codebase** and build native binaries, then submit to Apple and Google. The backend (Vercel, `/api/*`, Grammy bot) does **not** change; the mobile app will call the same APIs (e.g. config, AI) and can still open the same Mini App URL in a WebView or use the same backend from a native UI.

| Step | What to do |
|------|------------|
| **Build** | From `front/`: `flutter build ios` (Xcode required) and `flutter build appbundle` (Android). Fix any platform-specific config (e.g. `AndroidManifest.xml`, `Info.plist`, signing). |
| **Apple** | Open `build/ios/` in Xcode, configure signing and capabilities, archive, then upload to App Store Connect and submit for review. |
| **Google** | Upload the AAB from `build/app/outputs/bundle/release/` to Google Play Console, set store listing and release track. |
| **Backend** | No change. Vercel (and bot, AI) stay as-is; the app uses the same base URL / env for API and Mini App link. |

**Note:** If the app relies on `flutter_telegram_miniapp` (Telegram WebView), a standalone store build may need to open the Mini App URL in a browser or in-app WebView so Telegram login/context still work, or you expose a non-Mini-App flow that uses the same APIs. The serverless Grammy bot and AI features are reachable from any client (Mini App, iOS app, Android app) that calls your Vercel domain.

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
- Non-command text: local deterministic fallback (`Use /help for available commands.`)
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

### Webhook vs local: do you need a webhook for local?

**Recommended:** Use **polling for local** (no public URL, no ngrok) and **webhook only for Vercel deploy.**

| Where      | How              | Public HTTPS URL? |
|-----------|-------------------|-------------------|
| **Local** | Polling (`run-bot-local.js`) | No — no tunnel needed. |
| **Vercel**| Webhook (`/api/bot`)          | Yes — your Vercel domain. |

- **Local:** Delete webhook (if set), run `run-bot-local.js`. The bot pulls updates via `getUpdates`. When done, set the webhook back to Vercel.
- **Vercel:** After deploy, set the webhook once to `https://<your-vercel-domain>/api/bot`. Telegram POSTs there; no polling on the server.

**Optional:** To test the exact webhook path locally (e.g. validate → 200 ACK), use ngrok + `run-bot-webhook-local.js` (see “Local testing with webhook” below).

### Local testing (polling)

1. **Remove the webhook** (if it was set for production), so Telegram stops sending to the Vercel URL:
   ```bash
   cd front
   BOT_TOKEN="<your-token>" node scripts/delete-telegram-webhook.mjs
   ```
2. **Run the bot in polling mode:**
   ```bash
   cd front
   BOT_TOKEN="<your-token>" node scripts/run-bot-local.js
   ```
   Optional: set `AI_HEALTH_URL`, `APP_URL`, `TELEVERSE_BASE_URL` / `TELEVERSE_INTERNAL_KEY` in the environment or in `front/.env` (if you use `dotenv`).
3. Talk to the bot in Telegram; updates are received locally.
4. When done, **set the webhook again** for Vercel so production receives updates:
   ```bash
   BOT_TOKEN="<token>" TELEGRAM_WEBHOOK_URL="https://<your-vercel-domain>/api/bot" node scripts/set-telegram-webhook.mjs
   ```

### Local testing with webhook (same logic as Vercel)

To run the **same webhook path** locally (validate → 200 ACK → `bot.handleUpdate`), expose your machine and point Telegram at it:

1. **Start the local webhook server** (same handler as `api/bot.js`):
   ```bash
   cd front
   BOT_TOKEN="<token>" node scripts/run-bot-webhook-local.js
   ```
   Listens on `http://localhost:31337` (or set `PORT`).

2. **Expose it with ngrok** (or localtunnel / cloudflared):
   ```bash
   ngrok http 31337
   ```
   Use the HTTPS URL ngrok shows (e.g. `https://abc123.ngrok-free.app`).

3. **Set Telegram webhook to the tunnel + path:**
   ```bash
   TELEGRAM_WEBHOOK_URL="https://<ngrok-host>/api/bot" BOT_TOKEN="<token>" node scripts/set-telegram-webhook.mjs
   ```
   If you use `TELEGRAM_WEBHOOK_SECRET` on Vercel, set it in env here too.

4. Open the ngrok URL in the browser: `https://<ngrok-host>/api/bot` → GET should return the same health JSON as production.

5. Talk to the bot; Telegram POSTs to the tunnel → your local server runs the same code as Vercel.

6. When done, point the webhook back at Vercel (see “Webhook scripts (production)”).

### Webhook scripts (production)

```bash
node scripts/set-telegram-webhook.mjs   # after deploy: point Telegram to your Vercel URL
node scripts/delete-telegram-webhook.mjs # remove webhook (e.g. before local polling)
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

## Portability Notes

- `front/api/bot.js` is a thin webhook wrapper (validation + fast ACK + async update handling).
- `front/bot-service/*` is the portable bot module boundary (`createBot/getBot/startPolling`).
- Future migration to an `app/` structure is expected to be a path/import move, not a bot behavior rewrite.
