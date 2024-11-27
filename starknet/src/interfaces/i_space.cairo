use starknet::{ClassHash, ContractAddress, SyscallResult};
use sx::types::{
    UserAddress, Strategy, Proposal, IndexedStrategy, UpdateSettingsCalldata, ProposalStatus
};

#[starknet::interface]
trait ISpace<TContractState> {
    // -- View functions --

    /// The voting delay in seconds between when a proposal is created and the start of the voting period.
    fn voting_delay(self: @TContractState) -> u32;

    /// @notice The minimum duration of the voting period.
    fn min_voting_duration(self: @TContractState) -> u32;

    /// Returns the maximum voting duration. Once this duration has elapsed, no additional votes can be cast.
    fn max_voting_duration(self: @TContractState) -> u32;

    /// Returns the DAO URI. See https://ethereum-magicians.org/t/erc-4824-decentralized-autonomous-organizations/8362
    fn dao_uri(self: @TContractState) -> Array<felt252>;

    /// The next proposal id. Starts at 1.
    fn next_proposal_id(self: @TContractState) -> u256;

    /// The allow list of authenticators. Only allowed authenticators can interact with the `propose`,
    /// `udpate_proposal` and `vote` functions.
    fn authenticators(self: @TContractState, account: ContractAddress) -> bool;

    /// An array of allowed voting strategies. Voting strategies are used to determine the voting power of a voter.
    fn voting_strategies(self: @TContractState, index: u8) -> Strategy;

    /// The current active voting strategies. Each bit represents whether the proposal is active or not.
    /// These are stored at the proposal level when a proposal is created, meaning when a new voting strategy is added or removed
    /// it only affects subsequent proposals, not ongoing ones.
    fn active_voting_strategies(self: @TContractState) -> u256;

    /// The index of the next available voting strategy. Starts at 0.
    fn next_voting_strategy_index(self: @TContractState) -> u8;

    /// The proposal validation strategy. This strategy is used to determine whether a user can create a new proposal or not.
    fn proposal_validation_strategy(self: @TContractState) -> Strategy;

    /// Returns the current voting power for a given choice and a given proposal id.
    fn vote_power(self: @TContractState, proposal_id: u256, choice: u128) -> u256;

    /// Returns whether a given user has voted on a given proposal.
    fn vote_registry(self: @TContractState, proposal_id: u256, voter: UserAddress) -> bool;

    /// Returns the proposal struct corresponding to `proposal_id`.
    fn proposals(self: @TContractState, proposal_id: u256) -> Proposal;

    /// Returns the status of a given proposal.
    fn get_proposal_status(self: @TContractState, proposal_id: u256) -> ProposalStatus;

    // -- Owner Actions --
    /// All-in-one update settings function. Rather than updating the settings individually, a
    /// struct is passed to be able to update different settings in a single call. Settings that should not
    /// be updated should have the `no_update` value (see `UpdateSettingsCalldata`).
    fn update_settings(ref self: TContractState, input: UpdateSettingsCalldata);

    // -- Actions --
    /// Initializes the contract. Can only be called once.
    fn initialize(
        ref self: TContractState,
        owner: ContractAddress,
        min_voting_duration: u32,
        max_voting_duration: u32,
        voting_delay: u32,
        proposal_validation_strategy: Strategy,
        proposal_validation_strategy_metadata_uri: Array<felt252>,
        voting_strategies: Array<Strategy>,
        voting_strategy_metadata_uris: Array<Array<felt252>>,
        authenticators: Array<ContractAddress>,
        metadata_uri: Array<felt252>,
        dao_uri: Array<felt252>,
    );
    /// Creates a new proposal. Users must go through an authenticator before calling this function.
    ///
    /// # Arguments
    ///
    /// * `author` - The author of the proposal.
    /// * `metadata_uri` - The metadata URI of the proposal. Could be a link to a discussion page, etc.
    /// * `execution_strategy` - The execution strategy for the proposal, consisting of a
    ///                          strategy address and an execution payload.
    /// * `user_proposal_validation_params` - The user proposal validation params. These are the params that will be
    ///                                      passed to the proposal validation strategy.
    fn propose(
        ref self: TContractState,
        author: UserAddress,
        choices: u128,
        metadata_uri: Array<felt252>,
        execution_strategy: Strategy,
        user_proposal_validation_params: Array<felt252>,
    );

    /// Casts a vote on a given proposal. Users must go through an authenticator before calling this function.
    ///
    /// # Arguments
    ///
    /// * `voter` - The voter.
    /// * `proposal_id` - The proposal id to vote on.
    /// * `choice` - The choice to vote for.
    /// * `user_voting_strategies` - The strategies to use to compute the voter's voting power, each consisting of a
    ///                                 strategy index and an array of user provided parameters.
    /// * `metadata_uri` - The metadata URI of the vote.
    fn vote(
        ref self: TContractState,
        voter: UserAddress,
        proposal_id: u256,
        choice: u128,
        user_voting_strategies: Array<IndexedStrategy>,
        metadata_uri: Array<felt252>,
    );

    /// Executes a proposal. Callable by anyone as long as the proposal is accepted.
    fn execute(ref self: TContractState, proposal_id: u256, execution_payload: Array<felt252>);

    /// Updates the proposal. Must be done before the voting period starts. Users need to go through an 
    /// authenticator to interact with this function. The author must be the same as the proposal author.
    ///
    /// # Arguments
    ///
    /// * `author` - The author of the proposal.
    /// * `proposal_id` - The proposal id.
    /// * `execution_strategy` - The new execution strategy that replaces the old one.
    /// * `metadata_uri` - The new metadata URI that replaces the old one.
    fn update_proposal(
        ref self: TContractState,
        author: UserAddress,
        proposal_id: u256,
        choices: u128,
        execution_strategy: Strategy,
        metadata_uri: Array<felt252>,
    );

    /// Cancels a proposal. Callable by the owner of the contract. The proposal must not have been finalized.
    fn cancel(ref self: TContractState, proposal_id: u256);

    /// Upgrades the contract to a new version and calls the `initialize` function on the new contract.
    /// Callable by the owner of the contract.
    ///
    /// # Arguments
    ///
    /// * `class_hash` - The class hash of the new contract.
    /// * `initialize_calldata` - The calldata to pass to the `initialize` function of the new contract.
    fn upgrade(
        ref self: TContractState, class_hash: ClassHash, initialize_calldata: Array<felt252>
    ) -> SyscallResult<()>;

    /// Initializes the contract after an upgrade. This is different from the `initialize` function
    /// in that it is called after the upgrade, which means the contract already has a state and storage
    /// associated to it. 
    ///
    /// # Note
    ///
    /// Should have a lock mechanism to ensure it is only called once!
    ///
    /// # Arguments
    ///
    /// * `initialize_calldata` - The calldata to use to perform a post-upgrade initialization.
    fn post_upgrade_initializer(ref self: TContractState, initialize_calldata: Array<felt252>,);
}
