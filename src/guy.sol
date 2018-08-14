// Guy - vote w/ a proxy identity; managed by The Hub

pragma solidity ^0.4.24;

import "ds-token/token.sol";
import "ds-chief/chief.sol";
import "./voting.sol";


contract Guy {
    address public owner;
    address public hub;
    Voting public voting;
    DSChief public chief;

    constructor(DSChief chief_, Voting voting_, address owner_) public {
        hub = msg.sender;
        owner = owner_;
        chief = chief_;
        voting = voting_;
        DSToken gov = chief.GOV();
        DSToken iou = chief.IOU();
        gov.approve(chief, uint(-1));
        iou.approve(chief, uint(-1));
        iou.approve(voting, uint(-1));
        gov.approve(hub, uint(-1));
    }

    modifier canExecute() {
        require(msg.sender == owner || msg.sender == hub);
        _;
    }

    function lock(uint amt) public {
        require(msg.sender == hub);
        chief.lock(amt); // mkr out, ious in
        voting.lock(amt); // ious out
    }

    function free(uint amt) public {
        require(msg.sender == hub);
        voting.free(amt); // ious in
        chief.free(amt); // ious out, mkr in
    }

    function voteGov(uint id, bool yay) public canExecute {
        voting.vote(id, yay);
    }

    function retractGov(uint id) public canExecute {
        voting.unSay(id);
    }

    function voteExec(address[] yays) public canExecute returns (bytes32 slate) {
        return chief.vote(yays);
    }

    function voteExec(bytes32 slate) public canExecute {
        chief.vote(slate);
    }

    // function retractExec() public canExecute {
    //     chief.free(chief.deposits(this));
    // }
}