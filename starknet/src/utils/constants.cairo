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
//    "Propose(uint256 chainId,uint256 authenticator,uint256 space,address author,uint128 choices,uint256[] metadataUri,Strategy executionStrategy,uint256[] userProposalValidationParams,uint256 salt)Strategy(uint256 address,uint256[] params)"
//         )
const PROPOSE_TYPEHASH_HIGH: u128 = 0xcfa442a702307331eaf2d45aa6c8da70;
const PROPOSE_TYPEHASH_LOW: u128 = 0xa0113ec543fb427277f972cfecb6a19a;

// keccak256(
//    "Vote(uint256 chainId,uint256 authenticator,uint256 space,address voter,uint256 proposalId,uint128 choice,IndexedStrategy[] userVotingStrategies,uint256[] metadataUri)IndexedStrategy(uint256 index,uint256[] params)"
//         )
const VOTE_TYPEHASH_HIGH: u128 = 0x90609fdc19f6de4fcd7d09504bbdd134;
const VOTE_TYPEHASH_LOW: u128 = 0x142ed1654dd447dbef520e793e53b5ec;

// keccak256(
//    "UpdateProposal(uint256 chainId,uint256 authenticator,uint256 space,address author,uint256 proposalId,uint128 choice,Strategy executionStrategy,uint256[] metadataUri,uint256 salt)Strategy(uint256 address,uint256[] params)"
//         )
const UPDATE_PROPOSAL_TYPEHASH_HIGH: u128 = 0xea05b63d628d1f86ef923f9c79ebdc82;
const UPDATE_PROPOSAL_TYPEHASH_LOW: u128 = 0x8920f878d19015413323acc61a52afb3;

// keccak256("Strategy(uint256 address,uint256[] params)")
const STRATEGY_TYPEHASH_HIGH: u128 = 0xa6cb034787a88e7219605b9db792cb9a;
const STRATEGY_TYPEHASH_LOW: u128 = 0x312314462975078b4bdad10feee486d9;

// keccak256("IndexedStrategy(uint256 index,uint256[] params)")
const INDEXED_STRATEGY_TYPEHASH_HIGH: u128 = 0xf4acb5967e70f3ad896d52230fe743c9;
const INDEXED_STRATEGY_TYPEHASH_LOW: u128 = 0x1d011b57ff63174d8f2b064ab6ce9cc6;

// ------ Stark Signature Constants ------

const STARKNET_MESSAGE: felt252 = 'StarkNet Message';

// StarknetKeccak('StarkNetDomain(name:felt252,version:felt252,chainId:felt252)')
const DOMAIN_TYPEHASH: felt252 = 0x27652a980b9a4920425c858386f09477bb210dea95169abd576f5ef7c9d5ca2;

// H('Propose(space:ContractAddress,author:ContractAddress,choices:u128,metadataUri:felt*,executionStrategy:Strategy,
//    userProposalValidationParams:felt*,salt:felt252)Strategy(address:felt252,params:felt*)')
const PROPOSE_TYPEHASH: felt252 = 0x3fc8b3b886f4272c1055fdebb44f4046954215a7541edcd47b91e1155139694;

// H('Vote(space:ContractAddress,voter:ContractAddress,proposalId:u256,choice:u128,userVotingStrategies:IndexedStrategy*,
//    metadataUri:felt*)IndexedStrategy(index:felt252,params:felt*)u256(low:felt252,high:felt252)')
const VOTE_TYPEHASH: felt252 = 0xfc1b4a34a5677c923bfd0f4a3cd492ffc366819e8258b84baad19b7f19d5a3;

// H('UpdateProposal(space:ContractAddress,author:ContractAddress,proposalId:u256,choices:u128,executionStrategy:Strategy,
//    metadataUri:felt*,salt:felt252)Strategy(address:felt252,params:felt*)u256(low:felt252,high:felt252)')
const UPDATE_PROPOSAL_TYPEHASH: felt252 =
    0x7d25dd6a9637f321ba1758c07de86814749987de04646d641546764605b09d;

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
