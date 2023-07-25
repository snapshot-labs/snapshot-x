use array::ArrayTrait;
use result::ResultTrait;
use serde::Serde;
use traits::{PartialEq, TryInto, Into};
use hash::LegacyHash;
use option::OptionTrait;
use clone::Clone;
use integer::{U8IntoU128};
use starknet::{
    ContractAddress, contract_address_const, StorageAccess, StorageBaseAddress, SyscallResult,
    storage_write_syscall, storage_read_syscall, storage_address_from_base_and_offset,
    storage_base_address_from_felt252, contract_address::Felt252TryIntoContractAddress,
    syscalls::deploy_syscall, class_hash::Felt252TryIntoClassHash
};
use sx::utils::math::pow;
use array::SpanTrait;

impl Felt252ArrayIntoU256Array of Into<Array<felt252>, Array<u256>> {
    fn into(self: Array<felt252>) -> Array<u256> {
        let mut arr = ArrayTrait::<u256>::new();
        let mut i = 0_usize;
        loop {
            if i >= self.len() {
                break ();
            }
            arr.append((*self.at(i)).into());
            i += 1;
        };
        arr
    }
}

#[derive(Copy, Drop, Serde)]
enum Choice {
    Against: (),
    For: (),
    Abstain: (),
}

#[derive(Copy, Drop, Serde, PartialEq)]
enum FinalizationStatus {
    Pending: (),
    Executed: (),
    Cancelled: (),
}

#[derive(Copy, Drop, Serde, PartialEq)]
enum ProposalStatus {
    VotingDelay: (),
    VotingPeriod: (),
    VotingPeriodAccepted: (),
    Accepted: (),
    Executed: (),
    Rejected: (),
    Cancelled: ()
}

impl ChoiceIntoU8 of Into<Choice, u8> {
    fn into(self: Choice) -> u8 {
        match self {
            Choice::Against(_) => 0_u8,
            Choice::For(_) => 1_u8,
            Choice::Abstain(_) => 2_u8,
        }
    }
}

impl ChoiceIntoU256 of Into<Choice, u256> {
    fn into(self: Choice) -> u256 {
        ChoiceIntoU8::into(self).into()
    }
}

impl U8IntoFinalizationStatus of TryInto<u8, FinalizationStatus> {
    fn try_into(self: u8) -> Option<FinalizationStatus> {
        if self == 0_u8 {
            Option::Some(FinalizationStatus::Pending(()))
        } else if self == 1_u8 {
            Option::Some(FinalizationStatus::Executed(()))
        } else if self == 2_u8 {
            Option::Some(FinalizationStatus::Cancelled(()))
        } else {
            Option::None(())
        }
    }
}

impl FinalizationStatusIntoU8 of Into<FinalizationStatus, u8> {
    fn into(self: FinalizationStatus) -> u8 {
        match self {
            FinalizationStatus::Pending(_) => 0_u8,
            FinalizationStatus::Executed(_) => 1_u8,
            FinalizationStatus::Cancelled(_) => 2_u8,
        }
    }
}

impl ProposalStatusIntoU8 of Into<ProposalStatus, u8> {
    fn into(self: ProposalStatus) -> u8 {
        match self {
            ProposalStatus::VotingDelay(_) => 0_u8,
            ProposalStatus::VotingPeriod(_) => 1_u8,
            ProposalStatus::VotingPeriodAccepted(_) => 2_u8,
            ProposalStatus::Accepted(_) => 3_u8,
            ProposalStatus::Executed(_) => 4_u8,
            ProposalStatus::Rejected(_) => 5_u8,
            ProposalStatus::Cancelled(_) => 6_u8,
        }
    }
}

impl LegacyHashChoice of LegacyHash<Choice> {
    fn hash(state: felt252, value: Choice) -> felt252 {
        LegacyHash::hash(state, ChoiceIntoU8::into(value))
    }
}

#[derive(Option, Clone, Drop, Serde, StorageAccess)]
struct Strategy {
    address: ContractAddress,
    params: Array<felt252>,
}

impl PartialEqStrategy of PartialEq<Strategy> {
    fn eq(lhs: @Strategy, rhs: @Strategy) -> bool {
        lhs.address == rhs.address
            && poseidon::poseidon_hash_span(
                lhs.params.span()
            ) == poseidon::poseidon_hash_span(rhs.params.span())
    }

