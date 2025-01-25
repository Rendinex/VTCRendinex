pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {console} from "forge-std/console.sol";

contract RVTC is ERC20, Ownable, ReentrancyGuard {
    uint256 public constant TOKEN_PER_LICENSE = 1000 * 10 ** 18;
    uint256 public totalLicensesMinted;
    uint256 public constant MIN_DEPOSIT = 10; // Minimum 10 tokens
    uint256 public totalLockedTokens;
    uint256 public cumulativeProfitPerToken; // Global cumulative profit per token
    uint256 public feePercent = 10;
    uint256 public totalFundsForLicenses;
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
        mapping(address => uint256) contributions;
    }

    IERC20 public usdtToken;

    event LicenseCreated(uint256 indexed licenseId, uint256 fundingGoal);
    event LicenseFunded(uint256 indexed licenseId, address indexed contributor, uint256 amount);
    event LicenseFinalized(uint256 indexed licenseId, uint256 totalFundsRaised);
    event ContributionWithdrawn(uint256 indexed licenseId, address indexed contributor, uint256 amount);
    event FundingGoalReduced(uint256 indexed licenseId, uint256 newFundingGoal);

    event TokensDeposited(address indexed user, uint256 amount);
    event SaleFinalized();
    event LicenseMinted(uint256 indexed licenseId, uint256 fundingGoal);
    event LicensePurchased(address indexed buyer, uint256 indexed licenseId, uint256 amount);
    event TokensWithdrawed(address indexed withdrawer, uint256 amount);
    event USDTDeposited(uint256 amount);
    event FeesDistributed(uint256 treasuryFee, uint256 rendinexFee);
    event FundsCollected(uint256 amount, address to);

    constructor(address _usdtToken, address _treasury, address _rendinex) Ownable(msg.sender) ERC20("RVTC", "RVTC") {
        usdtToken = IERC20(_usdtToken);
        treasury = _treasury;
        rendinex = _rendinex;
    }

    function createLicense(uint256 fundingGoal) external onlyOwner {
        require(fundingGoal > 0, "Funding goal must be greater than zero");

        uint256 licenseId = nextLicenseId++;
        licenses[licenseId].fundingGoal = fundingGoal;
        licenses[licenseId].fundingCompleted = false;

        emit LicenseCreated(licenseId, fundingGoal);
    }

    function contributeToLicense(uint256 licenseId, uint256 amount) external nonReentrant {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "Funding already completed");
        require(amount > 0, "Contribution must be greater than zero");
        require(usdtToken.transferFrom(msg.sender, address(this), amount), "USDT transfer failed");

        license.fundsRaised += amount;
        totalFundsForLicenses += amount;
        license.contributions[msg.sender] += amount;

        emit LicenseFunded(licenseId, msg.sender, amount);
    }

    function reduceFundingGoal(uint256 licenseId, uint256 newFundingGoal) external onlyOwner {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "Funding already completed");
        require(newFundingGoal >= license.fundsRaised, "New funding goal must be at least the amount already raised");
        require(newFundingGoal < license.fundingGoal, "New funding goal must be less than the current goal");

        license.fundingGoal = newFundingGoal;

        emit FundingGoalReduced(licenseId, newFundingGoal);
    }

    function withdrawContribution(uint256 licenseId) external nonReentrant {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "Funding already completed");
        uint256 contribution = license.contributions[msg.sender];
        require(contribution > 0, "No contributions to withdraw");

        license.contributions[msg.sender] = 0;
        license.fundsRaised -= contribution;

        require(usdtToken.transfer(msg.sender, contribution), "USDT transfer failed");

        emit ContributionWithdrawn(licenseId, msg.sender, contribution);
    }

    function mintLicense(uint256 fundingGoal) external onlyOwner {
        require(fundingGoal > 0, "Funding goal must be greater than zero");

        uint256 licenseId = nextLicenseId++;
        // Initialize the struct fields explicitly, excluding the mapping
        License storage license = licenses[licenseId];
        license.fundingGoal = fundingGoal;
        license.fundingCompleted = false;

        emit LicenseMinted(licenseId, fundingGoal);
    }

    function collectLicenseFunds(address to) external onlyOwner {
        uint256 amountToCollect = totalFundsForLicenses;
        totalFundsForLicenses = 0; // Reset the tracked funds
        require(usdtToken.balanceOf(address(this)) >= amountToCollect, "Insufficient balance");
        usdtToken.transfer(to, amountToCollect);
        emit FundsCollected(amountToCollect, to);
    }

    function finalizeLicense(uint256 licenseId) external onlyOwner {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "License already finalized");
        require(license.fundsRaised >= license.fundingGoal, "Funding goal not reached");

        license.fundingCompleted = true;
        totalLicensesMinted++;
        _mint(address(this), TOKEN_PER_LICENSE);

        require(usdtToken.transfer(owner(), license.fundsRaised), "USDT transfer to owner failed");

        emit LicenseFinalized(licenseId, license.fundsRaised);
    }

    function getTotalFundsForLicenses() external view returns (uint256) {
        return totalFundsForLicenses;
    }

    function getCumulativeProfitPerToken() external view returns (uint256) {
        return cumulativeProfitPerToken;
    }

    function getLastCumulativeProfitPerToken(address contributor) external view returns (uint256) {
        return lastCumulativeProfitPerToken[contributor];
    }

    function getWithdrawableAmount(address contributor) external view returns (uint256) {
        return withdrawable[contributor];
    }

    mapping(uint256 => uint256) public tokensDistributedPerLicense;

    function distributeTokensForLicense(uint256 licenseId, address recipient, uint256 amount) external onlyOwner {
        License storage license = licenses[licenseId];
        require(license.fundingCompleted, "Funding not finalized yet");
        require(
            tokensDistributedPerLicense[licenseId] + amount <= TOKEN_PER_LICENSE,
            "Exceeds token allocation for this license"
        );
        require(balanceOf(address(this)) >= amount, "Insufficient contract balance");

        tokensDistributedPerLicense[licenseId] += amount;
        _transfer(address(this), recipient, amount);
    }

    function distributeProfits(uint256 amount) external onlyOwner {
        require(totalSupply() > 0, "No tokens in circulation");
        require(usdtToken.transferFrom(msg.sender, address(this), amount), "USDT transfer failed");

        uint256 profitPerToken = (amount * 1e18) / totalSupply(); // Scale by 1e18 to handle decimals
        cumulativeProfitPerToken += profitPerToken;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _withdrawProfitsIfThresholdMet(msg.sender);
        _withdrawProfitsIfThresholdMet(recipient);
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _withdrawProfitsIfThresholdMet(sender);
        _withdrawProfitsIfThresholdMet(recipient);
        return super.transferFrom(sender, recipient, amount);
    }

    function _withdrawProfitsIfThresholdMet(address account) internal {
        _updateWithdrawable(account); // Update withdrawable profits for the account
        uint256 amount = withdrawable[account]; // Fetch the withdrawable amount

        if (amount >= 5 * 10 ** 6) {
            // Check if the amount is at least $5 (USDT uses 6 decimals)
            withdrawable[account] = 0; // Reset the withdrawable profits
            require(usdtToken.transfer(account, amount), "USDT transfer failed");
        }
    }

    function withdrawProfits() public {
        _updateWithdrawable(msg.sender); // Update withdrawable profits for the caller

        uint256 amount = withdrawable[msg.sender]; // Fetch the withdrawable amount

        require(amount > 0, "No withdrawable profits");
        require(amount >= 5 * 10 ** 6, "Withdrawable amount must be at least $5");

        withdrawable[msg.sender] = 0; // Reset the withdrawable profits
        require(usdtToken.transfer(msg.sender, amount), "USDT transfer failed");
    }

    // Update withdrawable profits for an account
    function _updateWithdrawable(address account) internal {
        uint256 currentBalance = balanceOf(account);
        if (currentBalance > 0) {
            uint256 profitSinceLastUpdate = cumulativeProfitPerToken - lastCumulativeProfitPerToken[account];
            withdrawable[account] += (currentBalance * profitSinceLastUpdate) / 1e18;
        }
        lastCumulativeProfitPerToken[account] = cumulativeProfitPerToken;
    }

    function depositTokens(uint256 amount) external {
        require(amount >= MIN_DEPOSIT, "Amount below minimum");
        require(totalLockedTokens + amount <= TOKEN_PER_LICENSE, "Exceeds target lock amount");
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

    function getLicenses()
        external
        view
        returns (uint256[] memory, uint256[] memory, uint256[] memory, bool[] memory)
    {
        uint256 totalLicenses = nextLicenseId;
        uint256[] memory ids = new uint256[](totalLicenses);
        uint256[] memory fundingGoals = new uint256[](totalLicenses);
        uint256[] memory fundsRaised = new uint256[](totalLicenses);
        bool[] memory fundingCompleted = new bool[](totalLicenses);

        for (uint256 i = 0; i < totalLicenses; i++) {
            ids[i] = i;
            fundingGoals[i] = licenses[i].fundingGoal;
            fundsRaised[i] = licenses[i].fundsRaised;
            fundingCompleted[i] = licenses[i].fundingCompleted;
        }

        return (ids, fundingGoals, fundsRaised, fundingCompleted);
    }
}
