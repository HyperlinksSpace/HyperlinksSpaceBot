/**
 * Vercel API route: named GET/POST so Telegram webhook POST is handled.
 * Forwards to app/bot/webhook so only this file is a route (avoids 12-function limit).
 */
import webhookHandler, {
  type NodeReq,
  type NodeRes,
} from '../bot/webhook.js';

async function handler(
  request: Request | NodeReq,
  context?: NodeRes,
): Promise<Response | void> {
  return webhookHandler(request, context);
}

export default handler;
export const GET = handler;
export const POST = handler;
