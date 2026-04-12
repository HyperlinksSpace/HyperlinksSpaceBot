/**
 * Telegram webhook: GET/POST forwarded to bot/webhook.
 * Mounted from api/[...path].ts (single Vercel serverless function).
 */
import webhookHandler, {
  type NodeReq,
  type NodeRes,
} from '../../bot/webhook.js';

async function handler(
  request: Request | NodeReq,
  context?: NodeRes,
): Promise<Response | void> {
  return webhookHandler(request, context);
}

export default handler;
export const GET = handler;
export const POST = handler;
