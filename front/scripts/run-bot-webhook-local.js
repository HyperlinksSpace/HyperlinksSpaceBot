#!/usr/bin/env node
/**
 * Run the bot locally with the same webhook logic as Vercel.
 * Telegram must POST to a public URL, so use ngrok (or similar) to expose this server.
 *
 * 1. Start this server:
 *    cd front && BOT_TOKEN="<token>" node scripts/run-bot-webhook-local.js
 * 2. Expose it: ngrok http 31337  (or the PORT you set)
 * 3. Set webhook to the ngrok URL:
 *    TELEGRAM_WEBHOOK_URL="https://<ngrok-id>.ngrok-free.app/api/bot" BOT_TOKEN="<token>" node scripts/set-telegram-webhook.mjs
 * 4. Talk to the bot; Telegram POSTs to ngrok → this server runs the same handler as api/bot.js
 *
 * Env: BOT_TOKEN, optional TELEGRAM_WEBHOOK_SECRET, PORT (default 31337).
 */
const http = require('http');
const path = require('path');

const PORT = Number(process.env.PORT) || 31337;

// Load the same handler as Vercel api/bot.js (from scripts/ we need to run from front/)
const botHandler = require('../api/bot');

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  let body = null;
  if (req.method === 'POST' && req.headers['content-type']?.includes('application/json')) {
    const raw = await readBody(req);
    try {
      body = JSON.parse(raw.toString('utf8'));
    } catch (_) {
      body = null;
    }
  }

  const reqWithBody = {
    method: req.method,
    headers: req.headers,
    url: req.url,
    body,
  };

  const resWithHelpers = {
    setHeader(name, value) {
      res.setHeader(name, value);
    },
    status(code) {
      res.statusCode = code;
      return {
        json(obj) {
          res.setHeader('Content-Type', 'application/json');
          res.end(JSON.stringify(obj));
        },
        end(data) {
          res.end(data);
        },
      };
    },
    end(data) {
      res.end(data);
    },
  };

  try {
    await botHandler(reqWithBody, resWithHelpers);
    if (!res.writableEnded) res.end();
  } catch (err) {
    console.error(err);
    if (!res.writableEnded) {
      res.statusCode = 500;
      res.end('Internal Server Error');
    }
  }
});

server.listen(PORT, () => {
  console.log(`Webhook server: http://localhost:${PORT}/api/bot`);
  console.log(`Expose with: ngrok http ${PORT}`);
  console.log(`Then set TELEGRAM_WEBHOOK_URL to https://<ngrok-host>/api/bot and run set-telegram-webhook.mjs`);
});
