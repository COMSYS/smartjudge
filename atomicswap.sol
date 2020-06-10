pragma solidity ^0.4.26;

import {Verifier, Mediator} from "mediator.sol";

contract AtomicSwap{

    enum ContractState {
        INITIALIZED,
        VERIFYED_CONTRACT,
        SEARCHING,
        CONFIRM_HASH,
        HASH_UPLOAD_TIMEOUT,
        UPLOADED_HASHES,
        HEADER_MISMATCH,
        MATCHING_HASHES,
        FINISHED
    }

    address managmentAddress;

    uint TIMEOUT_BLOCKS = 6 * 60 *24;

    struct Verification{
        Aggreement agreement;
        uint current_height;
        ContractState state;
        //bytes32[] alice_btc_headers;
        bytes32[] btc_headers;
        bytes32[] bob_btc_headers;
        uint16 mined_blocks;
        bytes32 last_hash;
        bytes32 tx_hash;
        //uint16 alice_current_resolving_header;
        uint16 bob_current_resolving_header;
        uint16 left_index;
        uint16 right_index;
        uint16 mid_index;
        bool search_right;
        bytes32 lower_bound_target_hash;
        bytes32 integrityCheck;
        bytes32 block_count_hash;
    }
    struct Aggreement{
        address alice;
        address bob;
        bytes32 btc_starting_block_hash;
        bytes20 btc_receive_addr;
        bytes8 btc_price; // in satoshi
    }

    mapping(uint256 => Verification) verification;
    event addressEvent(address addressStuff);
    event c_accepted(
       uint256 id
    );
    event c_contested(
        uint256 id
    );

    event c_verifyed_contract(
        uint256 id
    );

    event c_hash_upload_timeout(
        uint256 id
    );

    event c_header_mismatch(
        uint256 id
    );

    event c_matching_hashes(
        uint256 id
    );
    event bytesEvent(bytes32 eventStuff);

    event c_finished(
       uint256 id
    );

    event c_asked_for_stake(
        uint256 id
    );
    event next_upload_hash(
        uint256 id
    );

    constructor(address _managmentAddress) public {
      managmentAddress = _managmentAddress;
      emit addressEvent(managmentAddress); 
    }

    function publish_result(uint32 _id, address _honest_party) private{
        Mediator managmentContract = Mediator(managmentAddress);
        managmentContract.verifier_callback(_id, _honest_party);
    }

    function start_verification(address _alice, address _bob, uint32 _id, bytes32 _integrityCheck, bytes32 _block_count_hash) public{

        require(msg.sender == managmentAddress);
        Verification storage v = verification[_id];
        v.agreement.alice = _alice;
        emit addressEvent(v.agreement.alice);
        v.agreement.bob = _bob;
        v.integrityCheck = _integrityCheck;
        v.block_count_hash = _block_count_hash;

        v.current_height = block.number;
        v.state = ContractState.INITIALIZED;
    }

    function verify_agreement(uint32 _id, bytes8 _btc_price, bytes20 _btc_addr, bytes32 _btc_starting_hash, bytes32 _btc_hash_target, uint16 _mined_blocks, bytes32 _last_hash, bytes32 tx_hash)public returns(uint32){
        Verification storage v = verification[_id];
        require(msg.sender == v.agreement.bob);
        require(v.state == ContractState.INITIALIZED);

        bytes32 computed_trade_agreement = sha3(abi.encodePacked(_btc_price, _btc_addr, _btc_starting_hash, _btc_hash_target));
        bytes32 computed_witness = sha3(abi.encodePacked(_mined_blocks, _last_hash));

        if ( computed_trade_agreement == v.integrityCheck && computed_witness == v.block_count_hash && _mined_blocks > 12){
            v.agreement.btc_starting_block_hash = _btc_starting_hash;
            v.agreement.btc_receive_addr = _btc_addr;
            v.agreement.btc_price = _btc_price;
            v.lower_bound_target_hash = _btc_hash_target;
            v.btc_headers = new bytes32[](3);
            v.bob_btc_headers = new bytes32[](7);
            v.mined_blocks = _mined_blocks;
            v.btc_headers[0]= v.agreement.btc_starting_block_hash;
            v.btc_headers[1]=0;
            v.btc_headers[2]=_last_hash;
            v.last_hash=_last_hash;
            v.tx_hash = tx_hash;
            v.current_height = block.number;

            for(uint16 i=0; i < 7; i++){
                v.bob_btc_headers[i]=0;
            }

            v.state = ContractState.VERIFYED_CONTRACT;
        }else{
            publish_result(_id, v.agreement.alice);
        }

    }

    // Alice agrees with Bob's claimed block hashes
    function hashes_ok(uint32 _id)public {
        Verification storage v = verification[_id];
        require(v.state == ContractState.VERIFYED_CONTRACT);
        require(msg.sender == v.agreement.alice);
        v.state = ContractState.MATCHING_HASHES;
    }

    // Alice disagrees with Bob's claimed block hashes
    function search_start(uint32 _id)public {
        Verification storage v = verification[_id];
        require(v.state == ContractState.VERIFYED_CONTRACT);
        require(msg.sender == v.agreement.alice);
        v.right_index = v.mined_blocks;
        v.left_index = 0;
        v.mid_index = v.left_index + ((v.right_index - v.left_index) / 2);
        v.btc_headers[0] = v.agreement.btc_starting_block_hash;
        v.state = ContractState.SEARCHING;
        emit next_upload_hash(v.mid_index);
    }

    function search_claim(uint32 _id, bytes32 _btc_block_hash) public {
        Verification storage v = verification[_id];
        require(v.state == ContractState.SEARCHING);
        require(msg.sender == v.agreement.bob);
        v.btc_headers[1]=_btc_block_hash;
        v.state = ContractState.CONFIRM_HASH;
    }

    function search_partition(uint32 _id, bool _search_right) public{
        Verification storage v = verification[_id];

        require(v.state == ContractState.CONFIRM_HASH);
        require(msg.sender == v.agreement.alice);

        v.search_right = _search_right;
        if(v.search_right){
            v.left_index = v.mid_index;
            v.mid_index = v.left_index + ((v.right_index - v.left_index) / 2);
            v.btc_headers[0] = v.btc_headers[1];
            v.state = ContractState.SEARCHING;
            emit next_upload_hash(v.mid_index);
        }else{
            v.right_index = v.mid_index;
            v.mid_index = v.left_index + ((v.right_index - v.left_index) / 2);
            v.btc_headers[2] = v.btc_headers[1];
            v.state = ContractState.SEARCHING;
            emit next_upload_hash(v.mid_index);
        }
        if (v.left_index + 1 == v.right_index){
            v.bob_current_resolving_header = 1;
            // left should be the last block on which alice and bob agree
            v.bob_btc_headers[0] = v.btc_headers[0];
            v.state = ContractState.HEADER_MISMATCH;
            emit c_header_mismatch(_id);
        }
    }

    function resolve_header_mismatch(uint32 _id, bytes4 _version, bytes32 _prev_block_hash, bytes32 _merkle_root, bytes4 _timestamp, bytes4 _difficulty, bytes4 _nonce) public{
            Verification storage v = verification[_id];
            require(msg.sender == v.agreement.bob);
            require(v.state == ContractState.HEADER_MISMATCH);

            bytes32 uploaded_hash = sha256(sha256(abi.encodePacked(_version, _prev_block_hash, _merkle_root, _timestamp, _difficulty, _nonce)));

            if(v.left_index + v.bob_current_resolving_header == v.mined_blocks){
                if(v.last_hash != uploaded_hash){
                    emit c_finished(4);
                    publish_result(_id, v.agreement.alice);
                    v.state = ContractState.FINISHED;
                }
            } else if(v.left_index + v.bob_current_resolving_header == v.mined_blocks - 6){
                if(v.tx_hash != uploaded_hash){
                    emit c_finished(3);
                    publish_result(_id, v.agreement.alice);
                    v.state = ContractState.FINISHED;
                }
            }

            if(verify_header(_id, v.bob_btc_headers, v.bob_current_resolving_header, uploaded_hash, _prev_block_hash ,v.lower_bound_target_hash)){

                    v.bob_btc_headers[v.bob_current_resolving_header] = uploaded_hash;
                    v.bob_current_resolving_header++;

                    // Bob verified 6 BTC headers following the contented block (or 6 BTC headers following the BTC transaction), ensuring that his chain is the real one
                    if(v.bob_current_resolving_header == v.bob_btc_headers.length || v.left_index + v.bob_current_resolving_header == v.mined_blocks ){
                        publish_result(_id, v.agreement.bob);
                        v.state = ContractState.FINISHED;
                        emit c_finished(0);
                    }
                    
                    emit c_finished(1);

            } else {
                // one of Bob claimed headers is wrong
                publish_result(_id, v.agreement.alice);
                v.state = ContractState.FINISHED;
                emit c_finished(2);
            }
    }

    function verify_header(uint32 _id, bytes32[] storage btc_headers, uint16 index, bytes32 hash, bytes32 prev_block, bytes32 target_hash) private returns (bool verified){

        Verification storage v = verification[_id];

        if( ( index!=0 && v.bob_btc_headers[index - 1] != prev_block) ){
            return false;
        }

        // check target difficulty
        if(is_hash_smaller(hash, target_hash)){
            return true;//(new_hash == btc_headers[index]);
        } else {
            return false;
        }
    }

    function is_hash_smaller(bytes32 hash1, bytes32 hash2) private returns(bool){
       // check which hash is larger without inverting byteorder. Iterate over bytes, starting with most significant byte until they differ. Then check which hash is smaller.
        for(uint8 i=0; i<32; i++){
            uint8 new_hash_byte = uint8(hash1[31-i]) ;
            uint8 target_hash_byte = uint8(hash2[31-i]);

            if( new_hash_byte < target_hash_byte ){
                return true;
            } else if ( new_hash_byte > target_hash_byte ) {
                return false;
            }
        }
        return false;
    }

    /**
     * This function is called by Bob to verify that the right transaction has been mined into the Bitcoin chain.
     * This means that both parties have agreed on the block hashes which were uploaded in a way that
     * the transaction is in 7th last block. To verify that the transaction has actually occured we have to verify _btc_hash_target
     * the transaction depostis the right amount of Btc's into the right wallet and that the tranaction is indeed in the block.
     * Former can be checked by hashing the block header and checking if it has the agreed upon hash and then the merkle root shoud be verifyed.
     * Therefore we upload a hashes of the braches which have to be concatenated with the tranaction hash to create the merkle root.
     *
     *
     * @param   _id                         ID returned by create_contract to identify the referenced contract
     *
     * @param   _version                    The bytes from the bitcoin block
     *
     * @param   _prev_block_hash            The bytes from the bitcoin block
     *
     * @param   _merkle_root                The bytes from the bitcoin block
     *
     * @param   _timestamp                  The bytes from the bitcoin block
     *
     * @param   _difficulty                 The bytes from the bitcoin block
     *
     * @param   _nonce                      The bytes from the bitcoin block
     *
     * @param   _tx                         The transaction in the bitcoin chain
     *
     * @param   _merkle_indices             A binary number (ie 0b101010), where each digit tells us if the hash from the _merkle_root_hashes
     *                                      should be concatenated on the right or left side.
     *
     * @param   _merkle_root_hashes         The hashes of the branches from the merkle tree.
     */
    function verify_tx(uint8 _id, bytes4 _version, bytes32 _prev_block_hash,
        bytes32 _merkle_root, bytes4 _timestamp, bytes4 _difficulty,
        bytes4 _nonce, bytes memory _tx, uint16 _merkle_indices, bytes32[] memory _merkle_root_hashes) public {

        Verification storage v = verification[_id];

        require(msg.sender == v.agreement.bob);
        require(v.state == ContractState.MATCHING_HASHES);

        bytes32 uploaded_hash = sha256(sha256(abi.encodePacked(_version, _prev_block_hash, _merkle_root, _timestamp, _difficulty, _nonce)));

        if( uploaded_hash == v.tx_hash &&
            execute_tx_verification(_id, _version, _prev_block_hash, _merkle_root, _timestamp, _difficulty,
                                    _nonce,  _tx, _merkle_indices, _merkle_root_hashes)){
            publish_result(_id, v.agreement.bob);
            emit bytesEvent(1);
        }else{
            publish_result(_id, v.agreement.alice);
            emit bytesEvent(0);
        }
        v.state = ContractState.FINISHED;
    }

    function execute_tx_verification ( uint8 _id, bytes4 _version, bytes32 _prev_block_hash,
                                        bytes32 _merkle_root, bytes4 _timestamp, bytes4 _difficulty,
                                        bytes4 _nonce, bytes memory _tx, uint16 _merkle_indices, bytes32[] memory _merkle_root_hashes )private returns(bool){

        Verification storage v = verification[_id];

        bytes32 tx_hash = sha256(sha256(_tx));

        if(!verify_merkle_root(tx_hash, _merkle_root_hashes, _merkle_root, _merkle_indices)){
            return false;
        }

        //emit c_debug(0,0,0,0);

        return verify_tx_content(_tx, v.agreement.btc_receive_addr, v.agreement.btc_price);
    }

    // Verify if the tx has an output which transfers at least amount satsoshi to the given address
    function verify_tx_content(bytes memory _tx, bytes20 btc_address, bytes8 amount)private returns (bool){
        uint offset = 0;
        offset += 4;
        if(sha3(_tx[offset], _tx[offset + 1]) == sha3('0001')){
            offset += 2;
        }

        uint number_inputs = uint(_tx[offset]);
        offset+=1;
        while (number_inputs >=1){
            offset += 36;
            offset += 5 + uint(_tx[offset]);
            number_inputs -= 1;
        }
        uint number_outputs = uint(_tx[offset]);
        offset += 1;
        while(number_outputs >= 1){
            //lets check if amount is enough
            bytes32 amount_candidate_bytes = hex"";

            for(uint i = 0; i < 8; i++){
                amount_candidate_bytes |= bytes32(_tx[offset + i] & 0xFF) >> ((24 + i) * 8);
            }

            offset += 8;

            if (uint(amount_candidate_bytes) >= uint(amount)){
                offset += 1;
                bytes32 calculated_btc_address;
                bytes20 hashed_pub_key_candidate;

                if(sha3(_tx[offset]) == sha3(hex'76')){
                    offset += 2;
                    uint data_length = uint(_tx[offset]);
                    offset += 1;

                    hashed_pub_key_candidate = "";
                    for ( i = 0; i < data_length; i++){
                        hashed_pub_key_candidate |= bytes20(_tx[offset + i] & 0xFF) >> (( i + 1) * 8);
                    }
                    offset += data_length;

                    calculated_btc_address = get_btc_address(hashed_pub_key_candidate, data_length);
                    if(calculated_btc_address == btc_address){
                        return true;
                    }
                }
                else if(sha3(_tx[offset]) == sha3(hex'a9')){
                    offset += 1;
                    data_length = uint(_tx[offset]);
                    offset += 1;

                    hashed_pub_key_candidate = "";
                    for ( i = 0; i < data_length; i++){
                        hashed_pub_key_candidate |= bytes20(_tx[offset + i] & 0xFF) >> (( i) * 8);
                    }
                    offset += data_length;
                    if(hashed_pub_key_candidate == btc_address){
                        return true;
                    }
                }
            }
            number_outputs --;
        }

        return false;
    }

    function get_btc_address(bytes32 hashed_pub_key_candidate, uint data_length) private returns(bytes32){
        uint rows;
        uint cols;
        bytes21 test_hash = bytes21(hashed_pub_key_candidate);
        bytes32 checksum = sha256(sha256(test_hash));
        bytes32 hashed_btc_address = hashed_pub_key_candidate;
        for (uint i = 0; i < 4; i++){
            hashed_btc_address |= bytes32(checksum[i] & 0xFF) >> ((data_length + 1 +i) * 8);
        }
        return hashed_btc_address;

    }
    function verify_merkle_root(bytes32 tx_hash, bytes32[] memory hashes, bytes32 old_merkle_root, uint16 _indices)
        private returns(bool verified){
    bytes32 new_merkle_root = calc_merkle_root(tx_hash, hashes, _indices);
    if (new_merkle_root == old_merkle_root){
        return true;
    }
    return false;

    }

    function calc_merkle_root(bytes32 _tx_hash, bytes32[] memory _hashes, uint16 _indices) private returns(bytes32){
        bytes32 current_hash = _tx_hash;


        for (uint8 i = 0; i < _hashes.length; i++){
            bool right = is_right(_indices, i);
            if (right == false){
                bytes32 new_hash = sha256(sha256(abi.encodePacked(_hashes[i], current_hash)));
                current_hash = new_hash;
            }

            else if (right == true){
                current_hash = sha256(sha256(abi.encodePacked(current_hash, _hashes[i])));
            }

        }

        return current_hash;
    }

    function is_right(uint16 _number, uint8 _index) private returns(bool){
        return ( _number & (uint16(1) << (15 - _index)) ) > 0;

    }
}
