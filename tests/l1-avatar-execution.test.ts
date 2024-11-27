import dotenv from 'dotenv';
import { expect } from 'chai';
import { HttpNetworkConfig } from 'hardhat/types';
import {
  RpcProvider as StarknetRpcProvider,
  Contract as StarknetContract,
  Account as StarknetAccount,
  shortString,
  Uint256,
  uint256,
} from 'starknet';
import { Contract as EthContract } from 'ethers';
import {
  Devnet as StarknetDevnet,
  DevnetProvider as StarknetDevnetProvider,
} from 'starknet-devnet';
import { ethers, config } from 'hardhat';

import {
  safeWithL1AvatarExecutionStrategySetup,
  increaseEthBlockchainTime,
  extractMessagePayload,
} from './utils';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { getCompiledCode } from './utils';
import { AbiCoder, keccak256 } from 'ethers';

dotenv.config();

const eth_network: string = (config.networks.ethereumLocal as HttpNetworkConfig).url;
const account_address = process.env.ADDRESS || '';
const account_pk = process.env.PK || '';

const choices = '0x3';

describe('L1 Avatar Execution', function () {
  this.timeout(1000000);

  let signer: HardhatEthersSigner;
  let safe: EthContract;
  let mockMessagingContractAddress: string;
  let l1AvatarExecutionStrategy: EthContract;

  let account: StarknetAccount;
  let starkTxAuthenticator: StarknetContract;
  let vanillaVotingStrategy: StarknetContract;
  let vanillaProposalValidationStrategy: StarknetContract;
  let space: StarknetContract;
  let ethRelayer: StarknetContract;

  let starknetDevnet: StarknetDevnet;
  let starknetDevnetProvider: StarknetDevnetProvider;
  let provider: StarknetRpcProvider;

  const _owner = 1;
  const _min_voting_duration = 200;
  const _max_voting_duration = 200;
  const _voting_delay = 100;
  let _proposal_validation_strategy: { address: string; params: any[] };
  const _proposal_validation_strategy_metadata_uri = [];
  let _voting_strategies: { address: string; params: any[] }[];
  const _voting_strategies_metadata_uri = [[]];
  let _authenticators: string[];
  const _metadata_uri = [];
  const _dao_uri = [];

  before(async function () {
    const devnetConfig = {
      args: [
        '--seed',
        '42',
        '--lite-mode',
        '--dump-on',
        'request',
        '--dump-path',
        './dump.pkl',
        '--host',
        '127.0.0.1',
        '--port',
        '5050',
      ],
    };
    console.log('Spawning devnet...');
    starknetDevnet = await StarknetDevnet.spawnVersion('v0.2.0-rc.3', devnetConfig);
    starknetDevnetProvider = new StarknetDevnetProvider();

    console.log('Loading L1 Messaging Contract');
    const messagingLoadResponse =
      await starknetDevnetProvider.postman.loadL1MessagingContract(eth_network);
    mockMessagingContractAddress = messagingLoadResponse.messaging_contract_address;
    console.log('mock messaging contract', mockMessagingContractAddress);

    provider = new StarknetRpcProvider({ nodeUrl: starknetDevnet.provider.url });

    // Account used for deployments
    account = new StarknetAccount(provider, account_address, account_pk);

    // Deploy the Stark Sig Authenticator
    console.log('Deploying Stark Tx Authenticator...');
    const { sierraCode: auth_sierra, casmCode: auth_casm } =
      await getCompiledCode('sx_StarkTxAuthenticator');
    const auth_response = await account.declareAndDeploy({
      contract: auth_sierra,
      casm: auth_casm,
    });
    starkTxAuthenticator = new StarknetContract(
      auth_sierra.abi,
      auth_response.deploy.contract_address,
      provider,
    );
    console.log('Stark Eth Authenticator: ', starkTxAuthenticator.address);

    // Deploy the Vanilla Voting strategy
    console.log('Deploying Voting Strategy...');
    const { sierraCode: voting_sierra, casmCode: voting_casm } = await getCompiledCode(
      'sx_VanillaVotingStrategy',
    );
    const voting_response = await account.declareAndDeploy({
      contract: voting_sierra,
      casm: voting_casm,
    });
    vanillaVotingStrategy = new StarknetContract(
      voting_sierra.abi,
      voting_response.deploy.contract_address,
      provider,
    );
    console.log('Vanilla Voting Strategy: ', vanillaVotingStrategy.address);

    // Deploy the Vanilla Proposal Validation strategy
    console.log('Deploying Validation Strategy...');
    const { sierraCode: proposal_sierra, casmCode: proposal_casm } = await getCompiledCode(
      'sx_VanillaProposalValidationStrategy',
    );
    const proposal_response = await account.declareAndDeploy({
      contract: proposal_sierra,
      casm: proposal_casm,
    });
    vanillaProposalValidationStrategy = new StarknetContract(
      proposal_sierra.abi,
      proposal_response.deploy.contract_address,
      provider,
    );
    console.log(
      'Vanilla Proposal Validation Strategy: ',
      vanillaProposalValidationStrategy.address,
    );

    // Deploy the EthRelayer
    console.log('Deploying Eth Relayer...');
    const { sierraCode: relayer_sierra, casmCode: relayer_casm } = await getCompiledCode(
      'sx_EthRelayerExecutionStrategy',
    );
    const relayer_response = await account.declareAndDeploy({
      contract: relayer_sierra,
      casm: relayer_casm,
    });
    ethRelayer = new StarknetContract(
      relayer_sierra.abi,
      relayer_response.deploy.contract_address,
      provider,
    );
    console.log('Eth Relayer: ', ethRelayer.address);

    // Deploy the Space
    console.log('Deploying Space...');
    const { sierraCode: space_sierra, casmCode: space_casm } = await getCompiledCode('sx_Space');
    const space_response = await account.declareAndDeploy({
      contract: space_sierra,
      casm: space_casm,
    });
    space = new StarknetContract(
      space_sierra.abi,
      space_response.deploy.contract_address,
      provider,
    );
    console.log('Space: ', space.address);

    // Connect with our account
    space.connect(account);

    _proposal_validation_strategy = {
      address: vanillaProposalValidationStrategy.address,
      params: [],
    };
    _voting_strategies = [{ address: vanillaVotingStrategy.address, params: [] }];
    _authenticators = [starkTxAuthenticator.address];

    console.log('Initializing space...');
    const initializeRes = await space.initialize(
      _owner,
      _min_voting_duration,
      _max_voting_duration,
      _voting_delay,
      _proposal_validation_strategy,
      _proposal_validation_strategy_metadata_uri,
      _voting_strategies,
      _voting_strategies_metadata_uri,
      _authenticators,
      _metadata_uri,
      _dao_uri,
    );
    await provider.waitForTransaction(initializeRes.transaction_hash);
    console.log('Space initialized');

    // Dumping the Starknet state so it can be loaded at the same point for each test
    console.log('Dumping state...');
    await starknetDevnet.provider.dump('dump.pkl');
    console.log('State dumped');

    // Ethereum setup
    const signers = await ethers.getSigners();
    signer = signers[0];
    const quorum = 1;

    ({ l1AvatarExecutionStrategy, safe } = await safeWithL1AvatarExecutionStrategySetup(
      signer,
      mockMessagingContractAddress,
      space.address,
      ethRelayer.address,
      quorum,
    ));
    console.log('type: ', await l1AvatarExecutionStrategy.getStrategyType());
  });

  it('should execute a proposal via the Avatar Execution Strategy connected to a Safe', async function () {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    starkTxAuthenticator.connect(account);

    const proposalTx = {
      to: signer.address,
      value: 0,
      data: '0x11',
      operation: 0,
    };

    const abiCoder = new AbiCoder();
    const executionHash = keccak256(
      abiCoder.encode(
        ['tuple(address to, uint256 value, bytes data, uint8 operation)[]'],
        [[proposalTx]],
      ),
    );
    // Represent the execution hash as a Cairo Uint256
    const executionHashUint256: Uint256 = uint256.bnToUint256(executionHash);

    const executionPayload = [
      await l1AvatarExecutionStrategy.getAddress(),
      executionHashUint256.low,
      executionHashUint256.high,
    ];
    const proposalId = { low: '0x1', high: '0x0' };

    console.log('Authenticating propose...');
    const proposeRes = await starkTxAuthenticator.authenticate_propose(
      space.address,
      account.address,
      choices,
      [],
      { address: ethRelayer.address, params: executionPayload },
      [],
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Propose authenticated');

    await starknetDevnet.provider.increaseTime(_voting_delay);
    await increaseEthBlockchainTime(eth_network, _voting_delay);

    console.log('Authenticating vote...');
    const choice = '0x1';
    const voteRes = await starkTxAuthenticator.authenticate_vote(
      space.address,
      account.address,
      proposalId,
      choice,
      [{ index: '0x0', params: [] }],
      [],
    );
    await provider.waitForTransaction(voteRes.transaction_hash);
    console.log('Vote authenticated');

    // Advance time so that the maxVotingTimestamp is exceeded
    await starknetDevnet.provider.increaseTime(_max_voting_duration);
    await increaseEthBlockchainTime(eth_network, _max_voting_duration);

    // Execute
    console.log('Executing proposal...');
    const executeRes = await space.execute(proposalId, executionPayload);
    await provider.waitForTransaction(executeRes.transaction_hash);
    console.log('Proposal executed');

    // Propagating message to L1
    console.log('Flushing');
    const flushL2Response = await starknetDevnetProvider.postman.flush();
    const message_payload = flushL2Response.messages_to_l1[0].payload;

    // Proposal data can either be extracted from the message sent to L1 (as done here) or pulled from the contract directly
    const [proposalId_, proposal, votes] = extractMessagePayload(message_payload);

    console.log('Executing on L1');
    await expect(
      l1AvatarExecutionStrategy.execute(
        space.address,
        proposalId_,
        proposal,
        votes,
        executionHash,
        [proposalTx],
      ),
    )
      .to.emit(l1AvatarExecutionStrategy, 'ProposalExecuted')
      .withArgs(space.address.toString(), proposalId_);
    console.log('Executed on L1!');
  });

  it('should execute a proposal with multiple txs via the Avatar Execution Strategy connected to a Safe', async function () {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    await starkTxAuthenticator.connect(account);

    const proposalTx = {
      to: signer.address,
      value: 0,
      data: '0x11',
      operation: 0,
    };

    const proposalTx2 = {
      to: signer.address,
      value: 0,
      data: '0x22',
      operation: 0,
      salt: 1,
    };

    const abiCoder = new AbiCoder();
    const executionHash = keccak256(
      abiCoder.encode(
        ['tuple(address to, uint256 value, bytes data, uint8 operation)[]'],
        [[proposalTx, proposalTx2]],
      ),
    );
    // Represent the execution hash as a Cairo Uint256
    const executionHashUint256: Uint256 = uint256.bnToUint256(executionHash);

    const executionPayload = [
      await l1AvatarExecutionStrategy.getAddress(),
      executionHashUint256.low,
      executionHashUint256.high,
    ];

    const proposalId = { low: '0x1', high: '0x0' };

    // Propose
    console.log('Authenticating proposal...');
    const proposeRes = await starkTxAuthenticator.authenticate_propose(
      space.address,
      account.address,
      choices,
      [],
      { address: ethRelayer.address, params: executionPayload },
      [],
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');

    await starknetDevnet.provider.increaseTime(_voting_delay);
    await increaseEthBlockchainTime(eth_network, _voting_delay);

    console.log('Authenticating vote...');
    const choice = '0x1';
    const voteRes = await starkTxAuthenticator.authenticate_vote(
      space.address,
      account.address,
      proposalId,
      choice,
      [{ index: '0x0', params: [] }],
      [],
    );
    await provider.waitForTransaction(voteRes.transaction_hash);
    console.log('Vote authenticated!');

    // Advance time so that the maxVotingTimestamp is exceeded
    await starknetDevnet.provider.increaseTime(_max_voting_duration);
    await increaseEthBlockchainTime(eth_network, _max_voting_duration);

    console.log('Executing proposal...');
    const execRes = await space.execute(proposalId, executionPayload);
    await provider.waitForTransaction(execRes.transaction_hash);
    console.log('Proposal executed');

    // Propagating message to L1
    const flushL2Response = await starknetDevnetProvider.postman.flush();
    const message_payload = flushL2Response.messages_to_l1[0].payload;

    // Proposal data can either be extracted from the message sent to L1 (as done here) or pulled from the contract directly
    const [proposalId_, proposal, votes] = extractMessagePayload(message_payload);

    await l1AvatarExecutionStrategy.execute(
      space.address,
      proposalId_,
      proposal,
      votes,
      executionHash,
      [proposalTx, proposalTx2],
    );
  });

  it('should revert if the space is not whitelisted in the Avatar execution strategy', async function () {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    await starkTxAuthenticator.connect(account);

    // Disabling the space in the execution strategy
    await l1AvatarExecutionStrategy.disableSpace(space.address);

    const proposalTx = {
      to: signer.address,
      value: 0,
      data: '0x11',
      operation: 0,
    };

    const abiCoder = new AbiCoder();
    const executionHash = keccak256(
      abiCoder.encode(
        ['tuple(address to, uint256 value, bytes data, uint8 operation)[]'],
        [[proposalTx]],
      ),
    );
    // Represent the execution hash as a Cairo Uint256
    const executionHashUint256: Uint256 = uint256.bnToUint256(executionHash);

    const executionPayload = [
      await l1AvatarExecutionStrategy.getAddress(),
      executionHashUint256.low,
      executionHashUint256.high,
    ];

    const proposalId = { low: '0x1', high: '0x0' };

    console.log('Authenticating proposal...');
    const proposeRes = await starkTxAuthenticator.authenticate_propose(
      space.address,
      account.address,
      choices,
      [],
      { address: ethRelayer.address, params: executionPayload },
      [],
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');

    // Advance time to voting has started.
    await starknetDevnet.provider.increaseTime(_voting_delay);
    await increaseEthBlockchainTime(eth_network, _voting_delay);

    console.log('Authenticating vote...');
    const choice = '0x1';
    const voteRes = await starkTxAuthenticator.authenticate_vote(
      space.address,
      account.address,
      proposalId,
      choice,
      [{ index: '0x0', params: [] }],
      [],
    );
    await provider.waitForTransaction(voteRes.transaction_hash);
    console.log('Vote authenticated');

    // Advance time so that the maxVotingTimestamp is exceeded
    await starknetDevnet.provider.increaseTime(_max_voting_duration);
    await increaseEthBlockchainTime(eth_network, _max_voting_duration);

    console.log('Executing proposal...');
    const executRes = await space.execute(proposalId, executionPayload);
    await provider.waitForTransaction(executRes.transaction_hash);
    console.log('Proposal executed');

    // Propagating message to L1
    const flushL2Response = await starknetDevnetProvider.postman.flush();
    const message_payload = flushL2Response.messages_to_l1[0].payload;

    // Proposal data can either be extracted from the message sent to L1 (as done here) or pulled from the contract directly
    const [proposalId_, proposal, votes] = extractMessagePayload(message_payload);

    await expect(
      l1AvatarExecutionStrategy.execute(
        space.address,
        proposalId_,
        proposal,
        votes,
        executionHash,
        [proposalTx],
      ),
    ).to.be.reverted;

    // Re-enable the space in the execution strategy for other tests
    await l1AvatarExecutionStrategy.enableSpace(space.address);
  });

  it('should revert execution if an invalid payload is sent to L1', async function () {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    starkTxAuthenticator.connect(account);

    const proposalTx = {
      to: signer.address,
      value: 0,
      data: '0x22',
      operation: 0,
    };

    const abiCoder = new AbiCoder();
    const executionHash = keccak256(
      abiCoder.encode(
        ['tuple(address to, uint256 value, bytes data, uint8 operation)[]'],
        [[proposalTx]],
      ),
    );
    // Represent the execution hash as a Cairo Uint256
    const executionHashUint256: Uint256 = uint256.bnToUint256(executionHash);

    const executionPayload = [
      await l1AvatarExecutionStrategy.getAddress(),
      executionHashUint256.low,
      executionHashUint256.high,
    ];

    const proposalId = { low: '0x1', high: '0x0' };

    console.log('Authenticating proposal...');
    const proposeRes = await starkTxAuthenticator.authenticate_propose(
      space.address,
      account.address,
      choices,
      [],
      { address: ethRelayer.address, params: executionPayload },
      [],
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');

    // Advance time so that voting has started
    await starknetDevnet.provider.increaseTime(_voting_delay);
    await increaseEthBlockchainTime(eth_network, _voting_delay);

    console.log('Authenticating vote...');
    const choice = '0x1';
    const voteRes = await starkTxAuthenticator.authenticate_vote(
      space.address,
      account.address,
      proposalId,
      choice,
      [{ index: '0x0', params: [] }],
      [],
    );
    await provider.waitForTransaction(voteRes.transaction_hash);
    console.log('Vote authenticated');

    // Advance time so that the maxVotingTimestamp is exceeded
    await starknetDevnet.provider.increaseTime(_max_voting_duration);
    await increaseEthBlockchainTime(eth_network, _max_voting_duration);

    console.log('Executing proposal...');
    const executeRes = await space.execute(proposalId, executionPayload);
    await provider.waitForTransaction(executeRes.transaction_hash);
    console.log('Proposal executed');

    // Propagating message to L1
    const flushL2Response = await starknetDevnetProvider.postman.flush();
    const message_payload = flushL2Response.messages_to_l1[0].payload;
    // Proposal data can either be extracted from the message sent to L1 (as done here) or pulled from the contract directly
    const [proposalId_, proposal, votes] = extractMessagePayload(message_payload);

    // Manually set an incorrect votesFor value
    votes[1] = 10;

    await expect(
      l1AvatarExecutionStrategy.execute(
        space.address,
        proposalId_,
        proposal,
        votes,
        executionHash,
        [proposalTx],
      ),
    ).to.be.revertedWith('INVALID_MESSAGE_TO_CONSUME');
  });

  it('should revert execution if an invalid proposal tx is sent to the execution strategy', async function () {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    await starkTxAuthenticator.connect(account);

    const proposalTx = {
      to: signer.address,
      value: 0,
      data: '0x22',
      operation: 0,
    };

    const abiCoder = new AbiCoder();

    const executionHash = keccak256(
      abiCoder.encode(
        ['tuple(address to, uint256 value, bytes data, uint8 operation)[]'],
        [[proposalTx]],
      ),
    );
    // Represent the execution hash as a Cairo Uint256
    const executionHashUint256: Uint256 = uint256.bnToUint256(executionHash);

    const executionPayload = [
      await l1AvatarExecutionStrategy.getAddress(),
      executionHashUint256.low,
      executionHashUint256.high,
    ];

    console.log('Authenticating proposal...');
    const proposeRes = await starkTxAuthenticator.authenticate_propose(
      space.address,
      account.address,
      choices,
      [],
      { address: ethRelayer.address, params: executionPayload },
      [],
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');

    // Advance time so that voting has started
    await starknetDevnet.provider.increaseTime(_voting_delay);
    await increaseEthBlockchainTime(eth_network, _voting_delay);

    console.log('Authenticating vote...');
    const choice = '0x1';
    const voteRes = await starkTxAuthenticator.authenticate_vote(
      space.address,
      account.address,
      { low: '0x1', high: '0x0' },
      choice,
      [{ index: '0x0', params: [] }],
      [],
    );
    await provider.waitForTransaction(voteRes.transaction_hash);
    console.log('Vote authenticated');

    // Advance time so that the maxVotingTimestamp is exceeded
    await starknetDevnet.provider.increaseTime(_max_voting_duration);
    await increaseEthBlockchainTime(eth_network, _max_voting_duration);

    console.log('Executing proposal...');
    const executeRes = await space.execute({ low: '0x1', high: '0x0' }, executionPayload);
    await provider.waitForTransaction(executeRes.transaction_hash);
    console.log('Proposal executed');

    // Propagating message to L1
    const flushL2Response = await starknetDevnetProvider.postman.flush();
    const message_payload = flushL2Response.messages_to_l1[0].payload;

    const [proposalId, proposal, votes] = extractMessagePayload(message_payload);

    const fakeProposalTx = {
      to: signer.address,
      value: 10,
      data: '0x22',
      operation: 0,
      salt: 1,
    };

    // Sending fake proposal tx to the execution strategy
    await expect(
      l1AvatarExecutionStrategy.execute(space.address, proposalId, proposal, votes, executionHash, [
        fakeProposalTx,
      ]),
    ).to.be.revertedWithCustomError(l1AvatarExecutionStrategy, 'InvalidPayload');
  });

  it('should revert execution if quorum is not met (abstain votes only)', async function () {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    await starkTxAuthenticator.connect(account);

    const proposalTx = {
      to: signer.address,
      value: 0,
      data: '0x22',
      operation: 0,
    };

    const abiCoder = new AbiCoder();
    const executionHash = keccak256(
      abiCoder.encode(
        ['tuple(address to, uint256 value, bytes data, uint8 operation)[]'],
        [[proposalTx]],
      ),
    );

    // Represent the execution hash as a Cairo Uint256
    const executionHashUint256: Uint256 = uint256.bnToUint256(executionHash);

    const executionPayload = [
      await l1AvatarExecutionStrategy.getAddress(),
      executionHashUint256.low,
      executionHashUint256.high,
    ];

    // Propose
    console.log('Authenticating proposal...');
    const proposeRes = await starkTxAuthenticator.authenticate_propose(
      space.address,
      account.address,
      choices,
      [],
      { address: ethRelayer.address, params: executionPayload },
      [],
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');

    // Advance time so that voting has started
    await starknetDevnet.provider.increaseTime(_voting_delay);
    await increaseEthBlockchainTime(eth_network, _voting_delay);

    // Voting
    console.log('Authenticating vote...');
    const choice = '0x2';
    const voteRes = await starkTxAuthenticator.authenticate_vote(
      space.address,
      account.address,
      { low: '0x1', high: '0x0' },
      choice,
      [{ index: '0x0', params: [] }],
      [],
    );
    await provider.waitForTransaction(voteRes.transaction_hash);
    console.log('Vote authenticated');

    // Advance time so that the maxVotingTimestamp is exceeded
    await starknetDevnet.provider.increaseTime(_max_voting_duration);
    await increaseEthBlockchainTime(eth_network, _max_voting_duration);

    // Execute
    console.log('Executing proposal...');
    const executeRes = await space.execute({ low: '0x1', high: '0x0' }, executionPayload);
    await provider.waitForTransaction(executeRes.transaction_hash);
    console.log('Proposal executed');

    // Propagating message to L1
    const flushL2Response = await starknetDevnetProvider.postman.flush();
    const message_payload = flushL2Response.messages_to_l1[0].payload;

    const [proposalId, proposal, votes] = extractMessagePayload(message_payload);

    await expect(
      l1AvatarExecutionStrategy.execute(space.address, proposalId, proposal, votes, executionHash, [
        proposalTx,
      ]),
    ).to.be.revertedWithCustomError(l1AvatarExecutionStrategy, 'InvalidProposalStatus');
  });

  it('should revert execution if quorum is not met (against votes only)', async function () {
    {
      await starknetDevnet.provider.restart();
      await starknetDevnet.provider.load('./dump.pkl');
      await starknetDevnetProvider.postman.loadL1MessagingContract(
        eth_network,
        mockMessagingContractAddress,
      );
      await starkTxAuthenticator.connect(account);

      const proposalTx = {
        to: signer.address,
        value: 0,
        data: '0x22',
        operation: 0,
      };

      const abiCoder = new AbiCoder();
      const executionHash = keccak256(
        abiCoder.encode(
          ['tuple(address to, uint256 value, bytes data, uint8 operation)[]'],
          [[proposalTx]],
        ),
      );

      // Represent the execution hash as a Cairo Uint256
      const executionHashUint256: Uint256 = uint256.bnToUint256(executionHash);

      const executionPayload = [
        await l1AvatarExecutionStrategy.getAddress(),
        executionHashUint256.low,
        executionHashUint256.high,
      ];

      // Propose
      console.log('Authenticating proposal...');
      const proposeRes = await starkTxAuthenticator.authenticate_propose(
        space.address,
        account.address,
        choices,
        [],
        { address: ethRelayer.address, params: executionPayload },
        [],
      );
      await provider.waitForTransaction(proposeRes.transaction_hash);
      console.log('Proposal authenticated');

      // Advance time so that voting has started
      await starknetDevnet.provider.increaseTime(_voting_delay);
      await increaseEthBlockchainTime(eth_network, _voting_delay);

      // Voting
      console.log('Authenticating vote...');
      const choice = '0x0';
      const voteRes = await starkTxAuthenticator.authenticate_vote(
        space.address,
        account.address,
        { low: '0x1', high: '0x0' },
        choice,
        [{ index: '0x0', params: [] }],
        [],
      );
      await provider.waitForTransaction(voteRes.transaction_hash);
      console.log('Vote authenticated');

      // Advance time so that the maxVotingTimestamp is exceeded
      await starknetDevnet.provider.increaseTime(_max_voting_duration);
      await increaseEthBlockchainTime(eth_network, _max_voting_duration);

      // Execute
      console.log('Executing proposal...');
      const executeRes = await space.execute({ low: '0x1', high: '0x0' }, executionPayload);
      await provider.waitForTransaction(executeRes.transaction_hash);
      console.log('Proposal executed');

      // Propagating message to L1
      const flushL2Response = await starknetDevnetProvider.postman.flush();
      const message_payload = flushL2Response.messages_to_l1[0].payload;

      const [proposalId, proposal, votes] = extractMessagePayload(message_payload);

      await expect(
        l1AvatarExecutionStrategy.execute(
          space.address,
          proposalId,
          proposal,
          votes,
          executionHash,
          [proposalTx],
        ),
      ).to.be.revertedWithCustomError(l1AvatarExecutionStrategy, 'InvalidProposalStatus');
    }
  });

  it('should revert execution if quorum is not met (no votes)', async function () {
    {
      await starknetDevnet.provider.restart();
      await starknetDevnet.provider.load('./dump.pkl');
      await starknetDevnetProvider.postman.loadL1MessagingContract(
        eth_network,
        mockMessagingContractAddress,
      );
      await starkTxAuthenticator.connect(account);

      const proposalTx = {
        to: signer.address,
        value: 0,
        data: '0x22',
        operation: 0,
      };

      const abiCoder = new AbiCoder();
      const executionHash = keccak256(
        abiCoder.encode(
          ['tuple(address to, uint256 value, bytes data, uint8 operation)[]'],
          [[proposalTx]],
        ),
      );

      // Represent the execution hash as a Cairo Uint256
      const executionHashUint256: Uint256 = uint256.bnToUint256(executionHash);

      const executionPayload = [
        await l1AvatarExecutionStrategy.getAddress(),
        executionHashUint256.low,
        executionHashUint256.high,
      ];

      // Propose
      console.log('Authenticating proposal...');
      const proposeRes = await starkTxAuthenticator.authenticate_propose(
        space.address,
        account.address,
        choices,
        [],
        { address: ethRelayer.address, params: executionPayload },
        [],
      );
      await provider.waitForTransaction(proposeRes.transaction_hash);
      console.log('Proposal authenticated');

      // Advance time so that voting has started
      await starknetDevnet.provider.increaseTime(_voting_delay);
      await increaseEthBlockchainTime(eth_network, _voting_delay);

      // No voting

      // Advance time so that the maxVotingTimestamp is exceeded
      await starknetDevnet.provider.increaseTime(_max_voting_duration);
      await increaseEthBlockchainTime(eth_network, _max_voting_duration);

      // Execute
      console.log('Executing proposal...');
      const executeRes = await space.execute({ low: '0x1', high: '0x0' }, executionPayload);
      await provider.waitForTransaction(executeRes.transaction_hash);
      console.log('Proposal executed');

      // Propagating message to L1
      const flushL2Response = await starknetDevnetProvider.postman.flush();
      const message_payload = flushL2Response.messages_to_l1[0].payload;

      const [proposalId, proposal, votes] = extractMessagePayload(message_payload);

      await expect(
        l1AvatarExecutionStrategy.execute(
          space.address,
          proposalId,
          proposal,
          votes,
          executionHash,
          [proposalTx],
        ),
      ).to.be.revertedWithCustomError(l1AvatarExecutionStrategy, 'InvalidProposalStatus');
    }
  });

  it('should revert execution if voting period is not exceeded', async function () {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    await starkTxAuthenticator.connect(account);

    const proposalTx = {
      to: signer.address,
      value: 0,
      data: '0x22',
      operation: 0,
    };

    const abiCoder = new AbiCoder();
    const executionHash = keccak256(
      abiCoder.encode(
        ['tuple(address to, uint256 value, bytes data, uint8 operation)[]'],
        [[proposalTx]],
      ),
    );

    // Represent the execution hash as a Cairo Uint256
    const executionHashUint256: Uint256 = uint256.bnToUint256(executionHash);

    const executionPayload = [
      await l1AvatarExecutionStrategy.getAddress(),
      executionHashUint256.low,
      executionHashUint256.high,
    ];

    // Propose
    console.log('Authenticating proposal...');
    const proposeRes = await starkTxAuthenticator.authenticate_propose(
      space.address,
      account.address,
      choices,
      [],
      { address: ethRelayer.address, params: executionPayload },
      [],
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');

    // Advance time so that voting has started
    await starknetDevnet.provider.increaseTime(_voting_delay);
    await increaseEthBlockchainTime(eth_network, _voting_delay);

    // Voting
    console.log('Authenticating vote...');
    const choice = '0x1';
    const voteRes = await starkTxAuthenticator.authenticate_vote(
      space.address,
      account.address,
      { low: '0x1', high: '0x0' },
      choice,
      [{ index: '0x0', params: [] }],
      [],
    );
    await provider.waitForTransaction(voteRes.transaction_hash);
    console.log('Vote authenticated');

    // Try to execute before max Voting Timestamp is exceeded
    try {
      console.log('Trying to executing proposal...');
      const executeRes = await space.execute({ low: '0x1', high: '0x0' }, executionPayload);
      await provider.waitForTransaction(executeRes.transaction_hash);
      expect.fail('Should have failed');
    } catch (err) {
      expect(err.message).to.contain(shortString.encodeShortString('Before max end timestamp'));
      console.log('Invalid proposal failed as expected');
    }
  });
});
