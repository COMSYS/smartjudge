pragma solidity ^0.4.26;

// abstract verifier contract
contract Verifier {
    function start_verification(address alice, address bob, uint32 id, bytes32 initial_agreement, bytes32 witness) public;
    function start_verification(address alice, address bob, uint32 id, bytes32 initial_agreement, bytes32 witness, bytes32 data) public;
}

contract Mediator{

  enum ContractState {
    CREATED,
    ACCEPTED,
    REVEALED,
    CONTENDED,
    WAITING,
    FINISHED
  }

  struct Verification{
    uint256 costs;
    address contract_address;
  }

  struct Agreement{
    ContractState state;
    address alice;
    uint alice_funds;
    address bob;
    uint bob_funds;
    bytes32 agreement_hash;
    uint current_height;
    uint gascost;
  }

  struct Contention{
    bool revealed_data;
    bytes32 witness;
    uint32 verifier_id;
    uint256 verification_fee_made;
  }

  uint256 SECURITY_DEPOSIT = 400000; // 400000 gas worst case costs until verification for Alice
  uint64 TIMEOUT_BLOCKS = 6 * 60 * 24; // 24 hours

  mapping(uint32 => Agreement) agreements;
  mapping(uint32 => Verification) verifications;
  mapping(uint256 => bytes32) data;
  mapping(uint256 => Contention) contentions;

  uint32 verifier_counter = 0;
  uint32 storage_counter = 0;

  event RegisteredVerifer(address indexed _verifier, uint256 indexed _deposit, uint32 _id);
  event TradeID(uint32 _id);

  /**
   * Lets Alice create a new contract based on a hash and returns
   * the id to process this contract. A price higher or equal to
   * the SECURITY_DEPOSIT has to be put in escrow. Everything above the
   * SECURITY_DEPOSIT is the payment to Bob in case that the contract ends gracefully.
   *
   * @param     agreement_hash   Hash of the selected verifier and the initial terms of the contract
   *
   * @return    Id used to process this contract
   **/
   function create(bytes32 agreement_hash) public payable{
       require(msg.value >= SECURITY_DEPOSIT * tx.gasprice);

       Agreement storage a = agreements[storage_counter];

       a.state = ContractState.CREATED;
       a.agreement_hash = agreement_hash;
       a.alice = msg.sender;
       a.alice_funds = SECURITY_DEPOSIT * tx.gasprice;
       a.bob_funds = msg.value - SECURITY_DEPOSIT * tx.gasprice;
       a.current_height = block.number;
       a.gascost = tx.gasprice;

       emit TradeID(storage_counter);
       storage_counter++;
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
   * @param agreement_hash  Hash of the selected verifier and the initial terms of the contract
   **/
   function create(uint32 id, bytes32 agreement_hash) public payable{
       Agreement storage a = agreements[id];

       require(msg.value >= SECURITY_DEPOSIT * tx.gasprice);
       require(a.state == ContractState.FINISHED);

       a.state = ContractState.CREATED;
       a.agreement_hash = agreement_hash;
       a.alice = msg.sender;
       a.alice_funds = SECURITY_DEPOSIT * tx.gasprice;
       a.bob_funds = msg.value - SECURITY_DEPOSIT * tx.gasprice;
       a.current_height = block.number;
   }

  /**
   * This function lets Alice cancel a contract as long as no one accepted it beforehand.
   *
   * @param id              The id of the processed contract
   **/
   function abort(uint32 id) public{
       Agreement storage a = agreements[id];

       require(msg.sender == a.alice);
       require(a.state == ContractState.CREATED);

       a.alice.transfer(a.alice_funds + a.bob_funds);
       a.state = ContractState.FINISHED;
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

       Agreement storage a = agreements[id];

       require(a.state == ContractState.CREATED);
       require(msg.value >= SECURITY_DEPOSIT * tx.gasprice);

       a.bob = msg.sender;
       a.bob_funds += msg.value;
       a.current_height = block.number;
       a.state = ContractState.ACCEPTED;
   }

  /**
   * This function lets Alice end a contract gracefully.
   * This pays out Bob the promised amount and both parties
   * recover their deposits.
   *
   * @param id              The id of the processed contract
   **/
   function finish(uint32 id) public{

       Agreement storage a = agreements[id];

       require(a.state == ContractState.ACCEPTED || a.state == ContractState.REVEALED || a.state == ContractState.CONTENDED);
       require(msg.sender == a.alice);

       a.alice.transfer(a.alice_funds);
       a.bob.transfer(a.bob_funds);
       a.state = ContractState.FINISHED;
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

       Agreement storage a = agreements[id];

       require(a.state == ContractState.ACCEPTED);
       require(msg.sender == a.bob);

       data[id] = revealed_data;
       a.current_height = block.number;
       a.state = ContractState.REVEALED;

       uint256 fees = (gas_beginning - gasleft() + 28000) * tx.gasprice/2;
       if(fees > a.alice_funds){
           fees = a.alice_funds;
       }

       a.alice_funds -= fees;
       a.bob_funds += fees;
   }

  /**
   * This function lets Bob contend an execution.
   * He has to make a deposit which matches the indicated cost of the verifier,
   * which is checked later. To incentive both parties to do so,
   * the cost of the execution of this function are split between both users.
   *
   * @param id              The id of the processed contract
   * @param witness        Evidence brought forward by Bob
   **/
   function contest(uint32 id, bytes32 witness) payable public {

      uint256 gas_beginning = gasleft();

      Agreement storage a = agreements[id];
      Contention storage cont = contentions[id];

      require(msg.sender == a.bob);
      require(a.state == ContractState.ACCEPTED || a.state == ContractState.REVEALED);

      cont.revealed_data = (a.state == ContractState.REVEALED);

      cont.witness = witness;
      cont.verification_fee_made = msg.value/a.gascost;

      a.bob_funds += msg.value;
      a.current_height = block.number;
      a.state = ContractState.CONTENDED;

      uint256 fees = (gas_beginning - gasleft() + 28000) * tx.gasprice/2;
      if(fees > a.alice_funds){
          fees = a.alice_funds;
      }

      a.alice_funds -= fees;
      a.bob_funds += fees;
   }


  /**
   * This function lets Alice initate the verification process, by revealing the inital plaintext agreement.
   * She has to make her deposit and the value of the depostis of both parties are checked.
   * Afterwards the control is delegated to the selected verifier.
   *
   * @param id              The id of the processed contract
   * @param verifier_id     The registration id of the agreed upon verifer
   * @param initial_witness   The initally agreed upon state by both participants
   **/
  function init_verification(uint32 id, uint32 verifier_id, bytes32 initial_witness) payable public {

    Agreement storage a = agreements[id];

    require(msg.sender == a.alice);
    require(a.state == ContractState.CONTENDED);

    a.alice_funds += msg.value;

    if( a.agreement_hash == sha3(abi.encodePacked(verifier_id, initial_witness)) ){

        contentions[id].verifier_id = verifier_id;
        Verifier used_verifier = Verifier(verifications[verifier_id].contract_address);

        if(contentions[id].verification_fee_made != verifications[verifier_id].costs){
          a.alice.transfer(a.bob_funds + a.alice_funds);
          a.state = ContractState.FINISHED;
          return;
        }

        if(msg.value/a.gascost != verifications[verifier_id].costs){
          a.bob.transfer(a.bob_funds + a.alice_funds);
          a.state = ContractState.FINISHED;
          return;
        }
        
        if(contentions[id].revealed_data){
          used_verifier.start_verification(a.alice, a.bob, id, initial_witness, contentions[id].witness, data[id]);
        } else {
          used_verifier.start_verification(a.alice, a.bob, id, initial_witness, contentions[id].witness);
        }
        
        a.state = ContractState.WAITING;

    } else {

        a.bob.transfer(a.alice_funds + a.bob_funds);
        a.state = ContractState.FINISHED;

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

       Agreement storage a = agreements[id];

       require(a.state == ContractState.WAITING);
       require(msg.sender == verifications[contentions[id].verifier_id].contract_address);

       if(honest_party == a.bob)
         a.bob.transfer(a.bob_funds + a.alice_funds);
       else
         a.alice.transfer(a.bob_funds + a.alice_funds);

       a.state = ContractState.FINISHED;
   }

  /**
   * This function allows Alice or Bob to timeout the other party when applicable.
   *
   * @param id              The id of the processed contract
   **/
   function timeout(uint32 id) public{

        Agreement storage a = agreements[id];

        require( (msg.sender == a.alice && (a.state == ContractState.ACCEPTED || a.state == ContractState.REVEALED))
                 || (msg.sender == a.bob && a.state == ContractState.CONTENDED));

         require( a.current_height + TIMEOUT_BLOCKS >= block.number );

         msg.sender.transfer(a.bob_funds + a.alice_funds);
         a.state = ContractState.FINISHED;
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
   function register_verifier(address verifier_address, uint256 verifier_cost) public{
       Verification storage v = verifications[verifier_counter];
       v.contract_address = verifier_address;
       v.costs = verifier_cost;
       emit RegisteredVerifer(verifier_address, verifier_cost, verifier_counter);
       verifier_counter++;
   }
}
