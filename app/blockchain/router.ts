import { getSwapCoffeeStatus } from "./coffee.js";

export type BlockchainMode = "ping";

export type BlockchainRequest = {
  mode?: BlockchainMode;
};

export type BlockchainResponse = {
  ok: boolean;
  mode: BlockchainMode;
  provider: "swap.coffee";
  status: {
    swapCoffee: ReturnType<typeof getSwapCoffeeStatus>;
  };
  error?: string;
};

export async function handleBlockchainRequest(
  request: BlockchainRequest = {},
): Promise<BlockchainResponse> {
  const mode: BlockchainMode = request.mode ?? "ping";

  if (mode === "ping") {
    return {
      ok: true,
      mode,
      provider: "swap.coffee",
      status: {
        swapCoffee: getSwapCoffeeStatus(),
      },
    };
  }

  return {
    ok: false,
    mode,
    provider: "swap.coffee",
    status: {
      swapCoffee: getSwapCoffeeStatus(),
    },
    error: `Unsupported blockchain mode: ${mode}`,
  };
}
