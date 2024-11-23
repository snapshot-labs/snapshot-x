/* eslint-disable  @typescript-eslint/no-non-null-assertion */
/* eslint-disable  @typescript-eslint/explicit-module-boundary-types */

import { Contract, BigNumberish, Signer, ethers } from 'ethers';
import { AddressZero } from '@ethersproject/constants';

export const EIP712_TYPES = {
  Transaction: [
    {
      name: 'to',
      type: 'address',
    },
    {
      name: 'value',
      type: 'uint256',
    },
    {
      name: 'data',
      type: 'bytes',
    },
    {
      name: 'operation',
      type: 'uint8',
    },
    {
      name: 'nonce',
      type: 'uint256',
    },
  ],
};

export const EIP_DOMAIN = {
  EIP712Domain: [
    { type: 'uint256', name: 'chainId' },
    { type: 'address', name: 'verifyingContract' },
  ],
};

export const EIP712_SAFE_TX_TYPE = {
  // "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
  SafeTx: [
    { type: 'address', name: 'to' },
    { type: 'uint256', name: 'value' },
    { type: 'bytes', name: 'data' },
    { type: 'uint8', name: 'operation' },
    { type: 'uint256', name: 'safeTxGas' },
    { type: 'uint256', name: 'baseGas' },
    { type: 'uint256', name: 'gasPrice' },
    { type: 'address', name: 'gasToken' },
    { type: 'address', name: 'refundReceiver' },
    { type: 'uint256', name: 'nonce' },
  ],
};

export const EIP712_SAFE_MESSAGE_TYPE = {
  // "SafeMessage(bytes message)"
  SafeMessage: [{ type: 'bytes', name: 'message' }],
};

export interface MetaTransaction {
  to: string;
  value: string | number | bigint;
  data: string;
  operation: number;
}

export interface SafeTransaction extends MetaTransaction {
  safeTxGas: string | number;
  baseGas: string | number;
  gasPrice: string | number;
  gasToken: string;
  refundReceiver: string;
  nonce: string | number;
}

export interface SafeSignature {
  signer: string;
  data: string;
}

const encodeMetaTransaction = (tx: MetaTransaction): string => {
  const data = ethers.getBytes(tx.data);
  const encoded = ethers.solidityPacked(
    ['uint8', 'address', 'uint256', 'uint256', 'bytes'],
    [tx.operation, tx.to, tx.value, data.length, data],
  );
  return encoded.slice(2);
};

export const encodeMultiSend = (txs: MetaTransaction[]): string => {
  return '0x' + txs.map((tx) => encodeMetaTransaction(tx)).join('');
};

export const buildMultiSendSafeTx = async (
  multiSend: Contract,
  txs: MetaTransaction[],
  nonce: number,
  overrides?: Partial<SafeTransaction>,
): Promise<SafeTransaction> => {
  return buildContractCall(multiSend, 'multiSend', [encodeMultiSend(txs)], nonce, true, overrides);
};

export const calculateSafeDomainSeparator = (
  safeAddress: string,
  chainId: BigNumberish,
): string => {
  return ethers.TypedDataEncoder.hashDomain({ verifyingContract: safeAddress, chainId });
};

export const preimageSafeTransactionHash = (
  safeAddress: string,
  safeTx: SafeTransaction,
  chainId: BigNumberish,
): string => {
  return ethers.TypedDataEncoder.encode(
    { verifyingContract: safeAddress, chainId },
    EIP712_SAFE_TX_TYPE,
    safeTx,
  );
};

export const calculateSafeTransactionHash = (
  safeAddress: string,
  safeTx: SafeTransaction,
  chainId: BigNumberish,
): string => {
  return ethers.TypedDataEncoder.hash(
    { verifyingContract: safeAddress, chainId },
    EIP712_SAFE_TX_TYPE,
    safeTx,
  );
};

export const calculateSafeMessageHash = (
  safeAddress: string,
  message: string,
  chainId: BigNumberish,
): string => {
  return ethers.TypedDataEncoder.hash(
    { verifyingContract: safeAddress, chainId },
    EIP712_SAFE_MESSAGE_TYPE,
    {
      message,
    },
  );
};

export const safeApproveHash = async (
  signer: Signer,
  safe: Contract,
  safeTx: SafeTransaction,
  skipOnChainApproval?: boolean,
): Promise<SafeSignature> => {
  if (!skipOnChainApproval) {
    if (!signer.provider) throw Error('Provider required for on-chain approval');
    const chainId = (await signer.provider.getNetwork()).chainId;
    const typedDataHash = ethers.getBytes(
      calculateSafeTransactionHash(await safe.getAddress(), safeTx, chainId),
    );
    const signerSafe = safe.connect(signer);
    await signerSafe.approveHash(typedDataHash);
  }
  const signerAddress = await signer.getAddress();
  return {
    signer: signerAddress,
    data:
      '0x000000000000000000000000' +
      signerAddress.slice(2) +
      '0000000000000000000000000000000000000000000000000000000000000000' +
      '01',
  };
};

export const safeSignTypedData = async (
  signer: Signer,
  safe: Contract,
  safeTx: SafeTransaction,
  chainId?: BigNumberish,
): Promise<SafeSignature> => {
  if (!chainId && !signer.provider) throw Error('Provider required to retrieve chainId');
  const cid = (await signer.provider!.getNetwork()).chainId;
  const signerAddress = await signer.getAddress();
  return {
    signer: signerAddress,
    data: await signer.signTypedData(
      { verifyingContract: await safe.getAddress(), chainId: cid },
      EIP712_SAFE_TX_TYPE,
      safeTx,
    ),
  };
};

