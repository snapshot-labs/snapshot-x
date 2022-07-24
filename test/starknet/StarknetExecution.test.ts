import { expect } from 'chai';
import { ethers } from 'hardhat';
import { StarknetContract, Account } from 'hardhat/types';
import { utils } from '@snapshot-labs/sx';
import { starknetExecutionSetup } from '../shared/setup';
import { PROPOSE_SELECTOR, VOTE_SELECTOR, AUTHENTICATE_SELECTOR } from '../shared/constants';

export interface StarknetMetaTransaction {
  to: bigint;
  functionSelector: bigint;
  calldata: bigint[];
}

export function createStarknetExecutionParams(txArray: StarknetMetaTransaction[]): bigint[] {
  if (!txArray || txArray.length == 0) {
    return [];
  }

  const dataOffset = BigInt(1 + txArray.length * 4);
  const executionParams = [dataOffset];
  let calldataIndex = 0;

  txArray.forEach((tx) => {
    const subArr: bigint[] = [
      tx.to,
      tx.functionSelector,
      BigInt(tx.calldata.length),
      BigInt(calldataIndex),
    ];
    calldataIndex += tx.calldata.length;
    executionParams.push(...subArr);
  });

  txArray.forEach((tx) => {
    executionParams.push(...tx.calldata);
  });
  return executionParams;
}

