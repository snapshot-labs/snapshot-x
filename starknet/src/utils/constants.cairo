const INITIALIZE_SELECTOR: felt252 =
    0x79dc0da7c54b95f10aa182ad0a46400db63156920adb65eca2654c0945a463;
const UPGRADE_SELECTOR: felt252 = 0xf2f7c15cbe06c8d94597cd91fd7f3369eae842359235712def5584f8d270cd;
const POST_UPGRADE_INITIALIZER_SELECTOR: felt252 =
    0x394c078a9c6f355ad9fc59c3fa40825dfd9db2a41802a486f1492c16d2739e6;
const PROPOSE_SELECTOR: felt252 = 0x1bfd596ae442867ef71ca523061610682af8b00fc2738329422f4ad8d220b81;
const VOTE_SELECTOR: felt252 = 0x132bdf85fc8aa10ac3c22f02317f8f53d4b4f52235ed1eabb3a4cbbe08b5c41;
const UPDATE_PROPOSAL_SELECTOR: felt252 =
    0x1f93122f646d968b0ce8c1a4986533f8b4ed3f099122381a4f77478a480c2c3;

// ------ Ethereum Signature Constants ------

const ETHEREUM_PREFIX: u128 = 0x1901;

// keccak256(abi.encode(keccak256("EIP712Domain()"))
const DOMAIN_HASH_HIGH: u128 = 0x6192106f129ce05c9075d319c1fa6ea9;
const DOMAIN_HASH_LOW: u128 = 0xb3ae37cbd0c1ef92e2be7137bb07baa1;

// keccak256(
//    "Propose(uint256 chainId,uint256 authenticator,uint256 space,address author,uint256[] metadataUri,Strategy executionStrategy,uint256[] userProposalValidationParams,uint256 salt)Strategy(uint256 address,uint256[] params)"
//         )
const PROPOSE_TYPEHASH_HIGH: u128 = 0x04ede461dac4a3b480afeb3954345a3e;
const PROPOSE_TYPEHASH_LOW: u128 = 0x86377d7136dad5401c9e3ff24c7a0f07;

// keccak256(
//    "Vote(uint256 chainId,uint256 authenticator,uint256 space,address voter,uint256 proposalId,uint256 choice,IndexedStrategy[] userVotingStrategies,uint256[] metadataUri)IndexedStrategy(uint256 index,uint256[] params)"
//         )
const VOTE_TYPEHASH_HIGH: u128 = 0x9f141e8a6807fa0c11618a1232b75ba3;
const VOTE_TYPEHASH_LOW: u128 = 0x298f2993575d81a3b6ec2d52ae694cb7;

// keccak256(
//    "UpdateProposal(uint256 chainId,uint256 authenticator,uint256 space,address author,uint256 proposalId,Strategy executionStrategy,uint256[] metadataUri,uint256 salt)Strategy(uint256 address,uint256[] params)"
//         )
const UPDATE_PROPOSAL_TYPEHASH_HIGH: u128 = 0x2df41899fffb50338812b0c6bb5db608;
const UPDATE_PROPOSAL_TYPEHASH_LOW: u128 = 0x9503bccdcdb9a1ed596eea5bb5087f84;

// keccak256(
//     "SessionKeyAuth(uint256 chainId,uint256 authenticator,address owner,uint256 sessionPublicKey,uint256 sessionDuration,uint256 salt)"
//         )
const SESSION_KEY_AUTH_TYPEHASH_HIGH: u128 = 0xbf6f5331c3a2c744889ff780cad3d0f2;
const SESSION_KEY_AUTH_TYPEHASH_LOW: u128 = 0x550df4038acab427712b5b0b38e43c3d;

// keccak256(
//     "SessionKeyRevoke(uint256 chainId,uint256 authenticator,address owner,uint256 sessionPublicKey,uint256 salt)"
//         )
const SESSION_KEY_REVOKE_TYPEHASH_HIGH: u128 = 0xf607352669f95230a0602015a636355d;
const SESSION_KEY_REVOKE_TYPEHASH_LOW: u128 = 0x1ef75bc12feec22425baac28de317513;

