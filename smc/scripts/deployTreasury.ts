import { toNano } from '@ton/core';
import { Treasury } from '../wrappers/Treasury';
import { compile, NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const treasury = provider.open(
        Treasury.createFromConfig(
            {
                id: Math.floor(Math.random() * 10000),
                counter: 0,
            },
            await compile('Treasury')
        )
    );

    await treasury.sendDeploy(provider.sender(), toNano('0.05'));

    await provider.waitForDeploy(treasury.address);

    console.log('ID', await treasury.getID());
}
