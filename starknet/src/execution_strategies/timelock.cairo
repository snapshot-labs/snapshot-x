use starknet::ContractAddress;
use sx::types::{Proposal, ProposalStatus};

#[starknet::interface]
trait ITimelockExecutionStrategy<TContractState> {
    fn execute_queued_proposal(ref self: TContractState, payload: Span<felt252>);

    fn veto(ref self: TContractState, execution_payload_hash: felt252);

    fn set_veto_guardian(ref self: TContractState, new_veto_guardian: ContractAddress);

    fn veto_guardian(self: @TContractState) -> ContractAddress;

    fn set_timelock_delay(ref self: TContractState, new_timelock_delay: u32);

    fn timelock_delay(self: @TContractState) -> u32;

    fn enable_space(ref self: TContractState, space: ContractAddress);

    fn disable_space(ref self: TContractState, space: ContractAddress);

    fn is_space_enabled(self: @TContractState, space: ContractAddress) -> bool;
}

#[starknet::contract]
mod TimelockExecutionStrategy {
    use core::zeroable::Zeroable;
    use starknet::{ContractAddress, info, syscalls};
    use openzeppelin::access::ownable::OwnableComponent;
    use sx::interfaces::IExecutionStrategy;
    use super::ITimelockExecutionStrategy;
    use sx::types::{Proposal, ProposalStatus};
    use sx::utils::{simple_quorum::SimpleQuorumComponent, space_manager::SpaceManagerComponent};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    component!(path: SimpleQuorumComponent, storage: simple_quorum, event: SimpleQuorumEvent);

    #[abi(embed_v0)]
    impl SimpleQuorumImpl = SimpleQuorumComponent::SimpleQuorumImpl<ContractState>;
    impl SimpleQuorumInternalImpl = SimpleQuorumComponent::InternalImpl<ContractState>;

