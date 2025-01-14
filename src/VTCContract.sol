pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RVTC is ERC20, Ownable, ReentrancyGuard {
  uint256 public constant INITIAL_SUPPLY = 1000 * 10 ** 18;
  uint256 public constant TOKEN_PER_LICENSE = 1000 * 10 ** 18;
  uint256 public totalLicensesMinted;
  uint256 public constant MIN_DEPOSIT = 10; // Minimum 10 tokens
  uint256 public totalLockedTokens;
  uint256 public cumulativeProfitPerToken; // Global cumulative profit per token
  uint256 public feePercent = 10;
  uint256 public nextLicenseId;
  address public treasury;
  address public rendinex;
  address[] public usersWhoLockedTokens;

  mapping(uint256 => License) public licenses;
  mapping(address => uint256) public usdtWithdrawable;
  mapping(address => uint256) public lastCumulativeProfitPerToken; // Tracks each holder's last withdraw
  mapping(address => uint256) public withdrawable; // Withdrawable profits for each user
  mapping(address => uint256) public lockedTokens;
  mapping(address => bool) public hasLockedTokens;
  mapping(address => uint256) private _balances;

  struct License {
    uint256 fundingGoal;
    uint256 fundsRaised;
    bool fundingCompleted;
  }

  IERC20 public usdtToken;

  event TokensDeposited(address indexed user, uint256 amount);
  event SaleFinalized();
  event LicenseMinted(uint256 indexed licenseId, uint256 fundingGoal);
  event LicensePurchased(
    address indexed buyer,
    uint256 indexed licenseId,
    uint256 amount
  );
  event TokensWithdrawed(address indexed withdrawer, uint256 amount);
  event USDTDeposited(uint256 amount);
  event FeesDistributed(uint256 treasuryFee, uint256 rendinexFee);

  constructor(
    address _usdtToken,
    address _treasury,
    address _rendinex
  ) Ownable(msg.sender) ERC20("RVTC", "RVTC") {
    _mint(msg.sender, INITIAL_SUPPLY);
    usdtToken = IERC20(_usdtToken);
    treasury = _treasury;
    rendinex = _rendinex;
  }

  function mintLicense(uint256 fundingGoal) external onlyOwner {
    require(fundingGoal > 0, "Funding goal must be greater than zero");

    uint256 licenseId = nextLicenseId++;
    licenses[licenseId] = License({
      fundingGoal: fundingGoal,
      fundsRaised: 0,
      fundingCompleted: false
    });

    _mint(address(this), TOKEN_PER_LICENSE);
    totalLicensesMinted += 1;

    emit LicenseMinted(licenseId, fundingGoal);
  }

  function distributeProfits(uint256 amount) external onlyOwner {
    require(totalSupply() > 0, "No tokens in circulation");
    require(
      usdtToken.transferFrom(msg.sender, address(this), amount),
      "USDT transfer failed"
    );

    uint256 profitPerToken = (amount * 1e18) / totalSupply(); // Scale by 1e18 to handle decimals
    cumulativeProfitPerToken += profitPerToken;
  }

  function withdrawProfits() external {
    _updateWithdrawable(msg.sender); // Update the withdrawable amount
    uint256 amount = withdrawable[msg.sender];
    require(amount > 0, "No withdrawable profits");
    withdrawable[msg.sender] = 0;

    require(usdtToken.transfer(msg.sender, amount), "USDT transfer failed");
  }

  function transfer(
    address recipient,
    uint256 amount
  ) public override returns (bool) {
    _updateWithdrawable(msg.sender); // Update the sender's claimable profits
    _updateWithdrawable(recipient); // Update the recipient's claimable profits

    return super.transfer(recipient, amount); // Call the original ERC20 transfer
  }

  // Override transferFrom function to include custom logic (such as profit claim)
  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) public override returns (bool) {
    _updateWithdrawable(sender); // Update the sender's claimable profits
    _updateWithdrawable(recipient); // Update the recipient's claimable profits

    return super.transferFrom(sender, recipient, amount); // Call the original ERC20 transferFrom
  }

  // Update withdrawable profits for an account
  function _updateWithdrawable(address account) internal {
    uint256 currentBalance = balanceOf(account);
    if (currentBalance > 0) {
      uint256 profitSinceLastUpdate = cumulativeProfitPerToken -
        lastCumulativeProfitPerToken[account];
      withdrawable[account] += (currentBalance * profitSinceLastUpdate) / 1e18;
    }
    lastCumulativeProfitPerToken[account] = cumulativeProfitPerToken;
  }

  function depositTokens(uint256 amount) external {
    require(amount >= MIN_DEPOSIT, "Amount below minimum");
    require(
      totalLockedTokens + amount <= TOKEN_PER_LICENSE,
      "Exceeds target lock amount"
    );
    require(_balances[msg.sender] >= amount, "Insufficient balance");

    if (!hasLockedTokens[msg.sender]) {
      usersWhoLockedTokens.push(msg.sender);
      hasLockedTokens[msg.sender] = true;
    }

    lockedTokens[msg.sender] += amount;
    totalLockedTokens += amount;

    emit TokensDeposited(msg.sender, amount);
  }

  function finalizeSale() external onlyOwner {
    require(totalLockedTokens == TOKEN_PER_LICENSE, "Target not reached");

    for (uint256 i = 0; i < usersWhoLockedTokens.length; i++) {
      address user = usersWhoLockedTokens[i];
      uint256 locked = lockedTokens[user];
      if (locked > 0) {
        _burn(user, locked);
        lockedTokens[user] = 0;
      }
    }

    totalLockedTokens = 0;

    emit SaleFinalized();
  }
}
