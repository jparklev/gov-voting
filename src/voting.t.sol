pragma solidity ^0.4.24;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./voting.sol";


contract Voter {
    DSToken gov;
    Voting voting;

    constructor(DSToken _gov, Voting _voting) public {
        gov = _gov;
        voting = _voting;
    }

    function approve(uint amt) public {
        gov.approve(voting, amt);
    }

    function lock(uint amt) public {
        voting.lock(amt);
    }

    function free(uint amt) public {
        voting.free(amt);
    }

    function vote(uint amt, bool _for) public {
        voting.vote(amt, _for);
    }

    function unSay(uint id) public {
        voting.unSay(id);
    }
}


contract WarpVoting is Voting {
    uint48 _era; uint32 _age;
    function warp(uint48 era_, uint32 age_) public { _era = era_; _age = age_; }
    function era() public view returns (uint48) { return _era; } 
    function age() public view returns (uint32) { return _age; }       
    constructor(DSToken _gov) public Voting(_gov) {}
}


contract VotingTest is DSTest {
    bytes32 digest;
    uint8 hashFunction;
    uint8 size;

    DSToken gov;
    WarpVoting voting;
    Voter dan;
    Voter eli;

    function setUp() public {
        gov = new DSToken("GOV");
        voting = new WarpVoting(gov);
        voting.warp(1 hours, 1);
        dan = new Voter(gov, voting);
        eli = new Voter(gov, voting);
        gov.mint(200 ether);
        gov.transfer(dan, 100 ether);
        gov.transfer(eli, 100 ether);
    }

    function test_lock_free() public { // 543,912
        dan.approve(100 ether);
        dan.lock(100 ether);
        assertEq(gov.balanceOf(dan), 0 ether);
        assertEq(gov.balanceOf(voting), 100 ether);
        dan.free(100 ether);
        assertEq(gov.balanceOf(dan), 100 ether);
        assertEq(gov.balanceOf(voting), 0 ether);
    }

    function test_create_poll() public {
        dan.approve(100 ether);
        dan.lock(100 ether);
        uint _id = voting.createPoll(1, digest, hashFunction, size);
        (, uint48 _end, , uint _votesFor, uint _votesAgainst) = voting.getPoll(_id);
        require(_end == 1 hours + 1 days);
        assertEq(_votesFor, 0 ether);
        assertEq(_votesAgainst, 0 ether);
    }

    function test_cast_switch_withdraw() public {
        dan.approve(100 ether);
        dan.lock(100 ether);
        voting.warp(2 hours, 2); 
        uint _id = voting.createPoll(1, digest, hashFunction, size);
        // cast vote
        dan.vote(_id, true);
        (, , , uint _votesFor, uint _votesAgainst) = voting.getPoll(_id);
        assertEq(_votesFor, 100 ether);
        assertEq(_votesAgainst, 0 ether);
        // switch vote
        dan.vote(_id, false);
        (, , , uint votesFor_, uint votesAgainst_) = voting.getPoll(_id);
        assertEq(votesFor_, 0 ether);
        assertEq(votesAgainst_, 100 ether);
        // withdraw vote
        dan.unSay(_id);
        (, , , uint _votesFor_, uint _votesAgainst_) = voting.getPoll(_id);
        assertEq(_votesFor_, 0 ether);
        assertEq(_votesAgainst_, 0 ether);
    }

    function test_multi_warp() public {
        dan.approve(100 ether);
        eli.approve(100 ether);

        dan.lock(25 ether);
        eli.lock(50 ether);
        voting.warp(2 hours, 2); 

        uint _id = voting.createPoll(1, digest, hashFunction, size);
        dan.vote(_id, true);
        eli.vote(_id, true);
        (, , , uint _votesFor, uint _votesAgainst) = voting.getPoll(_id);
        assertEq(_votesFor, 75 ether);
        assertEq(_votesAgainst, 0 ether);

        dan.lock(50 ether);
        voting.warp(12 hours, 12); 
        dan.vote(_id, false);
        (, , , uint votesFor_, uint votesAgainst_) = voting.getPoll(_id);
        assertEq(votesFor_, 50 ether);
        assertEq(votesAgainst_, 25 ether);

        uint id_ = voting.createPoll(2, digest, hashFunction, size);
        dan.vote(id_, true);
        eli.vote(id_, true);
        (, , , uint _votesFor_, uint _votesAgainst_) = voting.getPoll(id_);
        assertEq(_votesFor_, 125 ether);
        assertEq(_votesAgainst_, 0 ether);
        dan.free(75 ether);
        assertEq(gov.balanceOf(dan), 100 ether);
        dan.vote(id_, false);
        (, , , uint __votesFor, uint __votesAgainst) = voting.getPoll(id_);
        assertEq(__votesFor, 50 ether);
        assertEq(__votesAgainst, 75 ether);
    }

    function testFail_poll_expires_vote() public {
        dan.approve(100 ether);
        dan.lock(100 ether);
        uint _id = voting.createPoll(1, digest, hashFunction, size);
        voting.warp(2 days, 2); 
        dan.vote(_id, true);
    }

    function testFail_poll_expires_withdraw() public {
        dan.approve(100 ether);
        dan.lock(100 ether);
        uint _id = voting.createPoll(1, digest, hashFunction, size);
        voting.warp(2 days, 2); 
        dan.unSay(_id);
    }

    function testFail_fake_poll_vote() public {
        dan.approve(100 ether);
        dan.lock(100 ether);
        voting.warp(2 hours, 2); 
        voting.createPoll(1, digest, hashFunction, size);
        dan.vote(200, true);
    }

    function testFail_fake_poll_withdraw() public {
        dan.approve(100 ether);
        dan.lock(100 ether);
        voting.warp(2 hours, 2); 
        voting.createPoll(1, digest, hashFunction, size);
        dan.unSay(200);
    }
}
