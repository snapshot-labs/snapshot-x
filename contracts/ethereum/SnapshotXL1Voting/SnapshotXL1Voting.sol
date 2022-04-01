/// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import './Interfaces/IStarknetCore.sol';

/**
 * @title Snapshot X L1 Voting contract
 * @author @Orland0x - <orlandothefraser@gmail.com>
 * @notice Allows EOAs and contract accounts to vote on Snapshot X with an L1 transaction, no signature needed.
 * @dev Work in progress
 */
abstract contract SnapshotXL1Voting {
  /// The StarkNet core contract.
  IStarknetCore public immutable starknetCore;

  /// address of the voting Authenticator contract that handles L1 votes
  uint256 public immutable votingAuthL1;

  /**
   * @dev Selector for the L1 handler submit_vote in the vote authenticator, found via:
   *      from starkware.starknet.compiler.compile import get_selector_from_name
   *      print(get_selector_from_name('submit_vote'))
   */
  uint256 private constant L1_VOTE_HANDLER =
    1564459668182098068965022601237862430004789345537526898295871983090769185429;

  /// @dev print(get_selector_from_name('submit_proposal'))
  uint256 private constant L1_PROPOSE_HANDLER =
    1604523576536829311415694698171983789217701548682002859668674868169816264965;

  /// @dev print(get_selector_from_name('delegate'))
  uint256 private constant L1_DELEGATE_HANDLER =
    1746921722015266013928822119890040225899444559222897406293768364420627026412;

  /* EVENTS */

  /**
   * @dev Emitted when a new L1 vote is submitted
   * @param votingContract Address of StarkNet voting contract
   * @param proposalID ID of the proposal the vote was submitted to
   * @param voter Address of the voter
   * @param choice The vote {1,2,3}
   */
  event L1VoteSubmitted(uint256 votingContract, uint256 proposalID, address voter, uint256 choice);

  /**
   * @dev Emitted when a new proposal is submitted via L1 vote
   * @param votingContract Address of StarkNet voting contract
   * @param executionHash Hash of the proposal execution details
   * @param metadataHash Hash of the proposal metadata
   * @param proposer Address of the proposer
   */
  event L1ProposalSubmitted(
    uint256 votingContract,
    uint256 executionHash,
    uint256 metadataHash,
    address proposer
  );

  /// Vote object
  struct Vote {
    uint256 vc_address;
    uint256 proposalID;
    uint256 choice;
  }

  /**
   * @dev Constructor
   * @param _starknetCore Address of the StarkNet core contract
   * @param _votingAuthL1 Address of the StarkNet vote authenticator for L1 votes
   */
  constructor(address _starknetCore, uint256 _votingAuthL1) {
    starknetCore = IStarknetCore(_starknetCore);
    votingAuthL1 = _votingAuthL1;
  }

  /**
   * @dev Submit vote to Snapshot X proposal via L1 transaction (No signature needed)
   * @param proposalID ID of the proposal
   * @param choice The vote {1,2,3}
   */
  function voteOnL1(
    uint256 votingContract,
    uint256 proposalID,
    uint256 choice
  ) external {
    uint256[] memory payload = new uint256[](4);
    payload[0] = votingContract;
    payload[1] = proposalID;
    payload[2] = uint256(uint160(address(msg.sender)));
    payload[3] = choice;
    starknetCore.sendMessageToL2(votingAuthL1, L1_VOTE_HANDLER, payload);
    emit L1VoteSubmitted(votingContract, proposalID, msg.sender, choice);
  }

  function proposeOnL1(uint256 executionHash, uint256 metadataHash) external virtual;

  function delegateOnL1(
    uint256 proposalID,
    uint256 startBlockNumber,
    uint256 endBlockNumber
  ) external virtual;
}
