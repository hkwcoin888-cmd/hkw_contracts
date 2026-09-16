// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface ISunswapV1Factory {
    function getExchange(address token) external view returns (address payable);
}

interface ISunswapV1Exchange {
    function factoryAddress() external view returns (address);
    function tokenAddress() external view returns (address);
}

interface ISunswapV2Pair {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface ISunswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface ISunswapV3Pool {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

interface ISunswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/// @title HKW TRC20 Token
/// @notice Fixed max supply (no minting; totalSupply is not reduced by burns).
///         Transfer tax: transfer / transferFrom take 0.01% and send it to the
///         zero address (capped at 10,000 HKW per transfer).
///         Official SunSwap V1 / V1.5 / V2 / V3 pools and the V4 PoolManager are
///         tax-exempt (auto-detected against canonical factories / singleton;
///         no owner pair registry).
///         Anyone may burn by transferring to the zero address. There is no
///         admin burn entrypoint.
///         `totalBurned` accumulates all units credited to the zero address
///         (explicit burns + transfer-tax burns) for off-chain / hook readers.
///         Owner may only transfer / renounce ownership; cannot mint, change
///         tax, or register pairs.
contract HKWToken {
    string public constant name = "Hero Knowledge World";
    string public constant symbol = "HKW";
    uint8 public constant decimals = 6;

    // Max / initial supply: 10,000,000,000 HKW (10B, decimals=6) — burns do not reduce this figure
    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 * 10 ** 6;

    /// @notice Transfer tax: 0.01% (1 / 10_000)
    uint256 public constant TRANSFER_TAX_BPS = 1;
    uint256 public constant TRANSFER_TAX_DENOM = 10_000;

    /// @notice Per-transfer tax cap: 10,000 HKW
    uint256 public constant MAX_TRANSFER_TAX = 10_000 * 10 ** 6;

    /// @notice Canonical SunSwap factories / singleton (TRON mainnet)
    /// V1  TXk8rQSAvPvBBNtqSoY6nCfsXWCSSpTVQF
    address public constant SUNSWAP_V1_FACTORY = address(0xeEd9e56a5CdDaA15eF0C42984884a8AFCf1BdEbb);
    /// V1.5 TB2LM4iegvhPJGWn9qizeefkPMm7bqqaMs
    address public constant SUNSWAP_V1_5_FACTORY = address(0x0b8f8141A15e48de6f406f3Ec32DaF9a983EadC3);
    /// V2  TKWJdrQkqHisa1X8HUdHEfREvTzw4pMAaY
    address public constant SUNSWAP_V2_FACTORY = address(0x689AbaeeEd3F0BB3585773192e23224CAC25Dd41);
    /// V3  TThJt8zaJzJMhCEScH7zWKnp5buVZqys9x
    address public constant SUNSWAP_V3_FACTORY = address(0xC2708485c99cd8cF058dE1a9a7e3C2d8261a995C);
    /// V4 PoolManager TVjuTE3V5bMVdpfNhid8kD2v35T2k1u1Br
    address public constant SUNSWAP_V4_POOL_MANAGER = address(0xD8dE75898a30b097Da826464e932934A512C7be3);

    uint256 public totalSupply;
    /// @notice Cumulative amount sent to the zero address (explicit + tax burns)
    uint256 public totalBurned;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed burner, uint256 amount, uint256 timestamp);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

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

    /// @notice Renounce ownership (irreversible). Prefer over leaving a live admin key.
    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    /// @notice True if `account` is an official SunSwap venue for this token (V1–V4).
    function isSunswapDex(address account) public view returns (bool) {
        if (account == address(0)) {
            return false;
        }
        // V4 singleton: all CL pools settle through PoolManager
        if (account == SUNSWAP_V4_POOL_MANAGER) {
            return true;
        }
        if (account.code.length == 0) {
            return false;
        }
        if (_isV2Pair(account) || _isV3Pool(account) || _isV1Exchange(account)) {
            return true;
        }
        return false;
    }

    function _isV2Pair(address account) internal view returns (bool) {
        try ISunswapV2Pair(account).factory() returns (address factory) {
            if (factory != SUNSWAP_V2_FACTORY) {
                return false;
            }
            address t0 = ISunswapV2Pair(account).token0();
            address t1 = ISunswapV2Pair(account).token1();
            if (t0 != address(this) && t1 != address(this)) {
                return false;
            }
            return ISunswapV2Factory(factory).getPair(t0, t1) == account;
        } catch {
            return false;
        }
    }

    function _isV3Pool(address account) internal view returns (bool) {
        try ISunswapV3Pool(account).factory() returns (address factory) {
            if (factory != SUNSWAP_V3_FACTORY) {
                return false;
            }
            address t0 = ISunswapV3Pool(account).token0();
            address t1 = ISunswapV3Pool(account).token1();
            if (t0 != address(this) && t1 != address(this)) {
                return false;
            }
            uint24 fee = ISunswapV3Pool(account).fee();
            return ISunswapV3Factory(factory).getPool(t0, t1, fee) == account;
        } catch {
            return false;
        }
    }

    function _isV1Exchange(address account) internal view returns (bool) {
        try ISunswapV1Exchange(account).factoryAddress() returns (address factory) {
            if (factory != SUNSWAP_V1_FACTORY && factory != SUNSWAP_V1_5_FACTORY) {
                return false;
            }
            address token = ISunswapV1Exchange(account).tokenAddress();
            if (token != address(this)) {
                return false;
            }
            return address(ISunswapV1Factory(factory).getExchange(address(this))) == account;
        } catch {
            return false;
        }
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

        // Official SunSwap V1–V4 path tax-exempt; full burn to zero with no extra tax
        bool taxExempt = (to == address(0)) || isSunswapDex(from) || isSunswapDex(to);
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
