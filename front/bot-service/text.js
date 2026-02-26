function startWelcomeText(aiAvailable) {
  if (aiAvailable) {
    return [
      'Welcome to HyperlinksSpace bot.',
      'AI is online now.',
      'Send a prompt and I will help you.',
      'Use /help to see available commands.',
    ].join('\n');
  }

  return [
    'Welcome to HyperlinksSpace bot.',
    'AI is temporarily unavailable, but the bot is online.',
    'Use /help to see available commands.',
  ].join('\n');
}

const HELP_TEXT = [
  'Commands:',
  '/start - show welcome and status',
  '/help - show command list',
  '/ping - service check',
].join('\n');

const FALLBACK_TEXT = 'Use /help for available commands.';

module.exports = {
  startWelcomeText,
  HELP_TEXT,
  FALLBACK_TEXT,
};
