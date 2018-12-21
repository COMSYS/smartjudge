pragma solidity ^0.5.0;

contract Verifier {
    function register_verification(address alice, address bob, uint32 id, bytes32 initial_state, bytes32 evidence) public;
    function register_verification(address alice, address bob, uint32 id, bytes32 initial_state, bytes32 evidence, bytes32 data) public;
}
