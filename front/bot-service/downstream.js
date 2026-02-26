const config = require('./config');

function buildEnvelope(update) {
  const message = update?.message || update?.edited_message || null;
  const text = message?.text || '';
  const command = text.trim().startsWith('/') ? text.trim().split(/\s+/)[0].toLowerCase() : null;

  return {
    update_id: update?.update_id || null,
    chat_id: message?.chat?.id || update?.callback_query?.message?.chat?.id || null,
    user_id: message?.from?.id || update?.callback_query?.from?.id || null,
    text,
    message_id: message?.message_id || null,
    is_command: Boolean(command),
    command,
    timestamp: message?.date || Math.floor(Date.now() / 1000),
  };
}

async function forwardToTeleverse(update) {
  if (!config.televerseBaseUrl || !config.televerseInternalKey) {
    return { forwarded: false, reason: 'downstream_not_configured' };
  }

  const endpoint = `${config.televerseBaseUrl}/internal/process-update`;
  const envelope = buildEnvelope(update);

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-internal-key': config.televerseInternalKey,
    },
    body: JSON.stringify(envelope),
  });

  return {
    forwarded: response.ok,
    status: response.status,
  };
}

module.exports = {
  buildEnvelope,
  forwardToTeleverse,
};
