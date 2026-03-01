import { Bot, Context } from "grammy";
export type BotEnv = {
    BOT_TOKEN: string;
};
type BotDeps = {
    logger?: (event: Record<string, unknown>) => void;
};
export declare function createBot(env: BotEnv, deps?: BotDeps): Bot<Context>;
export declare function getBot(env: BotEnv, deps?: BotDeps): Bot<Context>;
export declare function startPolling(env: BotEnv, deps?: BotDeps): Promise<void>;
export {};