describe('Space Testing', () => {
  // Contracts
  let space: StarknetContract;
  let controller: Account;
  let vanillaAuthenticator: StarknetContract;
  let vanillaVotingStrategy: StarknetContract;
  let starknetExecutionStrategy: StarknetContract;

  // Proposal creation parameters
  let spaceAddress: bigint;
  let metadataUri: bigint[];
  let proposerEthAddress: string;
  let usedVotingStrategies1: bigint[];
  let userVotingParamsAll1: bigint[][];
  let executionStrategy: bigint;
  let executionParams: bigint[];
  let proposeCalldata: bigint[];

  // Additional parameters for voting
  let voterEthAddress: string;
  let proposalId: bigint;
  let choice: utils.choice.Choice;
  let usedVotingStrategies2: bigint[];
  let userVotingParamsAll2: bigint[][];
  let voteCalldata: bigint[];

  before(async function () {
    this.timeout(800000);

    ({ space, controller, vanillaAuthenticator, vanillaVotingStrategy, starknetExecutionStrategy } =
      await starknetExecutionSetup());

    metadataUri = utils.strings.strToShortStringArr(
      'Hello and welcome to Snapshot X. This is the future of governance.'
    );
    proposerEthAddress = ethers.Wallet.createRandom().address;
    spaceAddress = BigInt(space.address);
    usedVotingStrategies1 = [BigInt(vanillaVotingStrategy.address)];
    userVotingParamsAll1 = [[]];
    executionStrategy = BigInt(starknetExecutionStrategy.address);

    // For the execution of the proposal, we create 2 new dummy proposals
    const txCalldata1 = utils.encoding.getProposeCalldata(
      proposerEthAddress,
      metadataUri,
      BigInt(1234),
      usedVotingStrategies1,
      userVotingParamsAll1,
      []
    );
    const txCalldata2 = utils.encoding.getProposeCalldata(
      proposerEthAddress,
      metadataUri,
      BigInt(4567),
      usedVotingStrategies1,
      userVotingParamsAll1,
      []
    );
    const txCalldata3 = utils.encoding.getProposeCalldata(
      proposerEthAddress,
      metadataUri,
      BigInt(456789),
      usedVotingStrategies1,
      userVotingParamsAll1,
      []
    );
    const tx1: StarknetMetaTransaction = {
      to: BigInt(vanillaAuthenticator.address),
      functionSelector: AUTHENTICATE_SELECTOR,
      calldata: [spaceAddress, PROPOSE_SELECTOR, BigInt(txCalldata1.length), ...txCalldata1],
    };
    const tx2: StarknetMetaTransaction = {
      to: BigInt(vanillaAuthenticator.address),
      functionSelector: AUTHENTICATE_SELECTOR,
      calldata: [spaceAddress, PROPOSE_SELECTOR, BigInt(txCalldata2.length), ...txCalldata2],
    };
    const tx3: StarknetMetaTransaction = {
      to: BigInt(vanillaAuthenticator.address),
      functionSelector: AUTHENTICATE_SELECTOR,
      calldata: [spaceAddress, PROPOSE_SELECTOR, BigInt(txCalldata3.length), ...txCalldata3],
    };
    executionParams = createStarknetExecutionParams([tx1, tx2, tx3]);

    proposeCalldata = utils.encoding.getProposeCalldata(
      proposerEthAddress,
      metadataUri,
      executionStrategy,
      usedVotingStrategies1,
      userVotingParamsAll1,
      executionParams
    );

    voterEthAddress = ethers.Wallet.createRandom().address;
    proposalId = BigInt(1);
    choice = utils.choice.Choice.FOR;
    usedVotingStrategies2 = [BigInt(vanillaVotingStrategy.address)];
    userVotingParamsAll2 = [[]];
    voteCalldata = utils.encoding.getVoteCalldata(
      voterEthAddress,
      proposalId,
      choice,
      usedVotingStrategies2,
      userVotingParamsAll2
    );
  });

  it('Users should be able to create a proposal, cast a vote, and execute it', async () => {
    // -- Creates the proposal --
    {
      await vanillaAuthenticator.invoke('authenticate', {
        target: spaceAddress,
        function_selector: PROPOSE_SELECTOR,
        calldata: proposeCalldata,
      });

      const { proposal_info } = await space.call('get_proposal_info', {
        proposal_id: proposalId,
      });

      const _for = utils.splitUint256.SplitUint256.fromObj(proposal_info.power_for).toUint();
      expect(_for).to.deep.equal(BigInt(0));
      const against = utils.splitUint256.SplitUint256.fromObj(proposal_info.power_against).toUint();
      expect(against).to.deep.equal(BigInt(0));
      const abstain = utils.splitUint256.SplitUint256.fromObj(proposal_info.power_abstain).toUint();
      expect(abstain).to.deep.equal(BigInt(0));
    }
    // -- Casts a vote FOR --
    {
      await vanillaAuthenticator.invoke('authenticate', {
        target: spaceAddress,
        function_selector: VOTE_SELECTOR,
        calldata: voteCalldata,
      });

      const { proposal_info } = await space.call('get_proposal_info', {
        proposal_id: proposalId,
      });

      const _for = utils.splitUint256.SplitUint256.fromObj(proposal_info.power_for).toUint();
      expect(_for).to.deep.equal(BigInt(1));
      const against = utils.splitUint256.SplitUint256.fromObj(proposal_info.power_against).toUint();
      expect(against).to.deep.equal(BigInt(0));
      const abstain = utils.splitUint256.SplitUint256.fromObj(proposal_info.power_abstain).toUint();
      expect(abstain).to.deep.equal(BigInt(0));
    }

    // -- Executes the proposal, which should create 2 new dummy proposal in the same space
    {
      await space.invoke('finalize_proposal', {
        proposal_id: proposalId,
        execution_params: executionParams,
      });

      let { proposal_info } = await space.call('get_proposal_info', {
        proposal_id: 2,
      });
      // We can check that the proposal was successfully created by checking the execution strategy
      // as it will be zero if the new proposal was not created
      expect(proposal_info.proposal.executor).to.deep.equal(BigInt(1234));

      // Same for second dummy proposal
      ({ proposal_info } = await space.call('get_proposal_info', {
        proposal_id: 3,
      }));
      expect(proposal_info.proposal.executor).to.deep.equal(BigInt(4567));

      ({ proposal_info } = await space.call('get_proposal_info', {
        proposal_id: 4,
      }));
      expect(proposal_info.proposal.executor).to.deep.equal(BigInt(456789));
    }
  }).timeout(6000000);
});
