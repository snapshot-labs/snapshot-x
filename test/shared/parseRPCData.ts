/* eslint-disable  @typescript-eslint/ban-types */

import Common, { Chain, Hardfork } from '@ethereumjs/common';
import { bufferToHex } from 'ethereumjs-util';
import blockFromRpc from '@ethereumjs/block/dist/from-rpc';
import { IntsSequence } from './types';
import { hexToBytes } from './helpers';

export interface ProcessBlockInputs {
  blockNumber: number;
  blockOptions: number;
  headerInts: IntsSequence;
}

export function getProcessBlockInputs(
  block: any,
  _chain: Chain = Chain.Mainnet,
  _hardfork: Hardfork = Hardfork.London
): ProcessBlockInputs {
  block.difficulty = '0x' + BigInt(block.difficulty).toString(16);
  block.totalDifficulty = '0x' + BigInt(block.totalDifficulty).toString(16);
  const common = new Common({ chain: _chain, hardfork: _hardfork });
  const header = blockFromRpc(block, [], { common }).header;
  const headerRlp = bufferToHex(header.serialize());
  const headerInts = IntsSequence.fromBytes(hexToBytes(headerRlp));
  return {
    blockNumber: block.number as number,
    blockOptions: 8 as number,
    headerInts: headerInts as IntsSequence,
  };
}

export interface ProofInputs {
  blockNumber: number;
  accountOptions: number;
  ethAddress: IntsSequence;
  ethAddressFelt: bigint; //Fossil treats eth addresses two different ways for some reason, it will be changed soon but now this works
  accountProofSizesBytes: bigint[];
  accountProofSizesWords: bigint[];
  accountProof: bigint[];
  userVotingPowerParams: bigint[];
}

export function getProofInputs(
  blockNumber: number,
  proofs: any,
  encodeParams: Function
): ProofInputs {
  const accountProofArray = proofs.accountProof.map((node: string) =>
    IntsSequence.fromBytes(hexToBytes(node))
  );
  let accountProof: bigint[] = [];
  let accountProofSizesBytes: bigint[] = [];
  let accountProofSizesWords: bigint[] = [];
  for (const node of accountProofArray) {
    accountProof = accountProof.concat(node.values);
    accountProofSizesBytes = accountProofSizesBytes.concat([BigInt(node.bytesLength)]);
    accountProofSizesWords = accountProofSizesWords.concat([BigInt(node.values.length)]);
  }
  const ethAddress = IntsSequence.fromBytes(hexToBytes(proofs.address));
  const ethAddressFelt = BigInt(proofs.address);
  const slot = IntsSequence.fromBytes(hexToBytes(proofs.storageProof[0].key));
  const storageProofArray = proofs.storageProof[0].proof.map((node: string) =>
    IntsSequence.fromBytes(hexToBytes(node))
  );
  let storageProof: bigint[] = [];
  let storageProofSizesBytes: bigint[] = [];
  let storageProofSizesWords: bigint[] = [];
  for (const node of storageProofArray) {
    storageProof = storageProof.concat(node.values);
    storageProofSizesBytes = storageProofSizesBytes.concat([BigInt(node.bytesLength)]);
    storageProofSizesWords = storageProofSizesWords.concat([BigInt(node.values.length)]);
  }
  const userVotingPowerParams = encodeParams(
    slot.values,
    storageProofSizesBytes,
    storageProofSizesWords,
    storageProof
  );
  return {
    blockNumber: blockNumber as number,
    accountOptions: 15 as number,
    ethAddress: ethAddress as IntsSequence,
    ethAddressFelt: ethAddressFelt as bigint,
    accountProofSizesBytes: accountProofSizesBytes as bigint[],
    accountProofSizesWords: accountProofSizesWords as bigint[],
    accountProof: accountProof as bigint[],
    userVotingPowerParams: userVotingPowerParams as bigint[],
  };
}
