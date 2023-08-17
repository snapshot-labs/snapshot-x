use clone::Clone;
use serde::Serde;
use starknet::ContractAddress;
use sx::types::{FinalizationStatus, UserAddress};

#[derive(Clone, Drop, Serde, PartialEq, starknet::Store)]
struct Proposal {
    start_timestamp: u32,
    min_end_timestamp: u32,
    max_end_timestamp: u32,
    execution_payload_hash: felt252,
    execution_strategy: ContractAddress,
    author: UserAddress,
    finalization_status: FinalizationStatus,
    active_voting_strategies: u256
}
