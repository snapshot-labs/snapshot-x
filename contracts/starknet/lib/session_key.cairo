// SPDX-License-Identifier: MIT

%lang starknet

from starkware.starknet.common.syscalls import get_block_timestamp
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.cairo.common.math import assert_lt, assert_not_zero, assert_nn_le
from starkware.cairo.common.alloc import alloc

from contracts.starknet.lib.stark_eip191 import StarkEIP191
from contracts.starknet.lib.eip712 import EIP712
from contracts.starknet.lib.eth_tx import EthTx
from contracts.starknet.lib.array_utils import ArrayUtils

//
// @title Session Key Library
// @author SnapshotLabs
// @notice A library to handle the authorization and revokation of StarkNet session keys from an Ethereum account
//

// @dev Stores the owner Ethereum address for a given session key
@storage_var
func SessionKey_owner_store(session_public_key: felt) -> (eth_address: felt) {
}

// @dev Stores the timestamp at which a session key is no longer valid
@storage_var
func SessionKey_end_timestamp_store(session_public_key: felt) -> (timestamp: felt) {
}

@event
func session_key_registered(eth_address: felt, session_public_key: felt, session_duration: felt) {
}

@event
func session_key_revoked(session_public_key: felt) {
}

namespace SessionKey {
    // @dev Registers a session key via authorization from an Ethereum EIP712 signature
    // @param r Signature parameter
    // @param s Signature parameter
    // @param v Signature parameter
    // @param salt Signature salt
    // @param eth_address Owner's Ethereum Address that was used to create the signature
    // @param session_public_key The StarkNet session public key that should be registered
    // @param session_duration The number of seconds that the session key is valid
    func authorize_with_sig{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        bitwise_ptr: BitwiseBuiltin*,
        range_check_ptr,
    }(
        r: Uint256,
        s: Uint256,
        v: felt,
        salt: Uint256,
        eth_address: felt,
        session_public_key: felt,
        session_duration: felt,
    ) {
        alloc_locals;

        EIP712.verify_session_key_auth_sig(
            r, s, v, salt, eth_address, session_public_key, session_duration
        );
        _register(eth_address, session_public_key, session_duration);
        return ();
    }

    // @dev Registers a session key via authorization from an Ethereum transaction
    // @dev Users must commit a hash to the StarkNet Commit contract on L1 and wait for it to be propogated to L2 before calling this function
    // @param eth_address Owner's Ethereum Address that was used to commit the hash on Ethereum
    // @param session_public_key The StarkNet session public key that should be registered
    // @param session_duration The number of seconds that the session key is valid
    func authorize_with_tx{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        eth_address: felt, session_public_key: felt, session_duration: felt
    ) {
        alloc_locals;
        let (commit_array: felt*) = alloc();
        assert commit_array[0] = eth_address;
        assert commit_array[1] = session_public_key;
        assert commit_array[2] = session_duration;
        let (commit_hash) = ArrayUtils.hash(3, commit_array);

        // Checks that the hash matches a commit and that the commit was created by the correct address
        EthTx.consume_commit(commit_hash, eth_address);

        _register(eth_address, session_public_key, session_duration);
        return ();
    }

    // @dev Revokes a session key via authorization from a signature from the session key itself
    // @param r Signature parameter
    // @param s Signature parameter
    // @param salt Signature salt
    // @param session_public_key The StarkNet session public key that should be revoked
    func revoke_with_session_key_sig{
        syscall_ptr: felt*,
        range_check_ptr,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
    }(r: felt, s: felt, salt: felt, session_public_key: felt) {
        alloc_locals;
        let (eth_address) = SessionKey_owner_store.read(session_public_key);
        with_attr error_message("SessionKey: Session does not exist") {
            assert_not_zero(eth_address);
        }
        StarkEIP191.verify_session_key_revoke_sig(r, s, salt, session_public_key);
        _revoke(session_public_key);
        return ();
    }

