export const domainTypes = {
  StarkNetDomain: [
    { name: 'name', type: 'felt252' },
    { name: 'version', type: 'felt252' },
    { name: 'chainId', type: 'felt252' },
    { name: 'verifyingContract', type: 'ContractAddress' },
  ],
};

export const sharedTypes = {
  Strategy: [
    { name: 'address', type: 'felt252' },
    { name: 'params', type: 'felt*' },
  ],
  IndexedStrategy: [
    { name: 'index', type: 'felt252' },
    { name: 'params', type: 'felt*' },
  ],
  u256: [
    { name: 'low', type: 'felt252' },
    { name: 'high', type: 'felt252' },
  ],
};

export const proposeTypes = {
  StarkNetDomain: domainTypes.StarkNetDomain,
  Propose: [
    { name: 'space', type: 'ContractAddress' },
    { name: 'author', type: 'ContractAddress' },
    { name: 'metadataUri', type: 'felt*' },
    { name: 'executionStrategy', type: 'Strategy' },
    { name: 'userProposalValidationParams', type: 'felt*' },
    { name: 'salt', type: 'felt252' },
  ],
  Strategy: sharedTypes.Strategy,
};

export const voteTypes = {
  StarkNetDomain: domainTypes.StarkNetDomain,
  Vote: [
    { name: 'space', type: 'ContractAddress' },
    { name: 'voter', type: 'ContractAddress' },
    { name: 'proposalId', type: 'u256' },
    { name: 'choice', type: 'felt252' },
    { name: 'userVotingStrategies', type: 'IndexedStrategy*' },
    { name: 'metadataUri', type: 'felt*' },
  ],
  IndexedStrategy: sharedTypes.IndexedStrategy,
  u256: sharedTypes.u256,
};

export const updateProposalTypes = {
  StarkNetDomain: domainTypes.StarkNetDomain,
  UpdateProposal: [
    { name: 'space', type: 'ContractAddress' },
    { name: 'author', type: 'ContractAddress' },
    { name: 'proposalId', type: 'u256' },
    { name: 'executionStrategy', type: 'Strategy' },
    { name: 'metadataUri', type: 'felt*' },
    { name: 'salt', type: 'felt252' },
  ],
  Strategy: sharedTypes.Strategy,
  u256: sharedTypes.u256,
};

export const sessionKeyRevokeTypes = {
  StarkNetDomain: domainTypes.StarkNetDomain,
  SessionKeyRevoke: [
    { name: 'owner', type: 'felt252' },
    { name: 'sessionPublicKey', type: 'felt252' },
    { name: 'salt', type: 'felt252' },
  ],
};

export const sessionKeyAuthTypes = {
  StarkNetDomain: domainTypes.StarkNetDomain,
  SessionKeyAuth: [
    { name: 'owner', type: 'felt252' },
    { name: 'sessionPublicKey', type: 'felt252' },
    { name: 'sessionDuration', type: 'felt252' },
    { name: 'salt', type: 'felt252' },
  ],
};

export interface Strategy {
  address: string;
  params: string[];
}

export interface IndexedStrategy {
  index: string;
  params: string[];
}

export interface u256 {
  low: string;
  high: string;
}

export interface Propose {
  space: string;
  author: string;
  metadataUri: string[];
  executionStrategy: Strategy;
  userProposalValidationParams: string[];
  salt: string;
}

export interface Vote {
  space: string;
  voter: string;
  proposalId: u256;
  choice: string;
  userVotingStrategies: IndexedStrategy[];
  metadataUri: string[];
}

export interface UpdateProposal {
  space: string;
  author: string;
  proposalId: u256;
  executionStrategy: Strategy;
  metadataUri: string[];
  salt: string;
}

export interface SessionKeyAuth {
  owner: string;
  sessionPublicKey: string;
  sessionDuration: string;
  salt: string;
}

export interface SessionKeyRevoke {
  owner: string;
  sessionPublicKey: string;
  salt: string;
}

export interface StarknetSigProposeCalldata extends Propose {
  signature: string[];
  accountType: string;
}

export interface StarknetSigVoteCalldata extends Vote {
  signature: string[];
  accountType: string;
}

export interface StarknetSigUpdateProposalCalldata extends UpdateProposal {
  signature: string[];
  accountType: string;
}
