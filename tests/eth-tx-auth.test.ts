import { expect } from 'chai';
import dotenv from 'dotenv';
import { poseidonHashMany } from 'micro-starknet';
import { ethers, config } from 'hardhat';
import { HttpNetworkConfig } from 'hardhat/types';
import {
  RpcProvider as StarknetRpcProvider,
  Account as StarknetAccount,
  Contract as StarknetContract,
  CallData,
  cairo,
  selector,
} from 'starknet';
import { Contract as EthContract } from 'ethers';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import {
  Devnet as StarknetDevnet,
  DevnetProvider as StarknetDevnetProvider,
} from 'starknet-devnet';
import { getCompiledCode } from './utils';

dotenv.config();

const eth_network: string = (config.networks.ethereumLocal as HttpNetworkConfig).url;
const account_address = process.env.ADDRESS || '';
const account_pk = process.env.PK || '';
const choices = '0x3';

describe('Ethereum Transaction Authenticator', function () {
  this.timeout(1000000);

  let signer: HardhatEthersSigner;
  let invalidSigner: HardhatEthersSigner;
  let starknetCommit: EthContract;

  let account: StarknetAccount;
  let ethTxAuthenticator: StarknetContract;
  let vanillaVotingStrategy: StarknetContract;
  let vanillaProposalValidationStrategy: StarknetContract;
  let space: StarknetContract;

  let starknetDevnet: StarknetDevnet;
  let starknetDevnetProvider: StarknetDevnetProvider;
  let provider: StarknetRpcProvider;

  let mockMessagingContractAddress: string;

  const _owner = 1;
  const _min_voting_duration = 100;
  const _max_voting_duration = 200;
  const _voting_delay = 100;
  let _proposal_validation_strategy: { address: string; params: string[] };
  const _proposal_validation_strategy_metadata_uri = [];
  let _voting_strategies: { address: string; params: string[] }[];
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
    console.log('Devnet spawned!');

    console.log('Loading L1 Messaging Contract');
    const messagingLoadResponse =
      await starknetDevnetProvider.postman.loadL1MessagingContract(eth_network);
    mockMessagingContractAddress = messagingLoadResponse.messaging_contract_address;
    console.log('Mock messaging contract: ', mockMessagingContractAddress);

    provider = new StarknetRpcProvider({ nodeUrl: starknetDevnet.provider.url });

    // Account used for deployments
    account = new StarknetAccount(provider, account_address, account_pk);

    const signers = await ethers.getSigners();
    signer = signers[0];
    invalidSigner = signers[1];

    // Deploy Starknet Commit contract to L1
    console.log('Deploying Starknet Commit contract to L1');
    const starknetCommitFactory = await ethers.getContractFactory('StarknetCommitMockMessaging');
    starknetCommit = await starknetCommitFactory.deploy(mockMessagingContractAddress);
    console.log('Starknet Commit contract deployed to L1: ', await starknetCommit.getAddress());

    console.log('Deploying Eth Tx Authenticator...');
    const { sierraCode: auth_sierra, casmCode: auth_casm } =
      await getCompiledCode('sx_EthTxAuthenticator');
    const auth_calldata = CallData.compile({
      starknet_commit_address: await starknetCommit.getAddress(),
    });
    const auth_response = await account.declareAndDeploy({
      contract: auth_sierra,
      casm: auth_casm,
      constructorCalldata: auth_calldata,
    });
    ethTxAuthenticator = new StarknetContract(
      auth_sierra.abi,
      auth_response.deploy.contract_address,
      provider,
    );
    console.log('Eth Tx Authenticator deployed: ', ethTxAuthenticator.address);

    console.log('Deploying Vanilla Voting Strategy...');
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
    console.log('Vanilla Voting Strategy deployed: ', vanillaVotingStrategy.address);

    console.log('Deploying Vanilla Proposal Validation Strategy...');
    const { sierraCode: validation_sierra, casmCode: validation_casm } = await getCompiledCode(
      'sx_VanillaProposalValidationStrategy',
    );
    const validation_response = await account.declareAndDeploy({
      contract: validation_sierra,
      casm: validation_casm,
    });
    vanillaProposalValidationStrategy = new StarknetContract(
      validation_sierra.abi,
      validation_response.deploy.contract_address,
      provider,
    );
    console.log(
      'Vanilla Proposal Validation Strategy deployed: ',
      vanillaProposalValidationStrategy.address,
    );

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

    _proposal_validation_strategy = {
      address: vanillaProposalValidationStrategy.address,
      params: [],
    };
    _voting_strategies = [{ address: vanillaVotingStrategy.address, params: [] }];
    _authenticators = [ethTxAuthenticator.address];

    space.connect(account);

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
  });

  it('can authenticate a proposal, a vote, and a proposal update', async () => {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    ethTxAuthenticator.connect(account);

    const proposal = {
      author: signer.address,
      choices: choices,
      metadataUri: ['0x1', '0x1'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
      executionStrategy: {
        address: '0x0000000000000000000000000000000000005678',
        params: ['0x0'],
      },
      userProposalValidationParams: [
        '0xffffffffffffffffffffffffffffffffffffffffff',
        '0x1234',
        '0x5678',
        '0x9abc',
      ],
    };

    const proposeCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('propose'),
      ...proposal,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const proposalCommit = `0x${poseidonHashMany(
      proposeCommitPreImage.map((v) => BigInt(v)),
    ).toString(16)}`;
    console.log('Proposal commit: ', proposalCommit);

    console.log('Committing proposal on L1...');
    await starknetCommit.commit(ethTxAuthenticator.address, proposalCommit, {
      value: 18485000000000,
    });
    console.log('Committed!');

    // Checking that the L1 -> L2 message has been propagated
    console.log('Flushing messages...');
    await starknetDevnetProvider.postman.flush();
    console.log('Messages flushed!');

    console.log('Authenticating proposal...');
    const proposeRes = await ethTxAuthenticator.authenticate_propose(
      space.address,
      proposal.author,
      proposal.choices,
      proposal.metadataUri,
      proposal.executionStrategy,
      proposal.userProposalValidationParams,
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');

    const updateProposal = {
      author: signer.address,
      proposalId: cairo.uint256('0x1'),
      choices: choices,
      executionStrategy: {
        address: '0x0000000000000000000000000000000000005678',
        params: ['0x0'],
      },
      metadataUri: ['0x1', '0x2'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
    };

    const updateCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('update_proposal'),
      ...updateProposal,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const updateCommit = `0x${poseidonHashMany(updateCommitPreImage.map((v) => BigInt(v))).toString(
      16,
    )}`;

    console.log('Update commit: ', updateCommit);

    console.log('Committing update proposal on L1...');
    await starknetCommit.commit(ethTxAuthenticator.address, updateCommit, {
      value: 18485000000000,
    });

    // Checking that the L1 -> L2 message has been propagated
    await starknetDevnetProvider.postman.flush();

    console.log('Authenticating update proposal...');
    const updateRes = await ethTxAuthenticator.authenticate_update_proposal(
      space.address,
      updateProposal.author,
      updateProposal.proposalId,
      updateProposal.choices,
      updateProposal.executionStrategy,
      updateProposal.metadataUri,
    );
    await provider.waitForTransaction(updateRes.transaction_hash);
    console.log('Update proposal authenticated');

    // Increase time so voting period begins
    await starknetDevnet.provider.increaseTime(_voting_delay);

    const choice = '0x1';
    const vote = {
      voter: signer.address,
      proposalId: cairo.uint256('0x1'),
      choice: choice,
      userVotingStrategies: [{ index: '0x0', params: ['0x1', '0x2', '0x3', '0x4'] }],
      metadataUri: ['0x1', '0x3'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
    };

    const voteCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('vote'),
      ...vote,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const voteCommit = `0x${poseidonHashMany(voteCommitPreImage.map((v) => BigInt(v))).toString(
      16,
    )}`;

    console.log('Vote commit: ', voteCommit);

    console.log('Committing vote on L1...');
    await starknetCommit.commit(ethTxAuthenticator.address, voteCommit, { value: 18485000000000 });
    console.log('Vote committed!');

    // Checking that the L1 -> L2 message has been propagated
    await starknetDevnetProvider.postman.flush();

    console.log('Authenticating vote...');
    const voteRes = await ethTxAuthenticator.authenticate_vote(
      space.address,
      vote.voter,
      vote.proposalId,
      choice,
      vote.userVotingStrategies,
      vote.metadataUri,
    );
    await provider.waitForTransaction(voteRes.transaction_hash);
    console.log('Vote authenticated');
  });

  it('should revert if an invalid hash of an action was committed', async () => {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    ethTxAuthenticator.connect(account);

    const proposal = {
      author: signer.address,
      choices: choices,
      metadataUri: ['0x1', '0x4'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
      executionStrategy: {
        address: '0x0000000000000000000000000000000000005678',
        params: ['0x0'],
      },
      userProposalValidationParams: [
        '0xffffffffffffffffffffffffffffffffffffffffff',
        '0x1234',
        '0x5678',
        '0x9abc',
      ],
    };

    const proposeCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('propose'),
      ...proposal,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const proposalCommit = `0x${poseidonHashMany(
      proposeCommitPreImage.map((v) => BigInt(v)),
    ).toString(16)}`;

    console.log('Proposal commit: ', proposalCommit);

    console.log('Committing proposal on L1...');
    await starknetCommit.commit(ethTxAuthenticator.address, proposalCommit, {
      value: 18485000000000,
    });
    console.log('Committed!');

    // Checking that the L1 -> L2 message has been propagated
    console.log('Flushing messages...');
    await starknetDevnetProvider.postman.flush();
    console.log('Messages flushed!');

    // Authenticating with a different user
    try {
      console.log('Authenticating proposal with a different user...');
      const proposeRes = await ethTxAuthenticator.authenticate_propose(
        space.address,
        invalidSigner.address,
        proposal.choices,
        proposal.metadataUri,
        proposal.executionStrategy,
        proposal.userProposalValidationParams,
      );
      await provider.waitForTransaction(proposeRes.transaction_hash);
      console.log('Proposal authenticated');
      expect.fail('Should have failed');
    } catch (err) {
      expect(err.message).to.contain('Commit not found');
      console.log('Proposal authentication failed as expected');
    }

    console.log('Authenticating proposal...');
    const proposeRes = await ethTxAuthenticator.authenticate_propose(
      space.address,
      proposal.author,
      proposal.choices,
      proposal.metadataUri,
      proposal.executionStrategy,
      proposal.userProposalValidationParams,
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');

    const updateProposal = {
      author: signer.address,
      proposalId: cairo.uint256('0x1'),
      choices: choices,
      executionStrategy: {
        address: '0x0000000000000000000000000000000000005678',
        params: ['0x0'],
      },
      metadataUri: ['0x1', '0x5'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
    };

    const updateCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('update_proposal'),
      ...updateProposal,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const updateCommit = `0x${poseidonHashMany(updateCommitPreImage.map((v) => BigInt(v))).toString(
      16,
    )}`;

    console.log('Update commit: ', updateCommit);

    console.log('Committing update proposal on L1...');
    await starknetCommit.commit(ethTxAuthenticator.address, updateCommit, {
      value: 18485000000000,
    });

    // Checking that the L1 -> L2 message has been propagated
    await starknetDevnetProvider.postman.flush();

    // Authenticating update proposal with a different user
    try {
      console.log('Authenticating update proposal with a different user...');
      const updateRes = await ethTxAuthenticator.authenticate_update_proposal(
        space.address,
        invalidSigner.address,
        updateProposal.proposalId,
        updateProposal.choices,
        updateProposal.executionStrategy,
        updateProposal.metadataUri,
      );
      await provider.waitForTransaction(updateRes.transaction_hash);
      console.log('Update proposal authenticated');
      expect.fail('Should have failed');
    } catch (err) {
      expect(err.message).to.contain('Commit not found');
      console.log('Update proposal authentication failed as expected');
    }

    console.log('Authenticating update proposal...');
    const updateRes = await ethTxAuthenticator.authenticate_update_proposal(
      space.address,
      updateProposal.author,
      updateProposal.proposalId,
      updateProposal.choices,
      updateProposal.executionStrategy,
      updateProposal.metadataUri,
    );
    await provider.waitForTransaction(updateRes.transaction_hash);
    console.log('Update proposal authenticated');

    // Increase time so voting period begins
    await starknetDevnet.provider.increaseTime(_voting_delay);

    const choice = '0x1';
    const vote = {
      voter: signer.address,
      proposalId: cairo.uint256('0x1'),
      choice: choice,
      userVotingStrategies: [{ index: '0x0', params: ['0x1', '0x2', '0x3', '0x4'] }],
      metadataUri: ['0x1', '0x6'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
    };

    const voteCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('vote'),
      ...vote,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const voteCommit = `0x${poseidonHashMany(voteCommitPreImage.map((v) => BigInt(v))).toString(
      16,
    )}`;

    console.log('Vote commit: ', voteCommit);

    console.log('Committing vote on L1...');
    await starknetCommit.commit(ethTxAuthenticator.address, voteCommit, { value: 18485000000000 });
    console.log('Vote committed!');

    // Checking that the L1 -> L2 message has been propagated
    await starknetDevnetProvider.postman.flush();

    // Authenticating vote with a different user
    try {
      console.log('Authenticating vote with a different user...');
      const voteRes = await ethTxAuthenticator.authenticate_vote(
        space.address,
        invalidSigner.address,
        vote.proposalId,
        choice,
        vote.userVotingStrategies,
        vote.metadataUri,
      );
      await provider.waitForTransaction(voteRes.transaction_hash);
      console.log('Vote authenticated');
      expect.fail('Should have failed');
    } catch (err) {
      expect(err.message).to.contain('Commit not found');
      console.log('Vote authentication failed as expected');
    }

    console.log('Authenticating vote...');
    const voteRes = await ethTxAuthenticator.authenticate_vote(
      space.address,
      vote.voter,
      vote.proposalId,
      choice,
      vote.userVotingStrategies,
      vote.metadataUri,
    );
    await provider.waitForTransaction(voteRes.transaction_hash);
    console.log('Vote authenticated');
  });

  it('should revert if a commit was made by a different address to the author/voter address', async () => {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    ethTxAuthenticator.connect(account);

    const proposal = {
      author: signer.address,
      choices: choices,
      metadataUri: ['0x1', '0x7'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
      executionStrategy: {
        address: '0x0000000000000000000000000000000000005678',
        params: ['0x0'],
      },
      userProposalValidationParams: [
        '0xffffffffffffffffffffffffffffffffffffffffff',
        '0x1234',
        '0x5678',
        '0x9abc',
      ],
    };

    const proposeCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('propose'),
      ...proposal,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const proposalCommit = `0x${poseidonHashMany(
      proposeCommitPreImage.map((v) => BigInt(v)),
    ).toString(16)}`;
    console.log('Proposal commit: ', proposalCommit);

    console.log('Committing proposal on L1...');
    await starknetCommit
      .connect(invalidSigner)
      .commit(ethTxAuthenticator.address, proposalCommit, { value: 18485000000000 });
    console.log('Committed!');

    // Checking that the L1 -> L2 message has been propagated
    console.log('Flushing messages...');
    await starknetDevnetProvider.postman.flush();
    console.log('Messages flushed!');

    try {
      console.log('Authenticating proposal...');
      const proposeRes = await ethTxAuthenticator.authenticate_propose(
        space.address,
        proposal.author,
        proposal.choices,
        proposal.metadataUri,
        proposal.executionStrategy,
        proposal.userProposalValidationParams,
      );
      await provider.waitForTransaction(proposeRes.transaction_hash);
      expect.fail('Should have failed');
    } catch (err) {
      expect(err.message).to.contain('Commit not found');
      console.log('Proposal authentication failed as expected');
    }
  });

  it('should not revert if the same commit was made twice', async () => {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    ethTxAuthenticator.connect(account);

    const proposal = {
      author: signer.address,
      choices: choices,
      metadataUri: ['0x1', '0x8'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
      executionStrategy: {
        address: '0x0000000000000000000000000000000000005678',
        params: ['0x0'],
      },
      userProposalValidationParams: [
        '0xffffffffffffffffffffffffffffffffffffffffff',
        '0x1234',
        '0x5678',
        '0x9abc',
      ],
    };

    const proposeCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('propose'),
      ...proposal,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const proposalCommit = `0x${poseidonHashMany(
      proposeCommitPreImage.map((v) => BigInt(v)),
    ).toString(16)}`;
    console.log('Proposal commit: ', proposalCommit);

    console.log('Committing proposal on L1 from another signer...');
    await starknetCommit
      .connect(invalidSigner)
      .commit(ethTxAuthenticator.address, proposalCommit, { value: 18485000000000 });
    console.log('Committed!');

    // Checking that the L1 -> L2 message has been propagated
    console.log('Flushing messages...');
    await starknetDevnetProvider.postman.flush();
    console.log('Messages flushed!');

    console.log('Committing proposal on L1 from the correct signer...');
    await starknetCommit.commit(ethTxAuthenticator.address, proposalCommit, {
      value: 18485000000000,
    });
    console.log('Committed!');

    // Checking that the L1 -> L2 message has been propagated
    console.log('Flushing messages...');
    await starknetDevnetProvider.postman.flush();
    console.log('Messages flushed!');

    console.log('Authenticating proposal...');
    const proposeRes = await ethTxAuthenticator.authenticate_propose(
      space.address,
      proposal.author,
      proposal.choices,
      proposal.metadataUri,
      proposal.executionStrategy,
      proposal.userProposalValidationParams,
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');
  });

  it('a commit cannot be consumed twice', async () => {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    ethTxAuthenticator.connect(account);

    const proposal = {
      author: signer.address,
      choices: choices,
      metadataUri: ['0x1', '0x9'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
      executionStrategy: {
        address: '0x0000000000000000000000000000000000005678',
        params: ['0x0'],
      },
      userProposalValidationParams: [
        '0xffffffffffffffffffffffffffffffffffffffffff',
        '0x1234',
        '0x5678',
        '0x9abc',
      ],
    };

    const proposeCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('propose'),
      ...proposal,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const proposalCommit = `0x${poseidonHashMany(
      proposeCommitPreImage.map((v) => BigInt(v)),
    ).toString(16)}`;
    console.log('Proposal commit: ', proposalCommit);

    console.log('Committing proposal on L1...');
    await starknetCommit.commit(ethTxAuthenticator.address, proposalCommit, {
      value: 18485000000000,
    });
    console.log('Committed!');

    // Checking that the L1 -> L2 message has been propagated
    console.log('Flushing messages...');
    await starknetDevnetProvider.postman.flush();
    console.log('Messages flushed!');

    console.log('Authenticating proposal...');
    const proposeRes = await ethTxAuthenticator.authenticate_propose(
      space.address,
      proposal.author,
      proposal.choices,
      proposal.metadataUri,
      proposal.executionStrategy,
      proposal.userProposalValidationParams,
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');

    // Attempting to replay the same commit
    try {
      console.log('Trying to replay the proposal creationc commit...');
      const proposeRes = await ethTxAuthenticator.authenticate_propose(
        space.address,
        proposal.author,
        proposal.choices,
        proposal.metadataUri,
        proposal.executionStrategy,
        proposal.userProposalValidationParams,
      );
      await provider.waitForTransaction(proposeRes.transaction_hash);
      expect.fail('Should have failed');
    } catch (err) {
      expect(err.message).to.contain('Commit not found');
      console.log('Proposal authentication failed as expected');
    }
  });

  it('a commit cannot be overwritten by a different sender', async () => {
    await starknetDevnet.provider.restart();
    await starknetDevnet.provider.load('./dump.pkl');
    await starknetDevnetProvider.postman.loadL1MessagingContract(
      eth_network,
      mockMessagingContractAddress,
    );
    ethTxAuthenticator.connect(account);

    const proposal = {
      author: signer.address,
      choices: choices,
      metadataUri: ['0x1', '0xa'], // We use metadataUris with different values because the L1 devnet does not reset so we need to make sure the commit is different
      executionStrategy: {
        address: '0x0000000000000000000000000000000000005678',
        params: ['0x0'],
      },
      userProposalValidationParams: [
        '0xffffffffffffffffffffffffffffffffffffffffff',
        '0x1234',
        '0x5678',
        '0x9abc',
      ],
    };

    const proposeCommitPreImage = CallData.compile({
      target: space.address,
      selector: selector.getSelectorFromName('propose'),
      ...proposal,
    });

    // Commit hash of payload to the Starknet Commit L1 contract
    const proposalCommit = `0x${poseidonHashMany(
      proposeCommitPreImage.map((v) => BigInt(v)),
    ).toString(16)}`;
    console.log('Proposal commit: ', proposalCommit);

    console.log('Committing proposal on L1 from the correct signer...');
    await starknetCommit.commit(ethTxAuthenticator.address, proposalCommit, {
      value: 18485000000000,
    });
    console.log('Committed!');

    console.log('Committing proposal on L1 from another signer...');
    await starknetCommit
      .connect(invalidSigner)
      .commit(ethTxAuthenticator.address, proposalCommit, { value: 18485000000000 });
    console.log('Committed!');

    // Checking that the L1 -> L2 message has been propagated
    console.log('Flushing messages...');
    await starknetDevnetProvider.postman.flush();
    console.log('Messages flushed!');

    // The commit by the correct signer should be accepted
    console.log('Authenticating proposal...');
    const proposeRes = await ethTxAuthenticator.authenticate_propose(
      space.address,
      proposal.author,
      proposal.choices,
      proposal.metadataUri,
      proposal.executionStrategy,
      proposal.userProposalValidationParams,
    );
    await provider.waitForTransaction(proposeRes.transaction_hash);
    console.log('Proposal authenticated');
  });
});
