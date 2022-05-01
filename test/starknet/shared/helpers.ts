import { ethers } from 'hardhat';
import { SplitUint256 } from './types';
import { expect } from 'chai';
import { computeHashOnElements } from 'starknet/dist/utils/hash';
import { toBN } from 'starknet/dist/utils/number';
import { EIP712_TYPES } from '../../ethereum/shared/utils';
import { _TypedDataEncoder } from '@ethersproject/hash';

export function assert(condition: boolean, message = 'Assertion Failed'): boolean {
  if (!condition) {
    throw message;
  }
  return condition;
}

export function hexToBytes(hex: string): number[] {
  const bytes = [];
  for (let c = 2; c < hex.length; c += 2) bytes.push(parseInt(hex.substring(c, c + 2), 16));
  return bytes;
}

export function bytesToHex(bytes: number[]): string {
  const body = Array.from(bytes, function (byte) {
    return ('0' + (byte & 0xff).toString(16)).slice(-2);
  }).join('');
  return '0x' + body;
}

/**
 * Receives a hex address, converts it to bigint, converts it back to hex.
 * This is done to strip leading zeros.
 * @param address a hex string representation of an address
 * @returns an adapted hex string representation of the address
 */
export function adaptAddress(address: string) {
  return '0x' + BigInt(address).toString(16);
}

/**
 * Expects address equality after adapting them.
 * @param actual
 * @param expected
 */
export function expectAddressEquality(actual: string, expected: string) {
  expect(adaptAddress(actual)).to.equal(adaptAddress(expected));
}

export function wordsToUint(word1: bigint, word2: bigint, word3: bigint, word4: bigint): bigint {
  const s3 = BigInt(2 ** 64);
  const s2 = BigInt(2 ** 128);
  const s1 = BigInt(2 ** 192);
  return word4 + word3 * s3 + word2 * s2 + word1 * s1;
}

export function uintToWords(
  uint: bigint
): [word1: bigint, word2: bigint, word3: bigint, word4: bigint] {
  const word4 = uint & ((BigInt(1) << BigInt(64)) - BigInt(1));
  const word3 = (uint & ((BigInt(1) << BigInt(128)) - (BigInt(1) << BigInt(64)))) >> BigInt(64);
  const word2 = (uint & ((BigInt(1) << BigInt(192)) - (BigInt(1) << BigInt(128)))) >> BigInt(128);
  const word1 = uint >> BigInt(192);
  return [word1, word2, word3, word4];
}

/**
 * Computes the Pedersen hash of a execution payload for StarkNet
 * This can be used to produce the input for calling the commit method in the StarkNet Commit contract.
 * @param target the target address of the execution.
 * @param selector the selector for the method at address target one wants to execute.
 * @param calldata the payload for the method at address target one wants to execute.
 * @returns A Pedersen hash of the data as a Big Int.
 */
export function getCommit(target: bigint, function_selector: bigint, calldata: bigint[]): bigint {
  const targetBigNum = toBN('0x' + target.toString(16));
  const function_selectorBigNum = toBN('0x' + function_selector.toString(16));
  const calldataBigNum = calldata.map((x) => toBN('0x' + x.toString(16)));
  return BigInt(computeHashOnElements([targetBigNum, function_selectorBigNum, ...calldataBigNum]));
}

/**
 * Utility function that returns an example executionHash and `txHashes`, given a verifying contract.
 * @param _verifyingContract The verifying l1 contract
 * @param tx1 Transaction object
 * @param tx2 Transaction object
 * @returns
 */
export function createExecutionHash(
  _verifyingContract: string,
  tx1: any,
  tx2: any
): {
  executionHash: SplitUint256;
  txHashes: Array<string>;
} {
  const domain = {
    chainId: ethers.BigNumber.from(1), //TODO: should be network.config.chainId but it's not working
    verifyingContract: _verifyingContract,
  };

  // 2 transactions in proposal
  const txHash1 = _TypedDataEncoder.hash(domain, EIP712_TYPES, tx1);
  const txHash2 = _TypedDataEncoder.hash(domain, EIP712_TYPES, tx2);

  const abiCoder = new ethers.utils.AbiCoder();
  const hash = BigInt(ethers.utils.keccak256(abiCoder.encode(['bytes32[]'], [[txHash1, txHash2]])));

  const executionHash = SplitUint256.fromUint(hash);
  return {
    executionHash,
    txHashes: [txHash1, txHash2],
  };
}
