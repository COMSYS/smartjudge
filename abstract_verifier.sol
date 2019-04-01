pragma solidity ^0.5.0;

contract Verifier {
    function start_verification(address alice, address bob, uint32 id, bytes32 initial_agreement, bytes32 witness) public;
    function start_verification(address alice, address bob, uint32 id, bytes32 initial_agreement, bytes32 witness, bytes32 data) public;
}