    component!(path: SpaceManagerComponent, storage: space_manager, event: SpaceManagerEvent);
    impl SpaceManagerInternalImpl = SpaceManagerComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        _timelock_delay: u32,
        _veto_guardian: ContractAddress,
        _proposal_execution_time: LegacyMap::<felt252, u32>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        simple_quorum: SimpleQuorumComponent::Storage,
        #[substorage(v0)]
        space_manager: SpaceManagerComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TimelockExecutionStrategySetUp: TimelockExecutionStrategySetUp,
        TimelockDelaySet: TimelockDelaySet,
        VetoGuardianSet: VetoGuardianSet,
        CallQueued: CallQueued,
        ProposalQueued: ProposalQueued,
        CallExecuted: CallExecuted,
        ProposalExecuted: ProposalExecuted,
        ProposalVetoed: ProposalVetoed,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        SimpleQuorumEvent: SimpleQuorumComponent::Event,
        #[flat]
        SpaceManagerEvent: SpaceManagerComponent::Event,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct TimelockExecutionStrategySetUp {
        owner: ContractAddress,
        veto_guardian: ContractAddress,
        timelock_delay: u32,
        quorum: u256
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct TimelockDelaySet {
        new_timelock_delay: u32
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct VetoGuardianSet {
        new_veto_guardian: ContractAddress
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct CallQueued {
        call: CallWithSalt,
        execution_time: u32
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProposalQueued {
        execution_payload_hash: felt252,
        execution_time: u32
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct CallExecuted {
        call: CallWithSalt
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProposalExecuted {
        execution_payload_hash: felt252
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProposalVetoed {
        execution_payload_hash: felt252
    }

    #[derive(Drop, PartialEq, Serde)]
    struct CallWithSalt {
        to: ContractAddress,
        selector: felt252,
        calldata: Array<felt252>,
        salt: felt252
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        veto_guardian: ContractAddress,
        spaces: Span<ContractAddress>,
        timelock_delay: u32,
        quorum: u256
    ) {
        self.ownable.initializer(owner);

        self.simple_quorum.initializer(quorum);

        self.space_manager.initializer(spaces);

        self._timelock_delay.write(timelock_delay);
        self._veto_guardian.write(veto_guardian);
    }

    #[abi(embed_v0)]
    impl ExecutionStrategy of IExecutionStrategy<ContractState> {
        fn execute(
            ref self: ContractState,
            proposal_id: u256,
            proposal: Proposal,
            votes: Array<u256>,
            payload: Array<felt252>
        ) {
            self.space_manager.assert_only_spaces();

            assert(votes.len() == 3, 'Invalid votes array length');
            let votes_against = *votes[0];
            let votes_for = *votes[1];
            let votes_abstain = *votes[2];
            let proposal_status = self
                .simple_quorum
                .get_proposal_status(@proposal, votes_for, votes_against, votes_abstain);

            assert(
                proposal_status == ProposalStatus::Accepted(())
                    || proposal_status == ProposalStatus::VotingPeriodAccepted(()),
                'Invalid Proposal Status'
            );

            assert(
                self._proposal_execution_time.read(proposal.execution_payload_hash).is_zero(),
                'Duplicate Hash'
            );

            let execution_time = info::get_block_timestamp().try_into().unwrap()
                + self._timelock_delay.read();
            self._proposal_execution_time.write(proposal.execution_payload_hash, execution_time);

            let mut payload = payload.span();
            let mut calls = Serde::<Array<CallWithSalt>>::deserialize(ref payload).unwrap();

            loop {
                match calls.pop_front() {
                    Option::Some(call) => {
                        self
                            .emit(
                                Event::CallQueued(
                                    CallQueued { call: call, execution_time: execution_time }
                                )
                            );
                    },
                    Option::None(()) => { break; }
                };
            }
        }

        fn get_proposal_status(
            self: @ContractState, proposal: Proposal, votes: Array<u256>
        ) -> ProposalStatus {
            assert(votes.len() == 3, 'Invalid votes array length');
            let votes_against = *votes[0];
            let votes_for = *votes[1];
            let votes_abstain = *votes[2];
            self
                .simple_quorum
                .get_proposal_status(@proposal, votes_for, votes_against, votes_abstain)
        }

        fn get_strategy_type(self: @ContractState) -> felt252 {
            'SimpleQuorumTimelock'
        }
    }

    #[abi(embed_v0)]
    impl TimelockExecutionStrategy of ITimelockExecutionStrategy<ContractState> {
        fn execute_queued_proposal(ref self: ContractState, mut payload: Span<felt252>) {
            let execution_payload_hash = poseidon::poseidon_hash_span(payload);
            let execution_time = self._proposal_execution_time.read(execution_payload_hash);
            assert(execution_time.is_non_zero(), 'Proposal Not Queued');
            assert(
                info::get_block_timestamp().try_into().unwrap() >= execution_time, 'Delay Not Met'
            );

            // Reset the execution time to 0 to prevent reentrancy.
            self._proposal_execution_time.write(execution_payload_hash, 0);

            let mut calls = Serde::<Array<CallWithSalt>>::deserialize(ref payload).unwrap();
            loop {
                match calls.pop_front() {
                    Option::Some(call) => {
                        syscalls::call_contract_syscall(
                            call.to, call.selector, call.calldata.span()
                        )
                            .expect('Call Failed');

                        self.emit(Event::CallExecuted(CallExecuted { call: call }));
                    },
                    Option::None(()) => { break; }
                };
            };

            self
                .emit(
                    Event::ProposalExecuted(
                        ProposalExecuted { execution_payload_hash: execution_payload_hash }
                    )
                );
        }

        fn veto(ref self: ContractState, execution_payload_hash: felt252) {
            self.assert_only_veto_guardian();
            assert(
                self._proposal_execution_time.read(execution_payload_hash).is_non_zero(),
                'Proposal Not Queued'
            );
            self._proposal_execution_time.write(execution_payload_hash, 0);
            self
                .emit(
                    Event::ProposalVetoed(
                        ProposalVetoed { execution_payload_hash: execution_payload_hash }
                    )
                );
        }

        fn set_veto_guardian(ref self: ContractState, new_veto_guardian: ContractAddress) {
            self.ownable.assert_only_owner();
            self._veto_guardian.write(new_veto_guardian);

            self
                .emit(
                    Event::VetoGuardianSet(VetoGuardianSet { new_veto_guardian: new_veto_guardian })
                );
        }

        fn veto_guardian(self: @ContractState) -> ContractAddress {
            self._veto_guardian.read()
        }

        fn set_timelock_delay(ref self: ContractState, new_timelock_delay: u32) {
            self.ownable.assert_only_owner();
            self._timelock_delay.write(new_timelock_delay);

            self
                .emit(
                    Event::TimelockDelaySet(
                        TimelockDelaySet { new_timelock_delay: new_timelock_delay }
                    )
                );
        }

        fn timelock_delay(self: @ContractState) -> u32 {
            self._timelock_delay.read()
        }

        fn enable_space(ref self: ContractState, space: ContractAddress) {
            self.ownable.assert_only_owner();
            self.space_manager.enable_space(space);
        }

        fn disable_space(ref self: ContractState, space: ContractAddress) {
            self.ownable.assert_only_owner();
            self.space_manager.disable_space(space);
        }

        fn is_space_enabled(self: @ContractState, space: ContractAddress) -> bool {
            self.space_manager.is_space_enabled(space)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_only_veto_guardian(self: @ContractState) {
            assert(self._veto_guardian.read() == info::get_caller_address(), 'Unauthorized Caller');
        }
    }
}
