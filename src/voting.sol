// Voting – create expiring straw polls 

pragma solidity ^0.4.24;

import "ds-thing/thing.sol";
import "ds-token/token.sol";


contract Voting is DSMath {
    uint public id_;
    DSToken public gov; 
    mapping(uint => Poll) public polls;    
    mapping(address => Checkpoint[]) public deposits;

    // idea credit Aragon
    enum VoterStatus { Absent, Yay, Nay }
    
    struct Checkpoint {
        uint128 fromBlock;
        uint128 value;
    }

    struct Multihash {
        bytes32 digest;
        uint8 hashFunction;
        uint8 size;
    }

    struct Poll {
        uint48 start;
        uint48 end;            
        uint yays;		 
        uint nays; 
        uint32 frozenAt;
        address[] voters;
        Multihash ipfsHash;
        mapping(address => VoterStatus) votes; 
    }

    event PollCreated(address src, uint48 start, uint48 end, uint32 frozenAt, uint id);
    event Voted(address src, uint id, bool yay, uint weight);
    event UnSaid(address src, uint id, uint weight);

    constructor(DSToken _gov) { gov = _gov; }

    function era() public view returns (uint48) { return uint48(now); }
    function age() public view returns (uint32) { return uint32(block.number); }

    function lock(uint wad) public {
        gov.pull(msg.sender, wad);
        updateDeposits(deposits[msg.sender], add(getDeposits(msg.sender), wad));
    }

    function free(uint wad) public {
        gov.push(msg.sender, wad);
        updateDeposits(deposits[msg.sender], sub(getDeposits(msg.sender), wad));
    }

    function pollExists(uint _id) public view returns (bool) {
        return (_id != 0 && _id <= id_);
    }

    function pollIsActive(uint _id) public view returns (bool) {
        return (era() >= polls[_id].start && era() < polls[_id].end);
    }

    function getPoll(uint _id) public view returns (uint48, uint48, uint32, uint, uint) {
        require(pollExists(_id));
        return (
            polls[_id].start, 
            polls[_id].end, 
            polls[_id].frozenAt, 
            polls[_id].yays, 
            polls[_id].nays
        );
    }
    
    function getVoterStatus(uint _id, address _guy) public view returns (VoterStatus status, uint weight) {
        // status codes -> 0 := not voting, 1 := voting yay, 2 := voting nay
        return (polls[_id].votes[_guy], depositsAt(_guy, polls[_id].frozenAt));
    }

    // this gets us "top supporters" info on the frontend
    // unfortunately we have to add the voters array just to get it
    // maybe better to leave this to a caching layer and save the gas?
    function getVoters(
        uint _id, 
        uint _offset, 
        uint _limit
    ) public view returns (address[], VoterStatus[], uint[]) {
        Poll storage poll = polls[_id];
        if (_offset < poll.voters.length) {
            uint i = 0;
            uint resultLength = poll.voters.length - _offset > _limit ? _limit : poll.voters.length - _offset;
            address[]     memory _voters   = new address[](resultLength);
            VoterStatus[] memory _votes = new VoterStatus[](resultLength);
            uint[]        memory _weights  = new uint[](resultLength);
            for (uint j = _offset; (j < poll.voters.length) && (i < _limit); j++) {
                _voters[j]   = poll.voters[j];
                _votes[j] = poll.votes[msg.sender];
                _weights[j]  = depositsAt(_voters[j], poll.frozenAt); i++;
            }
            return(_voters, _votes, _weights);
        }
    }

    function getMultiHash(uint _id) public view returns (bytes32, uint8, uint8) {
        require(pollExists(_id));
        return (
            polls[_id].ipfsHash.digest, 
            polls[_id].ipfsHash.hashFunction, 
            polls[_id].ipfsHash.size
        );
    }

    function createPoll(
        uint32 _tillStart,
        uint32 _tillEnd,
        bytes32 _digest, 
        uint8 _hashFunction, 
        uint8 _size
    ) public returns (uint) {
        require(_tillStart < _tillEnd);
        uint id = ++id_;
        uint48 _start = uint48(add(era(), mul(_tillStart, 1 days)));
        uint48 _end = uint48(add(era(), mul(_tillEnd, 1 days)));
        uint32 _frozenAt = age() - 1;
        polls[id] = Poll({
            start: _start,
            end: _end,
            yays: 0,
            nays: 0,
            voters: new address[](0),
            frozenAt: _frozenAt,
            ipfsHash: Multihash(_digest, _hashFunction, _size)
        });
        emit PollCreated(msg.sender, _start, _end, _frozenAt, id);
        return id;
    }
    
    function vote(uint _id, bool _yay) public {
        require(pollExists(_id));
        require(pollIsActive(_id));
        uint weight = depositsAt(msg.sender, polls[_id].frozenAt);
        require(weight > 0);
        subWeight(weight, msg.sender, polls[_id]);
        addWeight(weight, msg.sender, polls[_id], _yay);
        emit Voted(msg.sender, _id, _yay, weight);
    }
             
    function unSay(uint _id) public {
        require(pollExists(_id));
        require(pollIsActive(_id));
        uint weight = depositsAt(msg.sender, polls[_id].frozenAt);
        require(weight > 0);
        subWeight(weight, msg.sender, polls[_id]);
        emit UnSaid(msg.sender, _id, weight);
    }

    function getDeposits(address _guy) public view returns (uint) {
        return depositsAt(_guy, age());
    }

    // logic adapted from the minime token https://github.com/Giveth/minime –> credit Jordi Baylina
    function depositsAt(address _guy, uint _block) public view returns (uint) {
        Checkpoint[] storage checkpoints = deposits[_guy];
        if (checkpoints.length == 0) return 0;
        if (_block >= checkpoints[checkpoints.length - 1].fromBlock)
            return checkpoints[checkpoints.length - 1].value;
        if (_block < checkpoints[0].fromBlock) return 0;
        uint min = 0;
        uint max = checkpoints.length - 1;
        while (max > min) {
            uint mid = (max + min + 1) / 2;
            if (checkpoints[mid].fromBlock <= _block) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return checkpoints[min].value;
    }

    // Internal -----------------------------------------------------

    function updateDeposits(Checkpoint[] storage checkpoints, uint _value) internal {
        if ((checkpoints.length == 0) || (checkpoints[checkpoints.length - 1].fromBlock < age())) {
            Checkpoint storage newCheckPoint = checkpoints[checkpoints.length++];
            newCheckPoint.fromBlock = age();
            newCheckPoint.value = uint128(_value);
        } else {
            Checkpoint storage oldCheckPoint = checkpoints[checkpoints.length - 1];
            oldCheckPoint.value = uint128(_value);
        }
    }

    function subWeight(uint _weight, address _guy, Poll storage poll) internal {
        if (poll.votes[_guy] == VoterStatus.Absent) return;
        if (poll.votes[_guy] == VoterStatus.Yay) poll.yays = sub(poll.yays, _weight);
        else if (poll.votes[_guy] == VoterStatus.Nay) poll.nays = sub(poll.nays, _weight);
        poll.votes[_guy] = VoterStatus.Absent;
    }

    function addWeight(uint _weight, address _guy, Poll storage poll, bool _yay) internal {
        if (_yay) poll.yays = add(poll.yays, _weight);
        else poll.nays = add(poll.nays, _weight);
        poll.votes[_guy] = _yay ? VoterStatus.Yay : VoterStatus.Nay;
        poll.voters.push(_guy);
    }
}