    // @dev Revokes a session key via authorization from a signature from the owner Ethereum account
    // @param r Signature parameter
    // @param s Signature parameter
    // @param v Signature parameter
    // @param salt Signature salt
    // @param session_public_key The StarkNet session public key that should be revoked
    func revoke_with_owner_sig{
        syscall_ptr: felt*,
        range_check_ptr,
        pedersen_ptr: HashBuiltin*,
        bitwise_ptr: BitwiseBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
    }(r: Uint256, s: Uint256, v: felt, salt: Uint256, session_public_key: felt) {
        alloc_locals;

        let (eth_address) = SessionKey_owner_store.read(session_public_key);
        with_attr error_message("SessionKey: Session does not exist") {
            assert_not_zero(eth_address);
        }
        EIP712.verify_session_key_revoke_sig(r, s, v, salt, eth_address, session_public_key);
        _revoke(session_public_key);
        return ();
    }

    // @dev Revokes a session key via authorization from an Ethereum transaction by the owner
    // @dev Users must commit a hash to the StarkNet Commit contract on L1 and wait for it to be propogated to L2 before calling this function
    // @param session_public_key The StarkNet session public key that should be revoked
    func revoke_with_owner_tx{syscall_ptr: felt*, range_check_ptr, pedersen_ptr: HashBuiltin*}(
        session_public_key: felt
    ) {
        alloc_locals;
        let (eth_address) = SessionKey_owner_store.read(session_public_key);
        with_attr error_message("SessionKey: Session does not exist") {
            assert_not_zero(eth_address);
        }
        let (commit_array: felt*) = alloc();
        assert commit_array[0] = eth_address;
        assert commit_array[1] = session_public_key;
        let (commit_hash) = ArrayUtils.hash(2, commit_array);

        // Checks that hash maches a commit and that the commit was created by the correct address
        EthTx.consume_commit(commit_hash, eth_address);

        _revoke(session_public_key);

        return ();
    }

    // @dev Returns owner of a session key if it exists, otherwise throws
    // @param session_public_key The StarkNet session public key
    // return owner The owner Ethereum address
    func get_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        session_public_key: felt
    ) -> (owner: felt) {
        let (owner) = SessionKey_owner_store.read(session_public_key);
        with_attr error_message("SessionKey: Session does not exist") {
            assert_not_zero(owner);
        }

        let (end_timestamp) = SessionKey_end_timestamp_store.read(session_public_key);
        let (current_timestamp) = get_block_timestamp();
        with_attr error_message("SessionKey: Session has ended") {
            assert_lt(current_timestamp, end_timestamp);
        }
        return (owner,);
    }

    // @dev Asserts that a session key exists and has an owner equal to _owner
    // @param session_public_key The StarkNet session public key
    // @param _owner An Ethereum address
    func assert_valid{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        session_public_key: felt, _owner: felt
    ) {
        let (owner) = get_owner(session_public_key);
        with_attr error_message("SessionKey: Invalid owner") {
            assert _owner = owner;
        }
        return ();
    }
}

//
//  Internal Functions
//

func _register{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    eth_address: felt, session_public_key: felt, session_duration: felt
) {
    // It is valid to give a session duration of zero - if so it means the session is only valid during the same block as when it was registered
    let (current_timestamp) = get_block_timestamp();
    let end_timestamp = current_timestamp + session_duration;
    with_attr error_message("SessionKey: Invalid session duration") {
        // Asserts that 0 <= session_duration <= end_timestamp < RANGE_CHECK_BOUND
        assert_nn_le(session_duration, end_timestamp);
    }
    SessionKey_owner_store.write(session_public_key, eth_address);
    SessionKey_end_timestamp_store.write(session_public_key, end_timestamp);
    session_key_registered.emit(eth_address, session_public_key, session_duration);
    return ();
}

func _revoke{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    session_public_key: felt
) {
    SessionKey_owner_store.write(session_public_key, 0);
    session_key_revoked.emit(session_public_key);
    return ();
}
