pragma solidity ^0.5.0;

contract Mediator{

  enum ContractState {
    CREATED,
    ACCEPTED,
    REVEALED,
    CONTESTED,
    WAITING,
    FINISHED
  }

  struct Verification{
    uint256 costs;
    address contract_address;
  }

  struct Contract{
    ContractState state;
    address payable alice;
    uint alice_funds;
    address payable bob;
    uint bob_funds;
    bytes32 contract_hash;
    uint current_height;
    uint gascost;
  }

  struct Contestion{
    bool revealed_data;
    bytes32 evidence;
    uint32 verifier_id;
    uint256 verification_fee_made;
  }

  uint256 SECURITY_DEPOSIT = 400000; // 400000 gas worst case costs until verification for Alice
  uint64 TIMEOUT_BLOCKS = 6 * 60 * 24; // 24 hours

  mapping(uint32 => Contract) contracts;
  mapping(uint32 => Verification) verifications;
  mapping(uint256 => bytes32) data;
  mapping(uint256 => Contestion) contestions;

  uint32 verifier_counter = 0;
  uint32 contract_counter = 0;

  /**
   * Lets Alice create a new contract based on a hash and returns
   * the id to process this contract. A price higher or equal to
   * the SECURITY_DEPOSIT has to be put in escrow. Everything above the 
   * SECURITY_DEPOSIT is the payment to Bob in case that the contract ends gracefully.
   *
   * @param     contract_hash   Hash of the selected verifier and the initial terms of the contract
   *
   * @return    Id used to process this contract
   **/
  function create(bytes32 contract_hash) public payable returns (uint32 id){
      require(msg.value >= SECURITY_DEPOSIT * tx.gasprice);

      Contract storage c = contracts[contract_counter];

      c.state = ContractState.CREATED;
      c.contract_hash = contract_hash;
      c.alice = msg.sender;
      c.alice_funds = SECURITY_DEPOSIT * tx.gasprice;
      c.bob_funds = msg.value - SECURITY_DEPOSIT * tx.gasprice;
      c.current_height = block.number;
      c.gascost = tx.gasprice;
      
      return contract_counter++;
  }

  /**
   * Lets Alice create a new contract based on a hash.
   * The id to process the contract is preselected to that of
   * a finished contract, in order to reuse the storage.
   * A price higher or equal to
   * the SECURITY_DEPOSIT has to be put in escrow. Everything above the 
   * SECURITY_DEPOSIT is the payment to Bob in case that the contract ends gracefully.
   *
   * @param id              Id selected for the processing of this contract
   * @param contract_hash   Hash of the selected verifier and the initial terms of the contract
   **/
  function create(uint32 id, bytes32 contract_hash) public payable{
      Contract storage c = contracts[id];

      require(msg.value >= SECURITY_DEPOSIT * tx.gasprice);
      require(c.state == ContractState.FINISHED);

      c.state = ContractState.CREATED;
      c.contract_hash = contract_hash;
      c.alice = msg.sender;
      c.alice_funds = SECURITY_DEPOSIT * tx.gasprice;
      c.bob_funds = msg.value - SECURITY_DEPOSIT * tx.gasprice;
      c.current_height = block.number;
  }

  /**
   * This function lets Alice cancel a contract as long as no one accepted it beforehand.
   *
   * @param id              The id of the processed contract
   **/
  function abort(uint32 id) public{
      Contract storage c = contracts[id];

      require(msg.sender == c.alice);
      require(c.state == ContractState.CREATED);

      c.alice.transfer(c.alice_funds + c.bob_funds);
      c.state = ContractState.FINISHED;
  }

  /**
   * This function lets Bob accept a contract.
   * A deposit covering at least the TRADE_STAKE has to be made.
   * An increased deposit could be used if the two party protocol temporarly 
   * puts Alice at a monetary disadvantage.
   * 
   * @param id              The id of the processed contract
   **/
  function accept(uint32 id) payable public{

      Contract storage c = contracts[id];

      require(c.state == ContractState.CREATED);
      require(msg.value >= SECURITY_DEPOSIT * tx.gasprice);

      c.bob = msg.sender;
      c.bob_funds += msg.value;
      c.current_height = block.number;
      c.state = ContractState.ACCEPTED;
  }

  /**
   * This function lets Alice end a contract gracefully.
   * This pays out Bob the promised amount and both parties
   * recover their deposits.
   *
   * @param id              The id of the processed contract
   **/
  function finish(uint32 id) public{

      Contract storage c = contracts[id];

      require(c.state == ContractState.ACCEPTED || c.state == ContractState.REVEALED || c.state == ContractState.CONTESTED);
      require(msg.sender == c.alice);

      c.alice.transfer(c.alice_funds);
      c.bob.transfer(c.bob_funds);
      c.state = ContractState.FINISHED;
  }

  /**
   * This function lets Bob reveal a data object in case that is necessary
   * for the verification. It is recommended to use offchain channels
   * to save cost and increase anonyinimity. To incentive both parties to do so,
   * the cost of the execution of this function are split between both users.
   *
   * @param id              The id of the processed contract
   * @param revealed_data   Data which has to be received verifiably by Alice
   **/
  function reveal(uint32 id, bytes32 revealed_data) public{

      uint256 gas_beginning = gasleft();

      Contract storage c = contracts[id];

      require(c.state == ContractState.ACCEPTED);
      require(msg.sender == c.bob);

      data[id] = revealed_data;
      c.current_height = block.number;
      c.state = ContractState.REVEALED;

      uint256 fees = (gas_beginning - gasleft() + 28000) * tx.gasprice/2;
      if(fees > c.alice_funds){
          fees = c.alice_funds;
      }
      
      c.alice_funds -= fees;
      c.bob_funds += fees;
  }

  /**
   * This function lets Bob contest a contract.
   * He has to make a deposit which matches the indicated cost of the verifier,
   * which is checked later. To incentive both parties to do so,
   * the cost of the execution of this function are split between both users.
   *
   * @param id              The id of the processed contract
   * @param evidence        Evidence brought forward by Bob
   **/
   function contest(uint32 id, bytes32 evidence) payable public {

      uint256 gas_beginning = gasleft();

      Contract storage c = contracts[id];
      Contestion storage cont = contestions[id];

      require(msg.sender == c.bob);
      require(c.state == ContractState.ACCEPTED || c.state == ContractState.REVEALED);

      cont.revealed_data = (c.state == ContractState.REVEALED);

      cont.evidence = evidence;
      cont.verification_fee_made = msg.value/c.gascost;

      c.bob_funds += msg.value;
      c.current_height = block.number;
      c.state = ContractState.CONTESTED;

      uint256 fees = (gas_beginning - gasleft() + 28000) * tx.gasprice/2;
      if(fees > c.alice_funds){
          fees = c.alice_funds;
      }

      c.alice_funds -= fees;
      c.bob_funds += fees;
   }

  /**
   * This function lets Alice initate the verification process and provides her evidence.
   * She has to make her deposit and the value of the depostis of both parties are checked.
   * Afterwards the control is delegated to the selected verifier.
   *
   * @param id              The id of the processed contract
   * @param verifier_id     The registration id of the agreed upon verifer
   * @param initial_state   The initally agreed upon state by both participants
   **/
   function init_verification_process(uint32 id, uint32 verifier_id, bytes32 initial_state) payable public {

      Contract storage c = contracts[id];

      require(msg.sender == c.alice);
      require(c.state == ContractState.CONTESTED);

      c.alice_funds += msg.value;

      if( c.contract_hash == sha256(abi.encodePacked(verifier_id, initial_state)) ){

          contestions[id].verifier_id = verifier_id;
          Verifier used_verifier = Verifier(verifications[verifier_id].contract_address);

          if(contestions[id].verification_fee_made != verifications[verifier_id].costs){
            c.alice.transfer(c.bob_funds + c.alice_funds);
            c.state = ContractState.FINISHED;
            return;
          }

          if(msg.value/c.gascost != verifications[verifier_id].costs){
            c.bob.transfer(c.bob_funds + c.alice_funds);
            c.state = ContractState.FINISHED;
            return;
          }

          if(contestions[id].revealed_data)
            used_verifier.register_verification(c.alice, c.bob, id, initial_state, contestions[id].evidence, data[id]);
          else
            used_verifier.register_verification(c.alice, c.bob, id, initial_state, contestions[id].evidence);

          c.state = ContractState.WAITING;

      } else {

          c.bob.transfer(c.alice_funds + c.bob_funds);
          c.state = ContractState.FINISHED;

      }
    }

  /**
   * This function should be called when the verifier contract has evaluated the claim.
   * It can only be called by the selected verifier, and pays the whole deposits out to the honest party.
   *
   * @param id              The id of the processed contract
   * @param honest_party    The address of the party that acted honestly during the execution of the contract
   **/
  function verifier_callback(uint32 id, address honest_party) public{

      Contract storage c = contracts[id];

      require(c.state == ContractState.WAITING);
      require(msg.sender == verifications[contestions[id].verifier_id].contract_address);

      if(honest_party == c.bob)
        c.bob.transfer(c.bob_funds + c.alice_funds);
      else
        c.alice.transfer(c.bob_funds + c.alice_funds);

      c.state = ContractState.FINISHED;
  }
  
  /**
   * This function allows Alice or Bob to timeout the other party when applicable.
   * 
   * @param id              The id of the processed contract
   **/
  function timeout(uint32 id) public{
       
        Contract storage c = contracts[id];
       
        require( (msg.sender == c.alice && (c.state == ContractState.ACCEPTED || c.state == ContractState.REVEALED))
                || (msg.sender == c.bob && c.state == ContractState.CONTESTED));
                
        require( c.current_height + TIMEOUT_BLOCKS >= block.number );
                
        msg.sender.transfer(c.bob_funds + c.alice_funds);
        c.state = ContractState.FINISHED;
   }

  /**
   * This function registers a new verifier to the notary.
   * It has to implement the verifier interface.
   * After this call, the verifier can be used by Alice to create new contracts.
   *
   * @param verifier_address    The address of the verifier smart contract
   * @param verifier_cost       The maximum cost of the execution of the verifier, such that sufficient security deposits are made
   *
   * @return    Id used to select this verifier
   **/
  function register_verifier(address verifier_address, uint256 verifier_cost) public returns (uint32 id){
      Verification storage v = verifications[verifier_counter];
      v.contract_address = verifier_address;
      v.costs = verifier_cost;
      return verifier_counter++;
  }
}
