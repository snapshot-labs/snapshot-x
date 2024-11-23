import dotenv from 'dotenv';
import axios from 'axios';
import { ethers } from 'ethers';
import {
  RpcProvider,
  Account,
  CallData,
  cairo,
  Contract,
  CairoOption,
  CairoOptionVariant,
} from 'starknet';
import { utils } from '@snapshot-labs/sx';

dotenv.config();

type ProofElement = {
  index: number;
  value: string;
  proof: string[];
};

const accountAddress = process.env.ADDRESS || '';
const accountPk = process.env.PK || '';
const starknetNetworkUrl = process.env.STARKNET_NETWORK_URL || '';
const ethNetworkUrl = process.env.ETH_NETWORK_URL || '';
const herodotusApiKey = process.env.HERODOTUS_API_KEY || '';

async function main() {
  const provider = new RpcProvider({ nodeUrl: starknetNetworkUrl });
  const account = new Account(provider, accountAddress, accountPk);

  const spaceAddress = '0x2f998d51f78d2b23fea4e8af8306d67095fafaa2a6f76e7e328db6ba3e87bcd';
  const vanillaAuthenticatorAddress =
    '0x046ad946f22ac4e14e271f24309f14ac36f0fde92c6831a605813fefa46e0893';
  const evmSlotValueVotingStrategyAddress =
    '0x474edaba6e88a1478d0680bb97f43f01e6a311593ddc496da58d5a7e7a647cf';

  // OZ Votes token 18 decimals
  const l1TokenAddress = '0xd96844c9B21CB6cCf2c236257c7fc703E43BA071';
  // Slot index of the checkpoints mapping in the token contract,
  //obtained using Foundry's Cast Storage Layout tool.
  const slotIndex = 8;

  const voterAddress = '0x1fb824f4a6f82de72ae015931e5cf6923f9acb0f';

  const { abi: spaceAbi } = await provider.getClassAt(spaceAddress);
  const space = new Contract(spaceAbi, spaceAddress, provider);

  const { abi: vanillaAuthenticatorAbi } = await provider.getClassAt(vanillaAuthenticatorAddress);
  const vanillaAuthenticator = new Contract(
    vanillaAuthenticatorAbi,
    vanillaAuthenticatorAddress,
    provider,
  );
  vanillaAuthenticator.connect(account);

  const l1Token = new ethers.Contract(
    l1TokenAddress,
    ['function numCheckpoints(address account) public view returns (uint256)'],
    new ethers.JsonRpcProvider(ethNetworkUrl),
  );
  const numCheckpoints = await l1Token.numCheckpoints(voterAddress);
  console.log(numCheckpoints);

  // Deriving the keys of the final slot in the checkpoints array for the voter and the next empty slot
  const checkpointSlotKey =
    BigInt(
      ethers.keccak256(
        ethers.keccak256(
          `0x${voterAddress.slice(2).padStart(64, '0')}${slotIndex.toString(16).padStart(64, '0')}`,
        ),
      ),
    ) +
    BigInt(numCheckpoints) -
    BigInt(1);
  const nextEmptySlotKey = checkpointSlotKey + BigInt(1);

  let response;

  // Create a proposal
  await account.execute({
    contractAddress: vanillaAuthenticatorAddress,
    entrypoint: 'authenticate',
    calldata: CallData.compile({
      target: spaceAddress,
      selector: '0x1bfd596ae442867ef71ca523061610682af8b00fc2738329422f4ad8d220b81',
      data: CallData.compile({
        author: utils.starknetEnums.getUserAddressEnum('ETHEREUM', voterAddress),
        metadataUri: ['0x1', '0x2', '0x3', '0x4'],
        executionStrategy: {
          address: '0x0000000000000000000000000000000000005678',
          params: ['0x0'],
        },
        userProposalValidationParams: [],
      }),
    }),
  });

  // Get the snapshot timestamp of the proposal just created
  const proposalId = Number(await space.call('next_proposal_id', [])) - 1;
  const proposalStruct = (await space.call('proposals', [proposalId])) as any;
  const snapshotTimestamp = proposalStruct.start_timestamp;

  // Proving the token storage root of the token at the snapshot timestamp
  // Webhook here is just a random address, can update
  response = await axios({
    method: 'post',
    url: 'https://api.herodotus.cloud/submit-batch-query?apiKey=' + herodotusApiKey,
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
    },
    data: {
      destinationChainId: 'SN_GOERLI',
      fee: '0',
      data: {
        '5': {
          [`${'timestamp:'}${snapshotTimestamp}`]: {
            accounts: {
              [l1TokenAddress]: {
                props: ['STORAGE_ROOT'],
              },
            },
          },
        },
      },
      webhook: {
        url: 'https://webhook.site/1f3a9b5d-5c8c-4e2a-9d7e-6c3c5a0a0e2f',
        headers: {
          'Content-Type': 'application/json',
        },
      },
    },
  });
  console.log(response.data);

  // Wait for the query to be processed. This will return a query status of DONE when it's ready
  // Webhooks can be used to get notified when the query is ready.
  response = await axios({
    method: 'get',
    url:
      'https://api.herodotus.cloud/batch-query-status?apiKey=' +
      herodotusApiKey +
      '&batchQueryId=' +
      response.data.internalId,
    headers: {
      accept: 'application/json',
    },
  });
  console.log(response.data);

  // Get the binary search tree to remap the snapshot timestamp to the L1 block number
  response = await axios({
    method: 'get',
    url:
      'https://ds-indexer.api.herodotus.cloud/binsearch-path?timestamp=' +
      snapshotTimestamp +
      '&deployed_on_chain=SN_GOERLI&accumulates_chain=5',
    headers: {
      accept: 'application/json',
    },
  });

  // This is the snapshot L1 block number
  const l1BlockNumber = response.data.path[1].blockNumber;
  console.log(l1BlockNumber);

  // cache block number in voting strategy
  await account.execute({
    contractAddress: evmSlotValueVotingStrategyAddress,
    entrypoint: 'cache_timestamp',
    calldata: CallData.compile({
      timestamp: snapshotTimestamp,
      tree: {
        mapped_id: response.data.remapper.onchainRemapperId,
        last_pos: 3,
        peaks: response.data.proofs[0].peaksHashes,
        proofs: response.data.proofs.map((proof: any) => {
          return {
            index: proof.elementIndex,
            value: cairo.uint256(proof.elementHash),
            proof: proof.siblingsHashes,
          };
        }),
        left_neighbor: new CairoOption<ProofElement>(CairoOptionVariant.None),
      },
    }),
  });

  // Query the node for the storage proofs of the 2 slots at the snapshot block number
  response = await axios({
    method: 'post',
    url: ethNetworkUrl,
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
    },
    data: {
      id: 1,
      jsonrpc: '2.0',
      method: 'eth_getProof',
      params: [
        l1TokenAddress,
        [`0x${checkpointSlotKey.toString(16)}`, `0x${nextEmptySlotKey.toString(16)}`],
        `0x${l1BlockNumber.toString(16)}`,
      ],
    },
  });

  // This takes the proofs from the response and converts them to a list of 64 bit little endian words
  const storageProofsLittleEndianWords64 = response.data.result.storageProof.map(
    (proofWrapper: any) =>
      proofWrapper.proof.map(
        (node: string) =>
          node
            .slice(2)
            .match(/.{1,16}/g)
            ?.map(
              (word: string) =>
                `0x${word
                  .replace(/^(.(..)*)$/, '0$1')
                  .match(/../g)
                  ?.reverse()
                  .join('')}`,
            ),
      ),
  );

  // Cast Vote
  await account.execute({
    contractAddress: vanillaAuthenticatorAddress,
    entrypoint: 'authenticate',
    calldata: CallData.compile({
      target: spaceAddress,
      selector: '0x132bdf85fc8aa10ac3c22f02317f8f53d4b4f52235ed1eabb3a4cbbe08b5c41',
      data: CallData.compile({
        voter: utils.starknetEnums.getUserAddressEnum('ETHEREUM', voterAddress),
        proposalId: cairo.uint256(proposalId),
        choice: '0x1',
        user_voting_strategies: [
          {
            index: '0x0',
            params: CallData.compile({
              checkpoint_index: numCheckpoints - BigInt(1),
              checkpoint_mpt_proof: storageProofsLittleEndianWords64[0],
              exclusion_mpt_proof: storageProofsLittleEndianWords64[1],
            }),
          },
        ],
        metadataUri: ['0x1', '0x2', '0x3', '0x4'],
      }),
    }),
  });
}

main();
