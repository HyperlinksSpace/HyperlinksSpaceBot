# Welcome to your Expo app 👋

This is an [Expo](https://expo.dev) project created with [`create-expo-app`](https://www.npmjs.com/package/create-expo-app).

## Get started

To start the app (and the Telegram bot in polling mode), run:

```bash
npm run start
```

This runs both the Expo dev server and the bot. For Expo only (no bot), use `npm run start:expo`.

In the output, you'll find options to open the app in:

- [a development build](https://docs.expo.dev/develop/development-builds/introduction/)
- [an Android emulator](https://docs.expo.dev/workflow/android-studio-emulator/)
- [an iOS simulator](https://docs.expo.dev/workflow/ios-simulator/)
- [Expo Go](https://expo.dev/go), a limited sandbox for trying out app development with Expo

You can start developing by editing the files inside the **app** directory. This project uses [file-based routing](https://docs.expo.dev/router/introduction).

### Local env setup

1. **Copy the example file** (from the `app/` directory):
   ```bash
   cp .env.example .env
   ```
2. **Edit `.env`** and set at least:
   - **`BOT_TOKEN`** – if you run the Telegram bot locally (`npm run bot:local`).
3. **Expo app** – `npx expo start` reads env from the environment; for app-only env vars you can also put them in `.env` and use an Expo-compatible loader if you add one, or set them in the shell before running:
   ```bash
   export BOT_TOKEN=your_token
   npx expo start
   ```
4. **Bot local** – `npm run bot:local` loads `.env` from the project root (optional; you can also set `BOT_TOKEN` in the shell).

The `.env` file is gitignored; do not commit it.

## Workflows

This project is configured to use [EAS Workflows](https://docs.expo.dev/eas/workflows/get-started/) to automate some development and release processes. These commands are set up in [`package.json`](./package.json) and can be run using NPM scripts in your terminal.

### Previews

Run `npm run draft` to [publish a preview update](https://docs.expo.dev/eas/workflows/examples/publish-preview-update/) of your project, which can be viewed in Expo Go or in a development build.

### Development Builds

Run `npm run development-builds` to [create a development build](https://docs.expo.dev/eas/workflows/examples/create-development-builds/). Note - you'll need to follow the [Prerequisites](https://docs.expo.dev/eas/workflows/examples/create-development-builds/#prerequisites) to ensure you have the correct emulator setup on your machine.

### Production Deployments

Run `npm run deploy` to [deploy to production](https://docs.expo.dev/eas/workflows/examples/deploy-to-production/). Note - you'll need to follow the [Prerequisites](https://docs.expo.dev/eas/workflows/examples/deploy-to-production/#prerequisites) to ensure you're set up to submit to the Apple and Google stores.

## Hosting

Expo offers hosting for websites and API functions via EAS Hosting. See the [Getting Started](https://docs.expo.dev/eas/hosting/get-started/) guide to learn more.

### Deploy web build to Vercel

From this directory (`app/`), deploy the static web build to Vercel production:

```bash
vercel --prod
```

The project is configured so Vercel runs `npx expo export -p web` and serves the `dist/` output. Link the project first with `vercel` if needed.

### Telegram bot (Grammy)

A minimal bot that replies "Hello" is included. It is deployable on Vercel via webhook and runnable locally with getUpdates.

**Vercel (webhook)**  
- In Vercel: **Settings → Environment Variables** add `BOT_TOKEN` (or `TELEGRAM_BOT_TOKEN`). Optionally set **`SELF_URL`** to your production URL (e.g. `https://hsbexpo.vercel.app`) so the webhook is set to that domain; otherwise the build uses `VERCEL_URL` (deployment URL). Using `SELF_URL` ensures Telegram POSTs go to your production domain and show in that deployment’s logs.
- **Webhook is set on deploy:** each build runs `scripts/set-webhook.js` and registers the webhook URL with Telegram.
- Telegram sends updates to **POST** `/api/bot`; the bot replies "Hello".

**Checking logs (bot not responding)**  
1. **Vercel dashboard:** open your project → **Deployments** → click the latest deployment → **Functions** tab, or go to **Logs** (Runtime Logs). Trigger the bot (e.g. send /start), then refresh; you should see `[webhook] POST update …` and `[webhook] handled update …` if the function ran.  
2. **Verify webhook:** open **GET** `https://<your-app>.vercel.app/api/bot` in a browser. You should see `webhook_set: true` and `url: "https://…/api/bot"`. If `webhook_set` is false or missing, set `BOT_TOKEN` in Vercel and redeploy.  
3. **Telegram:** ensure you’re messaging the correct bot (same token as in Vercel) and that no other app (e.g. local polling) is using that token with a webhook elsewhere.

**Local (getUpdates, no webhook)**  
- Only `BOT_TOKEN` is required (in env or `.env`).
- Run the bot in polling mode (do not use the same token with webhook set elsewhere):
  ```bash
  node scripts/run-bot-local.js
  ```
- `npm run start` runs both Expo and the bot; or run the bot alone with `npm run bot:local`.

## Get a fresh project

When you're ready, run:

```bash
npm run reset-project
```

This command will move the starter code to the **app-example** directory and create a blank **app** directory where you can start developing.

## Learn more

To learn more about developing your project with Expo, look at the following resources:

- [Expo documentation](https://docs.expo.dev/): Learn fundamentals, or go into advanced topics with our [guides](https://docs.expo.dev/guides).
- [Learn Expo tutorial](https://docs.expo.dev/tutorial/introduction/): Follow a step-by-step tutorial where you'll create a project that runs on Android, iOS, and the web.

## Join the community

Join our community of developers creating universal apps.

- [Expo on GitHub](https://github.com/expo/expo): View our open source platform and contribute.
- [Discord community](https://chat.expo.dev): Chat with Expo users and ask questions.
