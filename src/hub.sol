// The Hub - delegate votes and manage your proxy voting identity

pragma solidity ^0.4.24;

import "ds-token/token.sol";
import "ds-chief/chief.sol";
import "./guy.sol";
import "./voting.sol";

contract Hub is DSMath {
    DSToken public gov;
    DSToken public iou;
    Voting public voting;
    DSChief public chief;
    mapping(address => address) public delegations;
    mapping(address => uint) public deposits;
    mapping(address => Guy) public proxies;
    mapping(address => bool) public delegates;
    mapping(address => bool) public standards;

    constructor(DSChief _chief, Voting _voting) { 
        chief = _chief; 
        voting = _voting;
        gov = chief.GOV();
        iou = chief.IOU();
    }

    event ProxyCreated(address src, address proxy);
    event Delegated(
        address src, 
        address delegate, 
        Guy prevProxy, 
        Guy currProxy, 
        uint weight
    );

    function lock(uint wad) public {
        require(wad > 0, "must lock some positive number of votes");
        address lad = delegating(msg.sender) ? 
            delegations[msg.sender] : msg.sender;
        if (!hasProxy(lad)) createProxy(lad);
        gov.move(msg.sender, proxies[lad], wad);
        proxies[lad].lock(wad);
        deposits[msg.sender] = add(deposits[msg.sender], wad);
    }

    function free(uint wad) public {
        require(deposits[msg.sender] >= wad, "trying to free more votes than you have a claim to");
        address lad = delegating(msg.sender) ? 
            delegations[msg.sender] : msg.sender;
        proxies[lad].free(wad);
        gov.move(proxies[lad], msg.sender, wad);
        deposits[msg.sender] = sub(deposits[msg.sender], wad);
    }

    function delegate(address guy) public {
        require(delegations[msg.sender] != guy, "already delegating to this voter");
        require(hasProxy(msg.sender), "no votes to delegate");
        if (!hasProxy(guy)) createProxy(guy); // make a proxy for the delegate if none exists
        address lad = delegating(msg.sender) ? 
            delegations[msg.sender] : msg.sender;
        proxies[lad].free(deposits[msg.sender]);
        gov.move(proxies[lad], proxies[guy], deposits[msg.sender]);
        proxies[guy].lock(deposits[msg.sender]);
        delegations[msg.sender] = guy == msg.sender ? address(0) : guy;
        emit Delegated(msg.sender, guy, proxies[lad], proxies[guy], deposits[msg.sender]);
    }

    function voteExec(address[] yays) public {
        require(canVote(msg.sender), "must have proxy & cannot be delegating vote");
        proxies[msg.sender].voteExec(yays);
    }

    function voteGov(uint id, bool yay) public {
        require(canVote(msg.sender), "must have proxy & cannot be delegating vote");
        proxies[msg.sender].voteGov(id, yay);
    }

    // Internal -----------------------------------------------------

    function createProxy(address _guy) internal {
        proxies[_guy] = new Guy(chief, voting, _guy);
        emit ProxyCreated(_guy, proxies[_guy]);
    }

    function canVote(address _guy) internal returns (bool) {
        return (!delegating(_guy) && hasProxy(_guy));
    }

    function delegating(address _guy) internal returns (bool) {
        return delegations[_guy] != address(0);
    }

    function hasProxy(address _guy) internal returns (bool) {
        return proxies[_guy] != address(0);
    }
}