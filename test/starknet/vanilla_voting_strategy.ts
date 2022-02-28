import { StarknetContract} from "hardhat/types/runtime";
import { expect } from "chai";
import { starknet } from "hardhat";
import {SplitUint256} from "./shared/types";

async function setup() {
    const vanillaVotingStrategyFactory = await starknet.getContractFactory("./contracts/starknet/strategies/vanilla_voting_strategy.cairo");
    const vanillaVotingStrategy = await vanillaVotingStrategyFactory.deploy();
    return {
        vanillaVotingStrategy: vanillaVotingStrategy as StarknetContract
    }
}

describe('Snapshot X L1 Proposal Executor:', () => {
    it('The module should return the number of transactions in a proposal', async () => {
        const {vanillaVotingStrategy} = await setup();
        console.log(vanillaVotingStrategy.address);
        const {voting_power: vp} = await vanillaVotingStrategy.call("get_voting_power", {block: 1, account_160: 2,  params: []});
        expect(new SplitUint256(vp.low, vp.high)).to.deep.equal(SplitUint256.fromUint(BigInt(1)));
    }).timeout(60000);
});