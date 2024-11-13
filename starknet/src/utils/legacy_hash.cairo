use hash::LegacyHash;
use starknet::EthAddress;
use sx::types::{UserAddress};

impl LegacyHashEthAddress of LegacyHash<EthAddress> {
    fn hash(state: felt252, value: EthAddress) -> felt252 {
        LegacyHash::<felt252>::hash(state, value.into())
    }
}

impl LegacyHashSpanFelt252 of LegacyHash<Span<felt252>> {
    fn hash(state: felt252, mut value: Span<felt252>) -> felt252 {
        let len = value.len();
        let mut call_data_state: felt252 = 0;
        loop {
            match value.pop_front() {
                Option::Some(item) => {
                    call_data_state = LegacyHash::hash(call_data_state, *item);
                },
                Option::None(_) => { break LegacyHash::hash(call_data_state, len); },
            };
        }
    }
}

impl LegacyHashUserAddress of LegacyHash<UserAddress> {
    fn hash(state: felt252, value: UserAddress) -> felt252 {
        match value {
            UserAddress::Starknet(address) => LegacyHash::<felt252>::hash(state, address.into()),
            UserAddress::Ethereum(address) => LegacyHash::<felt252>::hash(state, address.into()),
            UserAddress::Custom(address) => LegacyHash::<u256>::hash(state, address),
        }
    }
}

impl LegacyHashVoteRegistry of LegacyHash<(u256, UserAddress)> {
    fn hash(state: felt252, value: (u256, UserAddress)) -> felt252 {
        let (proposal_id, user) = value;
        let state = LegacyHash::hash(state, proposal_id);
        LegacyHash::hash(state, user)
    }
}

