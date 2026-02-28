/** Vercel api route: use named GET/POST so Telegram webhook POST is handled. */
const { handleRequest } = require('../bot/webhook');

module.exports = async function (request, context) {
  return handleRequest(request);
};

module.exports.GET = module.exports;
module.exports.POST = module.exports;
