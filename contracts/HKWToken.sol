// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title HKW TRC20 Token
/// @notice Fixed max supply (no minting; totalSupply is not reduced by burns).
///         Transfer tax: transfer / transferFrom take 0.01% and send it to the
///         zero address (capped at 10,000 HKW per transfer). DEX pair-related
///         transfers are tax-exempt so AMM reserves stay correct.
///         Anyone may burn by transferring to the zero address. There is no
///         admin burn entrypoint.
///         `totalBurned` accumulates all units credited to the zero address
///         (explicit burns + transfer-tax burns) for off-chain / hook readers.
///         Owner may only register pairs; cannot mint or change tax.
contract HKWToken {
    string public constant name = "hkw.com";
    string public constant symbol = "HKW";
    uint8 public constant decimals = 6;

    // Max / initial supply: 10,000,000,000 HKW (10B, decimals=6) — burns do not reduce this figure
    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 * 10 ** 6;

    /// @notice Transfer tax: 0.01% (1 / 10_000)
    uint256 public constant TRANSFER_TAX_BPS = 1;
    uint256 public constant TRANSFER_TAX_DENOM = 10_000;

    /// @notice Per-transfer tax cap: 10,000 HKW
    uint256 public constant MAX_TRANSFER_TAX = 10_000 * 10 ** 6;

    uint256 public totalSupply;
    /// @notice Cumulative amount sent to the zero address (explicit + tax burns)
    uint256 public totalBurned;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;
    mapping(address => bool) public isDexPair;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed burner, uint256 amount, uint256 timestamp);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event DexPairUpdated(address indexed pair, bool enabled);

    modifier onlyOwner() {
        require(msg.sender == owner, "HKW: not owner");
        _;
    }

    constructor(address initialHolder) {
        require(initialHolder != address(0), "HKW: zero holder");
        owner = initialHolder;

        totalSupply = TOTAL_SUPPLY;
        balanceOf[initialHolder] = TOTAL_SUPPLY;
        emit Transfer(address(0), initialHolder, TOTAL_SUPPLY);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HKW: zero owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Register or unregister a DEX pair (pair path is transfer-tax exempt)
    function setDexPair(address pair, bool enabled) external onlyOwner {
        require(pair != address(0), "HKW: zero pair");
        isDexPair[pair] = enabled;
        emit DexPairUpdated(pair, enabled);
    }

    /// @dev Tax due: min(value / 10000, 10_000 HKW); tiny amounts may round to 0
    function _taxAmount(uint256 value) internal pure returns (uint256) {
        uint256 tax = (value * TRANSFER_TAX_BPS) / TRANSFER_TAX_DENOM;
        if (tax > MAX_TRANSFER_TAX) {
            tax = MAX_TRANSFER_TAX;
        }
        return tax;
    }

    function _burnToZero(address from, uint256 amount) internal {
        if (amount == 0) return;
        balanceOf[address(0)] += amount;
        totalBurned += amount;
        emit Transfer(from, address(0), amount);
        emit Burn(from, amount, block.timestamp);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "HKW: transfer from zero");
        require(balanceOf[from] >= value, "HKW: insufficient balance");

        // DEX in/out tax-exempt; full burn to zero address with no extra tax
        bool taxExempt = (to == address(0)) || isDexPair[from] || isDexPair[to];
        uint256 tax = taxExempt ? 0 : _taxAmount(value);
        uint256 sendAmount = value - tax;

        balanceOf[from] -= value;

        if (to == address(0)) {
            // Explicit burn: entire sendAmount goes to zero (tax is always 0 on this path)
            totalBurned += sendAmount;
            balanceOf[address(0)] += sendAmount;
            emit Transfer(from, address(0), sendAmount);
            emit Burn(from, sendAmount, block.timestamp);
        } else {
            balanceOf[to] += sendAmount;
            emit Transfer(from, to, sendAmount);
            if (tax > 0) {
                _burnToZero(from, tax);
            }
        }
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(allowance[from][msg.sender] >= value, "HKW: allowance exceeded");
        allowance[from][msg.sender] -= value;
        _transfer(from, to, value);
        return true;
    }
}
