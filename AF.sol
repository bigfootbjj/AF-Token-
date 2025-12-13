cd ~/Desktop
cat > AF.sol << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AntiInflationToken {
    string public constant name = "AntiInflation";
    string public constant symbol = "AF";
    uint8 public constant decimals = 18;
    uint256 private constant TOTAL_SUPPLY = 10_000_000 * 10**18;
    uint256 public constant BURN_RATE = 100;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burned(address indexed from, uint256 amount);
    constructor() {_totalSupply = TOTAL_SUPPLY; _balances[msg.sender] = TOTAL_SUPPLY; emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);}
    function totalSupply() public view returns (uint256) {return _totalSupply;}
    function balanceOf(address account) public view returns (uint256) {return _balances[account];}
    function transfer(address to, uint256 amount) public returns (bool) {_transfer(msg.sender, to, amount); return true;}
    function allowance(address owner, address spender) public view returns (uint256) {return _allowances[owner][spender];}
    function approve(address spender, uint256 amount) public returns (bool) {_allowances[msg.sender][spender] = amount; emit Approval(msg.sender, spender, amount); return true;}
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {require(_allowances[from][msg.sender] >= amount); _allowances[from][msg.sender] -= amount; _transfer(from, to, amount); return true;}
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0) && _balances[from] >= amount);
        uint256 burnAmount = (amount * BURN_RATE) / 10_000;
        _balances[from] -= amount; _totalSupply -= burnAmount; emit Burned(from, burnAmount);
        _balances[to] += amount - burnAmount; emit Transfer(from, to, amount - burnAmount);
    }
}
EOF
