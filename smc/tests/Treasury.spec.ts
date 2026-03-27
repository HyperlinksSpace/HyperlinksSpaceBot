import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Cell, toNano } from '@ton/core';
import { Treasury } from '../wrappers/Treasury';
import '@ton/test-utils';
import { compile } from '@ton/blueprint';

describe('Treasury', () => {
    let code: Cell;

    beforeAll(async () => {
        code = await compile('Treasury');
    });

    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let treasury: SandboxContract<Treasury>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        treasury = blockchain.openContract(
            Treasury.createFromConfig(
                {
                    id: 0,
                    counter: 0,
                },
                code
            )
        );

        deployer = await blockchain.treasury('deployer');

        const deployResult = await treasury.sendDeploy(deployer.getSender(), toNano('0.05'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: treasury.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and treasury are ready to use
    });

    it('should increase counter', async () => {
        const increaseTimes = 3;
        for (let i = 0; i < increaseTimes; i++) {
            console.log(`increase ${i + 1}/${increaseTimes}`);

            const increaser = await blockchain.treasury('increaser' + i);

            const counterBefore = await treasury.getCounter();

            console.log('counter before increasing', counterBefore);

            const increaseBy = Math.floor(Math.random() * 100);

            console.log('increasing by', increaseBy);

            const increaseResult = await treasury.sendIncrease(increaser.getSender(), {
                increaseBy,
                value: toNano('0.05'),
            });

            expect(increaseResult.transactions).toHaveTransaction({
                from: increaser.address,
                to: treasury.address,
                success: true,
            });

            const counterAfter = await treasury.getCounter();

            console.log('counter after increasing', counterAfter);

            expect(counterAfter).toBe(counterBefore + increaseBy);
        }
    });

    it('should reset counter', async () => {
        const increaser = await blockchain.treasury('increaser');

        expect(await treasury.getCounter()).toBe(0);

        const increaseBy = 5;
        await treasury.sendIncrease(increaser.getSender(), {
            increaseBy,
            value: toNano('0.05'),
        });

        expect(await treasury.getCounter()).toBe(increaseBy);

        await treasury.sendReset(increaser.getSender(), {
            value: toNano('0.05'),
        });

        expect(await treasury.getCounter()).toBe(0);
    });
});
