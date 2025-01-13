// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RVTC is ERC20, Ownable, ReentrancyGuard {
    uint256 public constant INITIAL_SUPPLY = 1000 * 10 ** 18;
    uint256 public constant TOKEN_PER_LICENSE = 1000 * 10 ** 18;
    uint256 public totalLicensesMinted;

    uint256 public feePercent = 10; // 0.1% fee (0.1 * 1000 = 10 basis points)
    address public treasury;
    address public rendinex;

    struct License {
        uint256 fundingGoal;
        uint256 fundsRaised;
        bool fundingCompleted;
    }

    mapping(uint256 => License) public licenses;
    uint256 public nextLicenseId;

    mapping(address => uint256) public usdtClaimable;

    IERC20 public usdtToken;

    event LicenseMinted(uint256 indexed licenseId, uint256 fundingGoal);
    event LicensePurchased(address indexed buyer, uint256 indexed licenseId, uint256 amount);
    event TokensClaimed(address indexed claimer, uint256 amount);
    event USDTDeposited(uint256 amount);
    event FeesDistributed(uint256 treasuryFee, uint256 rendinexFee);

    constructor(address _usdtToken, address _treasury, address _rendinex) Ownable(msg.sender) ERC20("RVTC", "RVTC") {
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

    function purchaseLicense(uint256 licenseId, uint256 amount) external nonReentrant {
        License storage license = licenses[licenseId];
        require(!license.fundingCompleted, "Funding for this license is already completed");
        require(amount > 0 && amount + license.fundsRaised <= license.fundingGoal, "Invalid funding amount");

        usdtToken.transferFrom(msg.sender, address(this), amount);
        license.fundsRaised += amount;

        if (license.fundsRaised >= license.fundingGoal) {
            license.fundingCompleted = true;
        }

        uint256 tokensToTransfer = (amount * TOKEN_PER_LICENSE) / license.fundingGoal;
        _transfer(address(this), msg.sender, tokensToTransfer);

        emit LicensePurchased(msg.sender, licenseId, amount);
    }

    function distributeUSDT(uint256 totalProfits) external onlyOwner {
        require(usdtToken.transferFrom(msg.sender, address(this), totalProfits), "USDT transfer failed");

        uint256 treasuryFee = (totalProfits * feePercent) / 10000 / 2;
        uint256 rendinexFee = treasuryFee;
        uint256 distributedAmount = totalProfits - (treasuryFee + rendinexFee);

        usdtToken.transfer(treasury, treasuryFee);
        usdtToken.transfer(rendinex, rendinexFee);

        // Implement logic for distribution

        emit USDTDeposited(totalProfits);
        emit FeesDistributed(treasuryFee, rendinexFee);
    }

    function claimUSDT() external nonReentrant {
        uint256 claimable = usdtClaimable[msg.sender];
        require(claimable > 0, "No USDT to claim");

        usdtClaimable[msg.sender] = 0;
        usdtToken.transfer(msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable);
    }

    function updateFees(uint256 newFeePercent) external onlyOwner {
        require(newFeePercent <= 100, "Fee cannot exceed 1%");
        feePercent = newFeePercent;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        uint256 fee = (amount * feePercent) / 10000;
        uint256 amountAfterFee = amount - fee;

        uint256 treasuryShare = fee / 2;
        uint256 rendinexShare = fee - treasuryShare;

        super._transfer(sender, treasury, treasuryShare);
        super._transfer(sender, rendinex, rendinexShare);
        super._transfer(sender, recipient, amountAfterFee);
    }
}
