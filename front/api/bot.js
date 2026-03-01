/**
 * Vercel serverless: Telegram webhook gateway.
 * Uses Grammy for command and message handling (see bot-service/grammy-bot.js).
 * Contract: GET = health; POST = validate (secret, size, body) → 200 ACK → process via Grammy.
 */
const config = require('../bot-service/config');
import { webhookCallback } from "grammy";
import { getBot } from "../../packages/bot/dist/index.js"; // after build

function json(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(body));
}

const logger = (event) => console.log(JSON.stringify(event));

export default async function handler(req, res) {
  if (req.method === "GET") {
    return json(res, 200, { ok: true, service: "telegram-gateway" });
  }
  if (req.method !== "POST") return json(res, 405, { ok: false });

  // Minimal envs only
  const BOT_TOKEN = process.env.BOT_TOKEN;
  if (!BOT_TOKEN) return json(res, 503, { ok: false, error: "BOT_TOKEN missing" });

  const bot = getBot({ BOT_TOKEN }, { logger });

  // Let grammY handle update parsing & responses
  const cb = webhookCallback(bot, "http");
  return cb(req, res);
}