// keccak256("Strategy(uint256 address,uint256[] params)")
const STRATEGY_TYPEHASH_HIGH: u128 = 0xa6cb034787a88e7219605b9db792cb9a;
const STRATEGY_TYPEHASH_LOW: u128 = 0x312314462975078b4bdad10feee486d9;

// keccak256("IndexedStrategy(uint256 index,uint256[] params)")
const INDEXED_STRATEGY_TYPEHASH_HIGH: u128 = 0xf4acb5967e70f3ad896d52230fe743c9;
const INDEXED_STRATEGY_TYPEHASH_LOW: u128 = 0x1d011b57ff63174d8f2b064ab6ce9cc6;

// ------ Stark Signature Constants ------

const STARKNET_MESSAGE: felt252 = 'StarkNet Message';

// StarknetKeccak('StarkNetDomain(name:felt252,version:felt252,chainId:felt252,verifyingContract:ContractAddress)')
const DOMAIN_TYPEHASH: felt252 = 0xa9974a36dee531bbc36aad5eeab4ade4df5ad388a296bb14d28ad4e9bf2164;

// H('Propose(space:ContractAddress,author:ContractAddress,metadataUri:felt*,executionStrategy:Strategy,
//    userProposalValidationParams:felt*,salt:felt252)Strategy(address:felt252,params:felt*)')
const PROPOSE_TYPEHASH: felt252 = 0x22175ade273c5b12630bfc15eca8c6a8eb7e2648ac63d2b9882c535f92d71b9;

// H('Vote(space:ContractAddress,voter:ContractAddress,proposalId:u256,choice:felt252,userVotingStrategies:IndexedStrategy*,
//    metadataUri:felt*)IndexedStrategy(index:felt252,params:felt*)u256(low:felt252,high:felt252)')
const VOTE_TYPEHASH: felt252 = 0x1d9763f87aaaeb271287d4b9c84053d3f201ad61efc2c32a0abfb8cd42347bf;

// H('UpdateProposal(space:ContractAddress,author:ContractAddress,proposalId:u256,executionStrategy:Strategy,
//    metadataUri:felt*,salt:felt252)Strategy(address:felt252,params:felt*)u256(low:felt252,high:felt252)')
const UPDATE_PROPOSAL_TYPEHASH: felt252 =
    0x34f1b3fe98891caddfc18d9b8d3bee36be34145a6e9f7a7bb76a45038dda780;

// H('SessionKeyAuth(owner:felt252,sessionPublicKey:felt252,sessionDuration:felt252,salt:felt252)')
const SESSION_KEY_AUTH_TYPEHASH: felt252 =
    0x3AE06AD61C8456C0833FD6862CD5D5F3CE96C8B9EB80B4B7FB2D0FF15C840F6;

// H('SessionKeyRevoke(owner:felt252,sessionPublicKey:felt252,salt:felt252)')
const SESSION_KEY_REVOKE_TYPEHASH: felt252 =
    0x11FA5E8349D04FAA798D9F772F97D151A10FAF60B5CC9022CECA1D0A6BB06A;

// StarknetKeccak('Strategy(address:felt252,params:felt*)')
const STRATEGY_TYPEHASH: felt252 =
    0x39154ec0efadcd0deffdfc2044cf45dd986d260e59c26d69564b50a18f40f6b;

// StarknetKeccak('IndexedStrategy(index:felt252,params:felt*)')
const INDEXED_STRATEGY_TYPEHASH: felt252 =
    0x1f464f3e668281a899c5f3fc74a009ccd1df05fd0b9331b0460dc3f8054f64c;

// StarknetKeccak('u256(low:felt252,high:felt252)')
const U256_TYPEHASH: felt252 = 0x1094260a770342332e6a73e9256b901d484a438925316205b4b6ff25df4a97a;

// ------ ERC165 Interface Ids ------
// For more information, refer to: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-5.md

const ERC165_ACCOUNT_INTERFACE_ID: felt252 =
    0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd; // SNIP-6 compliant account ID, functions are snake case


// ------ Pseudo selectors for Tx based Session key authentication ------
const REGISTER_SESSION_WITH_OWNER_TX_SELECTOR: felt252 = 'register_session';

const REVOKE_SESSION_WITH_OWNER_TX_SELECTOR: felt252 = 'revoke_session';