export const signHash = async (signer: Signer, hash: string): Promise<SafeSignature> => {
  const typedDataHash = ethers.getBytes(hash);
  const signerAddress = await signer.getAddress();
  return {
    signer: signerAddress,
    data: (await signer.signMessage(typedDataHash)).replace(/1b$/, '1f').replace(/1c$/, '20'),
  };
};

export const safeSignMessage = async (
  signer: Signer,
  safeAddress: string,
  safeTx: SafeTransaction,
  chainId?: BigNumberish,
): Promise<SafeSignature> => {
  const cid = chainId || (await signer.provider!.getNetwork()).chainId;
  return signHash(signer, calculateSafeTransactionHash(safeAddress, safeTx, cid));
};

export const buildSignatureBytes = (signatures: SafeSignature[]): string => {
  signatures.sort((left, right) =>
    left.signer.toLowerCase().localeCompare(right.signer.toLowerCase()),
  );
  let signatureBytes = '0x';
  for (const sig of signatures) {
    signatureBytes += sig.data.slice(2);
  }
  return signatureBytes;
};

export const logGas = async (message: string, tx: Promise<any>, skip?: boolean): Promise<any> => {
  return tx.then(async (result) => {
    const receipt = await result.wait();
    if (!skip) console.log('           Used', receipt.gasUsed.toNumber(), `gas for >${message}<`);
    return result;
  });
};

export const executeTx = async (
  safe: Contract,
  safeTx: SafeTransaction,
  signatures: SafeSignature[],
  overrides?: any,
): Promise<any> => {
  const signatureBytes = buildSignatureBytes(signatures);
  return safe.execTransaction(
    safeTx.to,
    safeTx.value,
    safeTx.data,
    safeTx.operation,
    safeTx.safeTxGas,
    safeTx.baseGas,
    safeTx.gasPrice,
    safeTx.gasToken,
    safeTx.refundReceiver,
    signatureBytes,
    overrides || {},
  );
};

export const populateExecuteTx = async (
  safe: Contract,
  safeTx: SafeTransaction,
  signatures: SafeSignature[],
  overrides?: any,
): Promise<ethers.ContractTransaction> => {
  const signatureBytes = buildSignatureBytes(signatures);
  return safe.execTransaction.populateTransaction(
    safeTx.to,
    safeTx.value,
    safeTx.data,
    safeTx.operation,
    safeTx.safeTxGas,
    safeTx.baseGas,
    safeTx.gasPrice,
    safeTx.gasToken,
    safeTx.refundReceiver,
    signatureBytes,
    overrides || {},
  );
};

export const buildContractCall = async (
  contract: Contract,
  method: string,
  params: any[],
  nonce: number,
  delegateCall?: boolean,
  overrides?: Partial<SafeTransaction>,
): Promise<SafeTransaction> => {
  const data = contract.interface.encodeFunctionData(method, params);
  return buildSafeTransaction(
    Object.assign(
      {
        to: await contract.getAddress(),
        data,
        operation: delegateCall ? 1 : 0,
        nonce,
      },
      overrides,
    ),
  );
};

export const buildContractCallVariable = (
  contract: Contract,
  address: string,
  method: string,
  params: any[],
  nonce: number,
  delegateCall?: boolean,
  overrides?: Partial<SafeTransaction>,
): SafeTransaction => {
  const data = contract.interface.encodeFunctionData(method, params);
  return buildSafeTransaction(
    Object.assign(
      {
        to: address,
        data,
        operation: delegateCall ? 1 : 0,
        nonce,
      },
      overrides,
    ),
  );
};

export const executeTxWithSigners = async (
  safe: Contract,
  tx: SafeTransaction,
  signers: Signer[],
  overrides?: any,
) => {
  const sigs = await Promise.all(signers.map((signer) => safeSignTypedData(signer, safe, tx)));
  return executeTx(safe, tx, sigs, overrides);
};

export const executeContractCallWithSigners = async (
  safe: Contract,
  contract: Contract,
  method: string,
  params: any[],
  signers: Signer[],
  delegateCall?: boolean,
  overrides?: Partial<SafeTransaction>,
) => {
  const tx = await buildContractCall(
    contract,
    method,
    params,
    await safe.nonce(),
    delegateCall,
    overrides,
  );
  return executeTxWithSigners(safe, tx, signers);
};

export const buildSafeTransaction = (template: {
  to: string;
  value?: bigint | number | string;
  data?: string;
  operation?: number;
  safeTxGas?: number | string;
  baseGas?: number | string;
  gasPrice?: number | string;
  gasToken?: string;
  refundReceiver?: string;
  nonce: number;
}): SafeTransaction => {
  return {
    to: template.to,
    value: template.value || 0,
    data: template.data || '0x',
    operation: template.operation || 0,
    safeTxGas: template.safeTxGas || 0,
    baseGas: template.baseGas || 0,
    gasPrice: template.gasPrice || 0,
    gasToken: template.gasToken || AddressZero,
    refundReceiver: template.refundReceiver || AddressZero,
    nonce: template.nonce,
  };
};
