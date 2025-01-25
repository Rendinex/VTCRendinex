pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {console} from "forge-std/console.sol";

contract RVTC is ERC20, Ownable, ReentrancyGuard {
    uint256 public constant TOKEN_PER_LICENSE = 1000 * 10 ** 18;
    uint256 public totalLicensesMinted;
    uint256 public constant MIN_DEPOSIT = 10; // Minimum 10 tokens for deposit
    uint256 public totalLockedTokens;
    uint256 public cumulativeProfitPerToken; // Global cumulative profit per token
    uint256 public feePercent = 10;
    uint256 public totalFundsForLicenses;
    uint256 public nextLicenseId;
    uint256 public totalLicensesReturned;
    address public treasury;
    address public rendinex;
    address[] public usersWhoLockedTokens;

    mapping(uint256 => License) public licenses;
    mapping(address => uint256) public usdtWithdrawable;
    mapping(address => uint256) public lastCumulativeProfitPerToken; // Tracks each holder's last withdraw
    mapping(address => uint256) public withdrawable; // Withdrawable profits for each user
    mapping(address => uint256) public lockedTokens;
    mapping(address => bool) public hasLockedTokens;
    mapping(uint256 => uint256) public tokensDistributedPerLicense;

    // License struct definition
    struct License {
        uint256 fundingGoal; // Target funding for the license
        uint256 fundsRaised; // Total funds collected
        bool fundingCompleted; // Whether the funding goal is met
        mapping(address => uint256) contributions; // Contributions made by each user
    }

    IERC20 public usdtToken; // USDT token instance

    // Events
    event LicenseCreated(uint256 indexed licenseId, uint256 fundingGoal);
    event LicenseFunded(
        uint256 indexed licenseId,
        address indexed contributor,
        uint256 amount
    );
    event LicenseFinalized(uint256 indexed licenseId, uint256 totalFundsRaised);
    event ContributionWithdrawn(
        uint256 indexed licenseId,
        address indexed contributor,
        uint256 amount
    );
    event FundingGoalReduced(uint256 indexed licenseId, uint256 newFundingGoal);
    event TokensDeposited(address indexed user, uint256 amount);
    event SaleFinalized();
    event LicenseMinted(uint256 indexed licenseId, uint256 fundingGoal);
    event FundsCollected(uint256 amount, address to);
    event TokensUndeposited(address indexed user, uint256 amount);

    // Constructor
    constructor(
        address _usdtToken,
        address _treasury,
        address _rendinex
    ) Ownable(msg.sender) ERC20("RVTC", "RVTC") {
        usdtToken = IERC20(_usdtToken);
        treasury = _treasury;
        rendinex = _rendinex;
    }

    // Create a new license with a specified funding goal
    function createLicense(uint256 fundingGoal) external onlyOwner {
        require(fundingGoal > 0, "Funding goal must be greater than zero");

        uint256 licenseId = nextLicenseId++;
        licenses[licenseId].fundingGoal = fundingGoal;
        licenses[licenseId].fundingCompleted = false;

        emit LicenseCreated(licenseId, fundingGoal);
    }

    // Contribute to a specific license
    function contributeToLicense(
        uint256 licenseId,
        uint256 amount
    ) external nonReentrant {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "Funding already completed");
        require(amount > 0, "Contribution must be greater than zero");
        require(
            usdtToken.transferFrom(msg.sender, address(this), amount),
            "USDT transfer failed"
        );

        license.fundsRaised += amount;
        totalFundsForLicenses += amount;
        license.contributions[msg.sender] += amount;

        emit LicenseFunded(licenseId, msg.sender, amount);
    }

    // Reduce the funding goal for a specific license
    function reduceFundingGoal(
        uint256 licenseId,
        uint256 newFundingGoal
    ) external onlyOwner {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "Funding already completed");
        require(
            newFundingGoal >= license.fundsRaised,
            "New funding goal cannot be less than funds raised"
        );
        require(
            newFundingGoal < license.fundingGoal,
            "New funding goal must be less than current goal"
        );

        license.fundingGoal = newFundingGoal;

        emit FundingGoalReduced(licenseId, newFundingGoal);
    }

    // Withdraw contributions if funding goal is not met
    function withdrawContribution(uint256 licenseId) external nonReentrant {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "Funding already completed");
        uint256 contribution = license.contributions[msg.sender];
        require(contribution > 0, "No contributions to withdraw");

        license.contributions[msg.sender] = 0;
        license.fundsRaised -= contribution;

        require(
            usdtToken.transfer(msg.sender, contribution),
            "USDT transfer failed"
        );

        emit ContributionWithdrawn(licenseId, msg.sender, contribution);
    }

    // Collect funds from all licenses and transfer to a specified address
    function collectLicenseFunds(address to) external onlyOwner {
        uint256 amountToCollect = totalFundsForLicenses;
        totalFundsForLicenses = 0; // Reset the funds counter
        require(
            usdtToken.balanceOf(address(this)) >= amountToCollect,
            "Insufficient balance"
        );
        usdtToken.transfer(to, amountToCollect);

        emit FundsCollected(amountToCollect, to);
    }

    // Finalize a license once its funding goal is met
    function finalizeLicense(uint256 licenseId) external onlyOwner {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "License already finalized");
        require(
            license.fundsRaised >= license.fundingGoal,
            "Funding goal not reached"
        );

        license.fundingCompleted = true;
        totalLicensesMinted++;
        _mint(address(this), TOKEN_PER_LICENSE);

        require(
            usdtToken.transfer(owner(), license.fundsRaised),
            "USDT transfer to owner failed"
        );

        emit LicenseFinalized(licenseId, license.fundsRaised);
    }

    // Get the last cumulative profit per token for a contributor
    function getLastCumulativeProfitPerToken(
        address contributor
    ) external view returns (uint256) {
        return lastCumulativeProfitPerToken[contributor];
    }

    // Get the withdrawable amount for a contributor
    function getWithdrawableAmount(
        address contributor
    ) external view returns (uint256) {
        return withdrawable[contributor];
    }

    // Get the remaining funds required for a specific license
    function getRemainingFundsForLicense(
        uint256 licenseId
    ) external view returns (uint256) {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "License funding already completed");

        if (license.fundsRaised < license.fundingGoal) {
            return license.fundingGoal - license.fundsRaised; // Return remaining funds required
        } else {
            return 0; // No remaining funds if funding goal is already met or exceeded
        }
    }

    // Distribute tokens for a finalized license to a recipient
    function distributeTokensForLicense(
        uint256 licenseId,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        License storage license = licenses[licenseId];
        require(license.fundingCompleted, "Funding not finalized yet");
        require(
            tokensDistributedPerLicense[licenseId] + amount <=
                TOKEN_PER_LICENSE,
            "Exceeds token allocation for this license"
        );
        require(
            balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );

        tokensDistributedPerLicense[licenseId] += amount;
        _transfer(address(this), recipient, amount);
    }

    // Distribute profits among token holders
    function distributeProfits(uint256 amount) external onlyOwner {
        require(totalSupply() > 0, "No tokens in circulation");
        require(
            usdtToken.transferFrom(msg.sender, address(this), amount),
            "USDT transfer failed"
        );

        uint256 profitPerToken = (amount * 1e18) / totalSupply(); // Scale by 1e18 to manage precision
        cumulativeProfitPerToken += profitPerToken;
    }

    // Override `transfer` to include profit withdrawal mechanism
    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _withdrawProfitsIfThresholdMet(msg.sender); // Withdraw profits for sender
        _withdrawProfitsIfThresholdMet(recipient); // Withdraw profits for recipient
        return super.transfer(recipient, amount);
    }

    // Override `transferFrom` to include profit withdrawal mechanism
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _withdrawProfitsIfThresholdMet(sender); // Withdraw profits for sender
        _withdrawProfitsIfThresholdMet(recipient); // Withdraw profits for recipient
        return super.transferFrom(sender, recipient, amount);
    }

    // Withdraw profits automatically if the threshold is met
    function _withdrawProfitsIfThresholdMet(address account) internal {
        _updateWithdrawable(account); // Update the withdrawable profits for the account
        uint256 amount = withdrawable[account]; // Get the withdrawable amount

        if (amount >= 5 * 10 ** 6) {
            // At least $5 (USDT uses 6 decimals)
            withdrawable[account] = 0; // Reset withdrawable profits
            require(
                usdtToken.transfer(account, amount),
                "USDT transfer failed"
            );
        }
    }

    // Allow users to manually withdraw their profits
    function withdrawProfits() public {
        _updateWithdrawable(msg.sender); // Update withdrawable profits for the caller

        uint256 amount = withdrawable[msg.sender]; // Fetch withdrawable amount

        require(amount > 0, "No withdrawable profits");
        require(
            amount >= 5 * 10 ** 6,
            "Withdrawable amount must be at least $5"
        );

        withdrawable[msg.sender] = 0; // Reset withdrawable profits
        require(usdtToken.transfer(msg.sender, amount), "USDT transfer failed");
    }

    // Internal function to update withdrawable profits for an account
    function _updateWithdrawable(address account) internal {
        uint256 currentBalance = balanceOf(account);
        if (currentBalance > 0) {
            uint256 profitSinceLastUpdate = cumulativeProfitPerToken -
                lastCumulativeProfitPerToken[account];
            withdrawable[account] +=
                (currentBalance * profitSinceLastUpdate) /
                1e18;
        }
        lastCumulativeProfitPerToken[account] = cumulativeProfitPerToken;
    }

    // Deposit tokens into the contract for locking
    function depositTokens(uint256 amount) external {
        require(amount >= MIN_DEPOSIT, "Amount below minimum");

        // Calculate the remaining tokens available for deposit
        uint256 remainingTokens = TOKEN_PER_LICENSE - totalLockedTokens;

        // Ensure the amount doesn't exceed the remaining space
        uint256 depositAmount = amount > remainingTokens
            ? remainingTokens
            : amount;
        uint256 currentBalance = balanceOf(msg.sender);

        require(currentBalance >= depositAmount, "Insufficient balance");

        // If this is the first time the user deposits, add them to the list
        if (!hasLockedTokens[msg.sender]) {
            usersWhoLockedTokens.push(msg.sender);
            hasLockedTokens[msg.sender] = true;
        }

        lockedTokens[msg.sender] += depositAmount;
        totalLockedTokens += depositAmount;

        emit TokensDeposited(msg.sender, depositAmount);
    }

    // Undeposit all tokens locked by the user, provided the total locked tokens don't exceed the target
    function undepositAllTokens() external {
        require(
            totalLockedTokens < TOKEN_PER_LICENSE,
            "Cannot undeposit, total locked tokens reached target"
        );

        uint256 amount = lockedTokens[msg.sender];
        require(amount > 0, "No locked tokens to undeposit");
        require(
            totalLockedTokens - amount >= 0,
            "Total locked tokens would exceed limit"
        );

        // Reset the user's locked tokens and total locked tokens
        lockedTokens[msg.sender] = 0;
        totalLockedTokens -= amount;

        // If the user's locked tokens are zero, remove them from the list of users who locked tokens
        if (lockedTokens[msg.sender] == 0) {
            // Find the index of the user
            uint256 index;
            for (uint256 i = 0; i < usersWhoLockedTokens.length; i++) {
                if (usersWhoLockedTokens[i] == msg.sender) {
                    index = i;
                    break;
                }
            }

            // Swap the last user with the current one and pop the last user
            usersWhoLockedTokens[index] = usersWhoLockedTokens[
                usersWhoLockedTokens.length - 1
            ];
            usersWhoLockedTokens.pop();
            hasLockedTokens[msg.sender] = false;
        }

        // Emit the undeposit event
        emit TokensUndeposited(msg.sender, amount);
    }

    // Finalize the sale and burn locked tokens
    function finalizeSale() external onlyOwner {
        require(totalLockedTokens == TOKEN_PER_LICENSE, "Target not reached");

        uint256 length = usersWhoLockedTokens.length;
        uint256 i = 0;

        while (i < length) {
            address user = usersWhoLockedTokens[i];
            uint256 locked = lockedTokens[user];

            // Check if the user has locked tokens
            if (locked > 0) {
                _burn(user, locked); // Burn the locked tokens
                lockedTokens[user] = 0; // Reset the locked tokens for the user

                // Remove the user by swapping with the last element
                usersWhoLockedTokens[i] = usersWhoLockedTokens[length - 1];
                usersWhoLockedTokens.pop(); // Remove the last element

                length--;
                totalLockedTokens -= locked;
            } else {
                i++;
            }
        }

        totalLicensesReturned += 1;
        emit SaleFinalized();
    }

    // Retrieve information about all licenses
    function getLicenses()
        external
        view
        returns (
            uint256[] memory,
            uint256[] memory,
            uint256[] memory,
            bool[] memory
        )
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