    fn ne(lhs: @Strategy, rhs: @Strategy) -> bool {
        !(lhs.clone() == rhs.clone())
    }
}

#[derive(Option, Clone, Drop, Serde)]
struct IndexedStrategy {
    index: u8,
    params: Array<felt252>,
}

/// NOTE: Using u64 for timestamps instead of u32 which we use in sx-evm. can change if needed.
#[derive(Clone, Drop, Serde, PartialEq, StorageAccess)]
struct Proposal {
    snapshot_timestamp: u64,
    start_timestamp: u64,
    min_end_timestamp: u64,
    max_end_timestamp: u64,
    execution_payload_hash: felt252,
    execution_strategy: ContractAddress,
    author: ContractAddress,
    finalization_status: FinalizationStatus,
    active_voting_strategies: u256
}

// TODO: Should eventually be able to derive the StorageAccess trait on the structs and enum 
// cant atm as the derive only works for simple structs I think

impl StorageAccessFinalizationStatus of StorageAccess<FinalizationStatus> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<FinalizationStatus> {
        StorageAccessFinalizationStatus::read_at_offset_internal(address_domain, base, 0)
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: FinalizationStatus
    ) -> SyscallResult<()> {
        StorageAccessFinalizationStatus::write_at_offset_internal(address_domain, base, 0, value)
    }

    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<FinalizationStatus> {
        match StorageAccess::read_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 0_u8).into()
            ),
            offset
        ) {
            Result::Ok(num) => {
                Result::Ok(U8IntoFinalizationStatus::try_into(num).unwrap())
            },
            Result::Err(err) => Result::Err(err)
        }
    }

    fn write_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: FinalizationStatus
    ) -> SyscallResult<()> {
        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 0_u8).into()
            ),
            offset,
            FinalizationStatusIntoU8::into(value)
        )
    }

    fn size_internal(value: FinalizationStatus) -> u8 {
        1_u8
    }
}

impl StorageAccessProposal of StorageAccess<Proposal> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Proposal> {
        StorageAccessProposal::read_at_offset_internal(address_domain, base, 0)
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Proposal) -> SyscallResult<()> {
        StorageAccessProposal::write_at_offset_internal(address_domain, base, 0, value)
    }

    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Proposal> {
        Result::Ok(
            Proposal {
                snapshot_timestamp: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 0_u8).into()
                    ),
                    offset
                )?,
                start_timestamp: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 1_u8).into()
                    ),
                    offset
                )?,
                min_end_timestamp: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 2_u8).into()
                    ),
                    offset
                )?,
                max_end_timestamp: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 3_u8).into()
                    ),
                    offset
                )?,
                execution_payload_hash: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 4_u8).into()
                    ),
                    offset
                )?,
                execution_strategy: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 5_u8).into()
                    ),
                    offset
                )?,
                author: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 6_u8).into()
                    ),
                    offset
                )?,
                finalization_status: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 7_u8).into()
                    ),
                    offset
                )?,
                active_voting_strategies: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 8_u8).into()
                    ),
                    offset
                )?
            }
        )
    }

    fn write_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Proposal
    ) -> SyscallResult<()> {
        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 0_u8).into()
            ),
            offset,
            value.snapshot_timestamp
        );

        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 1_u8).into()
            ),
            offset,
            value.start_timestamp
        );

        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 2_u8).into()
            ),
            offset,
            value.min_end_timestamp
        );

        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 3_u8).into()
            ),
            offset,
            value.max_end_timestamp
        );

        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 4_u8).into()
            ),
            offset,
            value.execution_payload_hash
        );

        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 5_u8).into()
            ),
            offset,
            value.execution_strategy
        );

        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 6_u8).into()
            ),
            offset,
            value.author
        );

        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 7_u8).into()
            ),
            offset,
            value.finalization_status
        );

        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 8_u8).into()
            ),
            offset,
            value.active_voting_strategies
        )
    }

    fn size_internal(value: Proposal) -> u8 {
        9_u8
    }
}

