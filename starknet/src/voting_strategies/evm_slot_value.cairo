#[starknet::contract]
mod EvmSlotValueVotingStrategy {
    use starknet::{EthAddress, ContractAddress};
    use sx::types::{UserAddress, UserAddressTrait};
    use sx::interfaces::IVotingStrategy;
    use sx::utils::{SingleSlotProof, TIntoU256};

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl EvmSlotValueVotingStrategy of IVotingStrategy<ContractState> {
        /// Returns the EVM slot value of contract `C` at slot index `I`, using `voter` as the mapping key.
        /// The contract address and slot index is stored in the strategy parameters (defined by the space owner).
        /// The proof itself is supplied by the voter, in the `user_params` argument.
        ///
        /// # Notes
        ///
        /// This is most often used for proving a user balance on a different chain, such as a ERC20 token balance on L1.
        ///
        /// # Arguments
        ///
        /// * `timestamp` - The timestamp of the block at which the voting power is calculated.
        /// * `voter` - The address of the voter. Expected to be an ethereum address.
        /// * `params` - Should contain the contract address and the slot index.
        /// * `user_params` - Should contain the encoded proofs for the L1 contract and the slot index.
        ///
        /// # Returns
        ///
        /// `u256` - The slot value of the voter at the given timestamp.
        fn get_voting_power(
            self: @ContractState,
            timestamp: u32,
            voter: UserAddress,
            params: Span<felt252>, // [contract_address: address, slot_index: u32]
            user_params: Span<felt252>, // encoded proofs
        ) -> u256 {
            // Cast voter address to an Ethereum address
            // Will revert if the address is not a valid Ethereum address
            let voter = voter.to_ethereum_address();

            // Decode params 
            let mut params = params;
            let (evm_contract_address, slot_index) = Serde::<(
                EthAddress, u256
            )>::deserialize(ref params)
                .unwrap();

            // Get the balance of the voter at the given block timestamp
            // Migration to components planned ; disregard the `unsafe` keyword,
            // it is actually safe.
            let state = SingleSlotProof::unsafe_new_contract_state();
            let balance = SingleSlotProof::InternalImpl::get_storage_slot(
                @state, timestamp, evm_contract_address, slot_index, voter.into(), user_params
            );
            balance
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        timestamp_remappers: ContractAddress,
        facts_registry: ContractAddress
    ) {
        // Migration to components planned ; disregard the `unsafe` keyword,
        // it is actually safe.
        let mut state = SingleSlotProof::unsafe_new_contract_state();
        SingleSlotProof::InternalImpl::initializer(ref state, timestamp_remappers, facts_registry);
    }
}
