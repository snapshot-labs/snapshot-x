import { expect } from 'chai';
import { starknet, ethers } from 'hardhat';
import { vanillaSetup } from '../shared/setup';
import { StarknetContract, Account } from 'hardhat/types';
import { utils } from '@snapshot-labs/sx';
import { PROPOSE_SELECTOR } from '../shared/constants';

describe('Active Proposal', () => {
  let space: StarknetContract;
  let controller: Account;
  let user: Account;
  let vanillaVotingStrategy: StarknetContract;
  let vanillaAuthenticator: StarknetContract;
  let vanillaExecutionStrategy: StarknetContract;
  let proposalId: bigint;

  before(async function () {
    this.timeout(800000);
    ({ space, controller, vanillaAuthenticator, vanillaVotingStrategy, vanillaExecutionStrategy } =
      await vanillaSetup());
    user = await starknet.deployAccount('OpenZeppelin');
    proposalId = BigInt(1);
    const proposalCallData = utils.encoding.getProposeCalldata(
      user.address,
      utils.intsSequence.IntsSequence.LEFromString(''),
      vanillaExecutionStrategy.address,
      ['0x0'],
      [[]],
      []
    );

    // Create a proposal
    await user.invoke(vanillaAuthenticator, 'authenticate', {
      target: space.address,
      function_selector: PROPOSE_SELECTOR,
      calldata: proposalCallData,
    });
  });

  it('Fails to add a voting strategy if a proposal is active', async () => {
    try {
      await controller.invoke(space, 'add_voting_strategies', {
        addresses: [vanillaVotingStrategy.address],
        params_flat: [],
      });
      throw { message: 'should not add a voting strategy' };
    } catch (error: any) {
      expect(error.message).to.contain('Some proposals are still active');
    }
  });

  it('Fails to remove a voting strategy if a proposal is active', async () => {
    try {
      await controller.invoke(space, 'remove_voting_strategies', {
        indexes: ['0x0'],
      });
      throw { message: 'should not remove a voting strategy' };
    } catch (error: any) {
      expect(error.message).to.contain('Some proposals are still active');
    }
  });

  it('Fails to add an authenticator if a proposal is active', async () => {
    try {
      await controller.invoke(space, 'add_authenticators', {
        to_add: [vanillaAuthenticator.address],
      });
      throw { message: 'should not add an authenticator' };
    } catch (error: any) {
      expect(error.message).to.contain('Some proposals are still active');
    }
  });

  it('Fails to remove an authenticator if a proposal is active', async () => {
    try {
      await controller.invoke(space, 'remove_authenticators', {
        to_remove: [vanillaAuthenticator.address],
      });
      throw { message: 'should not remove an authenticator' };
    } catch (error: any) {
      expect(error.message).to.contain('Some proposals are still active');
    }
  });
});