impl StorageAccessFelt252Array of StorageAccess<Array<felt252>> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Array<felt252>> {
        StorageAccessFelt252Array::read_at_offset_internal(address_domain, base, 0)
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: Array<felt252>
    ) -> SyscallResult<()> {
        StorageAccessFelt252Array::write_at_offset_internal(address_domain, base, 0, value)
    }

    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8
    ) -> SyscallResult<Array<felt252>> {
        let mut arr: Array<felt252> = ArrayTrait::new();

        // Read the stored array's length. If the length is superior to 255, the read will fail.
        let len: u8 = StorageAccess::<u8>::read_at_offset_internal(address_domain, base, offset)
            .expect('Storage Span too large');
        offset += 1;

        // Sequentially read all stored elements and append them to the array.
        let exit = len + offset;
        loop {
            if offset >= exit {
                break;
            }

            let value = StorageAccess::<felt252>::read_at_offset_internal(
                address_domain, base, offset
            )
                .unwrap();
            arr.append(value);
            offset += StorageAccess::<felt252>::size_internal(value);
        };

        // Return the array.
        Result::Ok(arr)
    }

    fn write_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8, mut value: Array<felt252>
    ) -> SyscallResult<()> {
        // // Store the length of the array in the first storage slot.
        let len: u8 = value.len().try_into().expect('Storage - Span too large');
        StorageAccess::<u8>::write_at_offset_internal(address_domain, base, offset, len);
        offset += 1;

        // Store the array elements sequentially
        loop {
            match value.pop_front() {
                Option::Some(element) => {
                    StorageAccess::<felt252>::write_at_offset_internal(
                        address_domain, base, offset, element
                    )?;
                    offset += StorageAccess::<felt252>::size_internal(element);
                },
                Option::None(_) => {
                    break Result::Ok(());
                }
            };
        }
    }

    fn size_internal(value: Array<felt252>) -> u8 {
        if value.len() == 0 {
            return 1;
        }
        1_u8 + StorageAccess::<felt252>::size_internal(*value[0]) * value.len().try_into().unwrap()
    }
}

impl StorageAccessStrategy of StorageAccess<Strategy> {
    // #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Strategy> {
        StorageAccessStrategy::read_at_offset_internal(address_domain, base, 0)
    }
    // #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Strategy) -> SyscallResult<()> {
        StorageAccessStrategy::write_at_offset_internal(address_domain, base, 0, value)
    }

    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Strategy> {
        Result::Ok(
            Strategy {
                address: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 0_u8).into()
                    ),
                    offset
                )?,
                params: StorageAccess::read_at_offset_internal(
                    address_domain,
                    storage_base_address_from_felt252(
                        storage_address_from_base_and_offset(base, 1_u8).into()
                    ),
                    offset
                )?
            }
        )
    }

    fn write_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Strategy
    ) -> SyscallResult<()> {
        // Write value.address at offset 0
        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 0_u8).into()
            ),
            offset,
            value.address
        );

        // Write value.params at offset 1
        StorageAccess::write_at_offset_internal(
            address_domain,
            storage_base_address_from_felt252(
                storage_address_from_base_and_offset(base, 1_u8).into()
            ),
            offset,
            value.params
        )
    }

    fn size_internal(value: Strategy) -> u8 {
        // Add 1 for the strategy address
        StorageAccess::size_internal(value.params) + 1
    }
}

trait IndexedStrategyTrait {
    fn assert_no_duplicate_indices(self: @Array<IndexedStrategy>);
}

impl IndexedStrategyImpl of IndexedStrategyTrait {
    fn assert_no_duplicate_indices(self: @Array<IndexedStrategy>) {
        if self.len() < 2 {
            return ();
        }

        let mut bit_map = u256 { low: 0_u128, high: 0_u128 };
        let mut i = 0_usize;
        loop {
            if i >= self.len() {
                break ();
            }
            // Check that bit at index `strats[i].index` is not set.
            let s = pow(u256 { low: 2_u128, high: 0_u128 }, *self.at(i).index);

            assert((bit_map & s) == u256 { low: 1_u128, high: 0_u128 }, 'Duplicate Found');
            // Update aforementioned bit.
            bit_map = bit_map | s;
            i += 1;
        };
    }
}

