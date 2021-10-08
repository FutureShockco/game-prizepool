pragma solidity ^0.5.7;

import "./ERC20Standard.sol";

contract CWDToken is ERC20Standard {
	constructor(string memory _name, string memory _symbol, uint256 _totalSupply) public {
		totalSupply = _totalSupply;
		name = _name;
		decimals = 18;
		symbol = _symbol;
		balances[msg.sender] = totalSupply;
	}
}
