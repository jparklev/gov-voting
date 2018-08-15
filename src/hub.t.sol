pragma solidity ^0.4.24;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "ds-chief/chief.sol";
import "./hub.sol";
import "./voting.sol";


contract Voter {
    DSToken gov;
    Voting voting;
    Hub hub;

    constructor(DSToken _gov, Hub _hub) public {
        gov = _gov;
        hub = _hub;
    }

    function approve(uint amt) public {
        gov.approve(hub, amt);
    }

    function lock(uint amt) public {
        hub.lock(amt);
    }

    function free(uint amt) public {
        hub.free(amt);
    }

    function delegate(address guy) public {
        hub.delegate(guy);
    }

    function voteExec(address[] yays) public {
        hub.voteExec(yays);
    }

    function voteGov(uint id, bool yay) public {
        hub.voteGov(id, yay);
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
    address constant c1 = 0x1;
    bytes32 digest;
    uint8 hashFunction;
    uint8 size;

    DSToken gov;
    WarpVoting voting;
    Hub hub;
    DSChief chief;
    Voter dan;
    Voter eli;
    Voter sam;

    function setUp() public {
        gov = new DSToken("GOV");
        DSChiefFab fab = new DSChiefFab();
        chief = fab.newChief(gov, 3);
        voting = new WarpVoting(chief.IOU());
        voting.warp(1 hours, 1);
        hub = new Hub(chief, voting);
        dan = new Voter(gov, hub);
        eli = new Voter(gov, hub);
        sam = new Voter(gov, hub);
        gov.mint(300 ether);
        gov.transfer(dan, 100 ether);
        gov.transfer(eli, 100 ether);
        gov.transfer(sam, 100 ether);
    }
    
    function test_lock_free_lock() public {
        dan.approve(200 ether);
        dan.lock(100 ether);
        assertEq(gov.balanceOf(dan), 0 ether);
        assertEq(chief.deposits(hub.proxies(dan)), 100 ether);
        dan.free(100 ether);
        assertEq(gov.balanceOf(dan), 100 ether);
        assertEq(chief.deposits(hub.proxies(dan)), 0 ether);
        dan.lock(100 ether);
        assertEq(gov.balanceOf(dan), 0 ether);
        assertEq(chief.deposits(hub.proxies(dan)), 100 ether);
    }

    function testFail_free_too_much() public {
        dan.approve(200 ether);
        eli.approve(200 ether);
        dan.lock(100 ether);
        eli.lock(100 ether);
        assertEq(gov.balanceOf(dan), 0 ether);
        assertEq(chief.deposits(hub.proxies(dan)), 100 ether);
        dan.free(101 ether);
    }
    
    function test_delegate() public {
        dan.approve(100 ether);
        eli.approve(100 ether);
        dan.lock(100 ether);
        eli.lock(100 ether);

        assertEq(chief.deposits(hub.proxies(dan)), 100 ether);
        assertEq(chief.deposits(hub.proxies(eli)), 100 ether);

        dan.delegate(eli);
        voting.warp(1 hours, 2); 
        uint _id = voting.createPoll(1, digest, hashFunction, size);

        assertEq(chief.deposits(hub.proxies(dan)), 0 ether);
        assertEq(chief.deposits(hub.proxies(eli)), 200 ether);

        address[] memory yays = new address[](1);
        yays[0] = c1;

        eli.voteExec(yays);
        eli.voteGov(_id, true);
        assertEq(chief.approvals(c1), 200 ether);
        (, , , uint _for, ) = voting.getPoll(_id);
        assertEq(_for, 200 ether);

        dan.free(100 ether);
        assertEq(chief.deposits(hub.proxies(eli)), 100 ether);
        assertEq(chief.approvals(c1), 100 ether);
        (, , , uint for_,) = voting.getPoll(_id);
        assertEq(for_, 200 ether); // uses the amt eli had 1 block before the poll was created
    }
}