// TODO: move to u32
#[derive(Clone, Drop, Serde)]
struct UpdateSettingsCalldata {
    min_voting_duration: u64,
    max_voting_duration: u64,
    voting_delay: u64,
    metadata_URI: Array<felt252>,
    dao_URI: Array<felt252>,
    proposal_validation_strategy: Strategy,
    proposal_validation_strategy_metadata_URI: Array<felt252>,
    authenticators_to_add: Array<ContractAddress>,
    authenticators_to_remove: Array<ContractAddress>,
    voting_strategies_to_add: Array<Strategy>,
    voting_strategies_metadata_URIs_to_add: Array<Array<felt252>>,
    voting_strategies_to_remove: Array<u8>,
}

trait UpdateSettingsCalldataTrait {
    fn default() -> UpdateSettingsCalldata;
}

// Theoretically could derive a value with a proc_macro,
// since NO_UPDATE values are simply the first x bytes of a hash.
trait NoUpdateTrait<T> {
    fn no_update() -> T;
    fn should_update(self: @T) -> bool;
}

// Obtained by keccak256 hashing the string "No update", and then taking the corresponding number of bytes.
// Evaluates to: 0xf2cda9b13ed04e585461605c0d6e804933ca828111bd94d4e6a96c75e8b048ba

impl NoUpdateU32 of NoUpdateTrait<u32> {
    fn no_update() -> u32 {
        0xf2cda9b1
    }

    fn should_update(self: @u32) -> bool {
        *self != 0xf2cda9b1
    }
}

impl NoUpdateU64 of NoUpdateTrait<u64> {
    fn no_update() -> u64 {
        0xf2cda9b13ed04e58
    }

    fn should_update(self: @u64) -> bool {
        *self != 0xf2cda9b13ed04e58
    }
}

impl NoUpdateFelt252 of NoUpdateTrait<felt252> {
    fn no_update() -> felt252 {
        // First 248 bits
        0xf2cda9b13ed04e585461605c0d6e804933ca828111bd94d4e6a96c75e8b048
    }

    fn should_update(self: @felt252) -> bool {
        *self != 0xf2cda9b13ed04e585461605c0d6e804933ca828111bd94d4e6a96c75e8b048
    }
}

impl NoUpdateContractAddress of NoUpdateTrait<ContractAddress> {
    fn no_update() -> ContractAddress {
        // First 248 bits
        contract_address_const::<0xf2cda9b13ed04e585461605c0d6e804933ca828111bd94d4e6a96c75e8b048>()
    }

    fn should_update(self: @ContractAddress) -> bool {
        *self != contract_address_const::<0xf2cda9b13ed04e585461605c0d6e804933ca828111bd94d4e6a96c75e8b048>()
    }
}

impl NoUpdateStrategy of NoUpdateTrait<Strategy> {
    fn no_update() -> Strategy {
        Strategy {
            address: contract_address_const::<0xf2cda9b13ed04e585461605c0d6e804933ca828111bd94d4e6a96c75e8b048>(),
            params: array::ArrayTrait::new(),
        }
    }

    fn should_update(self: @Strategy) -> bool {
        *self
            .address != contract_address_const::<0xf2cda9b13ed04e585461605c0d6e804933ca828111bd94d4e6a96c75e8b048>()
    }
}

// TODO: find a way for "Strings"
impl NoUpdateArray<T> of NoUpdateTrait<Array<T>> {
    fn no_update() -> Array<T> {
        array::ArrayTrait::<T>::new()
    }

    fn should_update(self: @Array<T>) -> bool {
        self.len() != 0
    }
}


impl UpdateSettingsCalldataImpl of UpdateSettingsCalldataTrait {
    fn default() -> UpdateSettingsCalldata {
        UpdateSettingsCalldata {
            min_voting_duration: NoUpdateU64::no_update(),
            max_voting_duration: NoUpdateU64::no_update(),
            voting_delay: NoUpdateU64::no_update(),
            metadata_URI: NoUpdateArray::no_update(),
            dao_URI: NoUpdateArray::no_update(),
            proposal_validation_strategy: NoUpdateStrategy::no_update(),
            proposal_validation_strategy_metadata_URI: NoUpdateArray::no_update(),
            authenticators_to_add: NoUpdateArray::no_update(),
            authenticators_to_remove: NoUpdateArray::no_update(),
            voting_strategies_to_add: NoUpdateArray::no_update(),
            voting_strategies_metadata_URIs_to_add: NoUpdateArray::no_update(),
            voting_strategies_to_remove: NoUpdateArray::no_update(),
        }
    }
}
