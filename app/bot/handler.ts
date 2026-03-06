export type ChatRole = 'system' | 'user' | 'assistant';

export type ChatMessage = {
  role: ChatRole;
  content: string;
};

export type HandleChatInput = {
  messages: ChatMessage[];
};

export type HandleChatOutput = {
  text: string;
};

function lastUserText(messages: ChatMessage[]): string {
  return [...messages].reverse().find((message) => message.role === 'user')?.content?.trim() || '';
}

function openAiApiKey(): string {
  return (
    process.env.OPENAI_API_KEY ||
    process.env.OPENAI_KEY ||
    process.env.API_KEY ||
    ''
  ).trim();
}

function toOpenAiMessages(messages: ChatMessage[]): Array<{ role: ChatRole; content: string }> {
  return messages
    .map((message) => ({
      role: message.role,
      content: typeof message.content === 'string' ? message.content.trim() : '',
    }))
    .filter((message) => message.content.length > 0);
}

async function completeWithOpenAi(messages: ChatMessage[]): Promise<string | null> {
  const apiKey = openAiApiKey();
  if (!apiKey) return null;

  const baseUrl = (process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1').replace(/\/$/, '');
  const model = (process.env.OPENAI_MODEL || 'gpt-4o-mini').trim();
  const timeoutMs = Number(process.env.OPENAI_TIMEOUT_MS || 20000);
  const payloadMessages = toOpenAiMessages(messages);
  if (payloadMessages.length === 0) return null;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: payloadMessages,
        temperature: 0.3,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw new Error(`openai_http_${res.status}${body ? `: ${body}` : ''}`);
    }

    const data = (await res.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const content = data.choices?.[0]?.message?.content?.trim();
    return content || null;
  } finally {
    clearTimeout(timeout);
  }
}

export async function handleChat(input: HandleChatInput): Promise<HandleChatOutput> {
  const text = lastUserText(input.messages);
  if (!text) {
    return { text: 'I could not read that message.' };
  }

  try {
    const aiText = await completeWithOpenAi(input.messages);
    if (aiText && aiText.length > 0) {
      return { text: aiText };
    }
  } catch (err) {
    console.error('[bot/handler] openai failed', err);
  }

  return {
    text: 'I am online, but AI is temporarily unavailable. Please try again in a moment.',
  };
}

export default handleChat;
