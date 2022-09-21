%lang starknet

from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.uint256 import uint256_eq, Uint256
from starkware.cairo.common.alloc import alloc
from contracts.starknet.lib.hash_array import HashArray
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.starknet.common.syscalls import get_contract_address
from contracts.starknet.lib.felt_utils import FeltUtils

# Following a Starknet version of the EIP191 standard

# { name: 'snapshot-x', version: '1', chainId: '0x534e5f474f45524c49'} (chainID: SN_GOERLI)
const DOMAIN_HASH = 0x7b887e96718721a64b601a4873454d4a9e26a4b798d660c8d6b96d2045c8404

const STARKNET_MESSAGE = 0x537461726b4e6574204d657373616765

# getSelectorFromName("Propose(space:felt,proposerAddress:felt,metadataURI:felt*,executor:felt,executionParamsHash:felt,usedVotingStrategiesHash:felt,userVotingStrategyParamsFlatHash:felt,salt:felt)")
const PROPOSAL_TYPE_HASH = 0x35E10EF4A95BB833EE01F14D379540B1724B76496753505D7CCEB30E133BF2

# getSelectorFromName("Vote(space:felt,voterAddress:felt,proposal:felt,choice:felt,usedVotingStrategiesHash:felt,userVotingStrategyParamsFlatHash:felt,salt:felt)")
const VOTE_TYPE_HASH = 0x2A9A147261602C563F1C9D05CA076F6AE23A8A7A161EE8C8E3DE6E468BEAF9E

# getSelectorFromName("RevokeSessionKey(salt:felt)")
const REVOKE_SESSION_KEY_TYPE_HASH = 0x31F0BF4E2BBD12ECBA02E325F0EA3231350A638FC633AF8EBF244F50663ACE8

# Maps a tuple of (user, salt) to a boolean stating whether this tuple was already used or not (to prevent replay attack).
@storage_var
func StarkEIP191_salts(user : felt, salt : felt) -> (already_used : felt):
end

namespace StarkEIP191:
    func verify_propose_sig{
        syscall_ptr : felt*,
        range_check_ptr,
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
    }(
        r : felt,
        s : felt,
        salt : felt,
        target : felt,
        calldata_len : felt,
        calldata : felt*,
        public_key : felt,
    ):
        alloc_locals

        let proposer_address = calldata[0]

        let (authenticator) = get_contract_address()

        # Ensure proposer has not already used this salt in a previous action
        let (already_used) = StarkEIP191_salts.read(proposer_address, salt)

        with_attr error_message("Salt already used"):
            assert already_used = 0
        end

        # Metadata URI
        let metadata_uri_string_len = calldata[1]
        let metadata_uri_len = calldata[2]
        let metadata_uri : felt* = &calldata[3]
        let (metadata_uri_hash) = HashArray.hash_array(metadata_uri_len, metadata_uri)

        # Executor
        let executor = calldata[3 + metadata_uri_len]
        let (executor_u256) = FeltUtils.felt_to_uint256(executor)

        # Used voting strategies
        let used_voting_strats_len = calldata[4 + metadata_uri_len]
        let used_voting_strats = &calldata[5 + metadata_uri_len]
        let (used_voting_strategies_hash) = HashArray.hash_array(
            used_voting_strats_len, used_voting_strats
        )

        # User voting strategy params flat
        let user_voting_strat_params_flat_len = calldata[5 + metadata_uri_len + used_voting_strats_len]
        let user_voting_strat_params_flat = &calldata[6 + metadata_uri_len + used_voting_strats_len]
        let (user_voting_strategy_params_flat_hash) = HashArray.hash_array(
            user_voting_strat_params_flat_len, user_voting_strat_params_flat
        )

        # Execution hash
        let execution_params_len = calldata[6 + metadata_uri_len + used_voting_strats_len + user_voting_strat_params_flat_len]
        let execution_params_ptr : felt* = &calldata[7 + metadata_uri_len + used_voting_strats_len + user_voting_strat_params_flat_len]
        let (execution_hash) = HashArray.hash_array(execution_params_len, execution_params_ptr)

        let (structure : felt*) = alloc()

        assert structure[0] = PROPOSAL_TYPE_HASH
        assert structure[1] = target
        assert structure[2] = proposer_address
        assert structure[3] = metadata_uri_hash
        assert structure[4] = executor
        assert structure[5] = execution_hash
        assert structure[6] = used_voting_strategies_hash
        assert structure[7] = user_voting_strategy_params_flat_hash
        assert structure[8] = salt

        let (hash_struct) = HashArray.hash_array(9, structure)

        let (message : felt*) = alloc()

        assert message[0] = STARKNET_MESSAGE
        assert message[1] = DOMAIN_HASH
        assert message[2] = authenticator
        assert message[3] = hash_struct

        let (message_hash) = HashArray.hash_array(4, message)

        verify_ecdsa_signature(message_hash, public_key, r, s)

        StarkEIP191_salts.write(proposer_address, salt, 1)

        return ()
    end

    func verify_vote_sig{
        syscall_ptr : felt*,
        range_check_ptr,
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
    }(
        r : felt,
        s : felt,
        salt : felt,
        target : felt,
        calldata_len : felt,
        calldata : felt*,
        public_key : felt,
    ):
        alloc_locals

        let voter_address = calldata[0]

        let (authenticator) = get_contract_address()

        # Ensure voter has not already used this salt in a previous action
        let (already_used) = StarkEIP191_salts.read(voter_address, salt)

        with_attr error_message("Salt already used"):
            assert already_used = 0
        end

        let proposal_id = calldata[1]
        let choice = calldata[2]

        let used_voting_strategies_len = calldata[3]
        let used_voting_strategies = &calldata[4]
        let (used_voting_strategies_hash) = HashArray.hash_array(
            used_voting_strategies_len, used_voting_strategies
        )

        let user_voting_strategy_params_flat_len = calldata[4 + used_voting_strategies_len]
        let user_voting_strategy_params_flat = &calldata[5 + used_voting_strategies_len]
        let (user_voting_strategy_params_flat_hash) = HashArray.hash_array(
            user_voting_strategy_params_flat_len, user_voting_strategy_params_flat
        )

        # Now construct the data hash (hashStruct)
        let (structure : felt*) = alloc()
        assert structure[0] = VOTE_TYPE_HASH
        assert structure[1] = target
        assert structure[2] = voter_address
        assert structure[3] = proposal_id
        assert structure[4] = choice
        assert structure[5] = used_voting_strategies_hash
        assert structure[6] = user_voting_strategy_params_flat_hash
        assert structure[7] = salt

        let (hash_struct) = HashArray.hash_array(8, structure)

        let (message : felt*) = alloc()

        assert message[0] = STARKNET_MESSAGE
        assert message[1] = DOMAIN_HASH
        assert message[2] = authenticator
        assert message[3] = hash_struct

        let (message_hash) = HashArray.hash_array(4, message)

        verify_ecdsa_signature(message_hash, public_key, r, s)

        StarkEIP191_salts.write(voter_address, salt, 1)

        return ()
    end

    func verify_session_key_revoke_sig{
        syscall_ptr : felt*,
        range_check_ptr,
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
    }(r : felt, s : felt, salt : felt, public_key : felt):
        alloc_locals

        let (authenticator) = get_contract_address()

        # Ensure voter has not already used this salt in a previous action
        let (already_used) = StarkEIP191_salts.read(public_key, salt)
        with_attr error_message("Salt already used"):
            assert already_used = 0
        end

        # Now construct the data hash (hashStruct)
        let (structure : felt*) = alloc()
        assert structure[0] = REVOKE_SESSION_KEY_TYPE_HASH
        assert structure[1] = salt

        let (hash_struct) = HashArray.hash_array(2, structure)

        let (message : felt*) = alloc()

        assert message[0] = STARKNET_MESSAGE
        assert message[1] = DOMAIN_HASH
        assert message[2] = authenticator
        assert message[3] = hash_struct

        let (message_hash) = HashArray.hash_array(4, message)

        verify_ecdsa_signature(message_hash, public_key, r, s)

        StarkEIP191_salts.write(public_key, salt, 1)

        return ()
    end
end
