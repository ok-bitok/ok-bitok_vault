// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Vault {
    IERC20 public immutable usdc;
    address public immutable manager;
    address public navUpdater;
    uint256 public immutable maxTvl;
    uint256 public minDeposit;
    uint256 public minWithdrawal;

    uint256 public nav;
    uint256 public frozenNav;
    bool public isShutdown;
    address public migrationTarget;

    uint256 public constant SHARE_MULTIPLIER = 1e18;
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant MAX_FEE_BATCH_SIZE = 50;

    uint256 public vipThreshold;
    uint256 public minReferrerTvl;

    uint256 public totalShares;

    address[] private investors;
    mapping(address => bool) private isInvestorKnown;
    mapping(address => bool) private isInvestorActive;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public pendingWithdrawalShares;
    mapping(address => uint256) public pendingWithdrawalAmountUsdc;
    mapping(address => uint64) public pendingWithdrawalTimestamp;
    mapping(address => uint256) public firstDepositTimestamp;
    mapping(address => address) public referrerOf;
    mapping(address => bool) public isVip;

    struct PendingDeposit {
        address investor;
        uint128 amountUsdc;
        uint64 timestamp;
        bool active;
    }

    mapping(uint256 => PendingDeposit) internal pendingDeposits;
    uint256 public nextPendingDepositId;
    mapping(address => uint256[]) internal investorPendingDeposits;
    mapping(uint256 => uint256) internal investorPendingDepositsIndex;

    struct InvestorFeeState {
        uint256 lastSharePrice;
        bool initialized;
    }

    mapping(address => InvestorFeeState) internal investorFeeState;

    bool public performanceFeeStopped;
    uint256 public performanceFeeCutoffSharePrice;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event DepositPending(address indexed user, uint256 amount, uint256 pendingId);
    event WithdrawalRequested(
        address indexed user,
        uint256 amountUsdc,
        uint256 sharesLocked
    );
    event WithdrawalProcessed(address indexed user, uint256 amountUsdc);
    event NavUpdated(uint256 oldNav, uint256 newNav);
    event CapitalDeployed(uint256 amount);
    event CapitalReturned(uint256 amount);
    event ReferralRegistered(address indexed user, address indexed referrer);
    event ReferralRewardAccrued(address indexed referrer, uint256 amount);
    event MigrationTargetSet(address indexed newVault);
    event Migrated(address indexed user, uint256 shares, address indexed newVault);
    event Shutdown();
    event Redeemed(address indexed user, uint256 shares, uint256 payout);

    modifier onlyManager() {
        require(msg.sender == manager, "Not manager");
        _;
    }

    modifier onlyNavUpdater() {
        require(msg.sender == navUpdater, "Not navUpdater");
        _;
    }

    modifier notShutdown() {
        require(!isShutdown, "Shutdown");
        _;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;

        _;
        _status = _NOT_ENTERED;
    }

    constructor(
        address _usdc,
        address _manager,
        uint256 _maxTvl,
        uint256 _minDeposit,
        uint256 _vipThreshold,
        uint256 _initialNav
    ) {
        require(_usdc != address(0), "USDC address zero");
        require(_manager != address(0), "Manager zero");
        require(_maxTvl > 0, "maxTvl zero");
        require(_minDeposit > 0, "minDeposit zero");
        require(_vipThreshold > 0, "vipThreshold zero");
        require(_initialNav > 0, "nav zero");

        usdc = IERC20(_usdc);
        manager = _manager;
        navUpdater = _manager;
        maxTvl = _maxTvl;
        minDeposit = _minDeposit;
        minWithdrawal = _minDeposit;
        vipThreshold = _vipThreshold;
        minReferrerTvl = 100 * 1e6;
        nav = _initialNav;

        nextPendingDepositId = 1;

        _status = _NOT_ENTERED;
    }

    // ===== Investor actions =====

    function deposit(uint256 amount) external notShutdown nonReentrant {
        require(amount >= minDeposit, "Amount too small");
        require(nav > 0, "NAV is zero");

        _registerInvestor(msg.sender);

        _transferFrom(msg.sender, address(this), amount);
        _transfer(address(this), manager, amount);

        uint256 pendingId = _createPendingDeposit(amount);

        isInvestorActive[msg.sender] = true;

        emit DepositPending(msg.sender, amount, pendingId);
    }

    function requestWithdraw(uint256 amountUsdc) external notShutdown nonReentrant {
        require(amountUsdc > 0, "Zero amount");
        require(amountUsdc >= minWithdrawal, "Withdrawal amount too small");
        require(nav > 0, "NAV is zero");

        _settlePerformanceFee(msg.sender);

        _registerInvestor(msg.sender);

        uint256 sharesToBurn = (amountUsdc * SHARE_MULTIPLIER) / nav;
        require(sharesToBurn > 0, "Amount too small");

        uint256 freeShares = balances[msg.sender] - pendingWithdrawalShares[msg.sender];
        require(sharesToBurn <= freeShares, "Insufficient free shares");

        pendingWithdrawalShares[msg.sender] += sharesToBurn;
        pendingWithdrawalAmountUsdc[msg.sender] += amountUsdc;
        pendingWithdrawalTimestamp[msg.sender] = uint64(block.timestamp);

        isInvestorActive[msg.sender] = true;

        emit WithdrawalRequested(msg.sender, amountUsdc, sharesToBurn);
    }

    function migrate(uint256 shares) external notShutdown nonReentrant {
        address target = migrationTarget;
        require(target != address(0), "No migration target");
        require(shares > 0, "Zero shares");
        require(shares <= balances[msg.sender] - pendingWithdrawalShares[msg.sender], "Insufficient free shares");
        require(_isContract(target), "Target not contract");

        _settlePerformanceFee(msg.sender);

        require(nav > 0, "NAV is zero");

        balances[msg.sender] -= shares;
        totalShares -= shares;

        uint256 amountToTransfer = (shares * nav) / SHARE_MULTIPLIER;
        require(amountToTransfer > 0, "Amount too small");
        require(usdc.balanceOf(address(this)) >= amountToTransfer, "Insufficient liquidity");

        _transfer(address(this), target, amountToTransfer);

        _updateVipStatus(msg.sender);
        _updateInvestorActivity(msg.sender);

        emit Migrated(msg.sender, shares, target);
    }

    function registerReferral(address referrer) external nonReentrant {
        require(referrer != address(0), "Referrer zero");
        require(referrer != msg.sender, "Self referrer");
        require(referrerOf[msg.sender] == address(0), "Already registered");
        require(firstDepositTimestamp[msg.sender] == 0, "Deposit already made");
        require(balances[referrer] > 0, "Referrer has no shares");
        require(firstDepositTimestamp[referrer] != 0, "Referrer inactive");
        require(
            firstDepositTimestamp[msg.sender] == 0 ||
                firstDepositTimestamp[referrer] < firstDepositTimestamp[msg.sender],
            "Referrer not older"
        );

        referrerOf[msg.sender] = referrer;

        emit ReferralRegistered(msg.sender, referrer);
    }

    function claimReferralRewards() external nonReentrant {
        revert("claimReferralRewards: no-op, use main balance");
    }

    function redeemAll() external nonReentrant {
        require(isShutdown, "Not shutdown");

        _settlePerformanceFee(msg.sender);

        uint256 shares = balances[msg.sender];
        require(shares > 0, "No shares");

        uint256 payout = (shares * frozenNav) / SHARE_MULTIPLIER;
        require(payout > 0, "Amount too small");
        require(usdc.balanceOf(address(this)) >= payout, "Insufficient liquidity");

        balances[msg.sender] = 0;
        totalShares -= shares;

        pendingWithdrawalShares[msg.sender] = 0;
        pendingWithdrawalAmountUsdc[msg.sender] = 0;
        pendingWithdrawalTimestamp[msg.sender] = 0;

        _transfer(address(this), msg.sender, payout);

        _updateVipStatus(msg.sender);
        _updateInvestorActivity(msg.sender);

        emit Redeemed(msg.sender, shares, payout);
    }

    // ===== Manager actions =====

    function setNavUpdater(address newNavUpdater) external onlyManager nonReentrant {
        require(newNavUpdater != address(0), "Zero address");
        navUpdater = newNavUpdater;
    }

    function updateNav(uint256 newNav) external onlyNavUpdater notShutdown nonReentrant {
        require(newNav > 0, "Nav zero");
        uint256 oldNav = nav;
        nav = newNav;

        emit NavUpdated(oldNav, newNav);
    }

    function deployCapital(uint256 amount) external onlyManager notShutdown nonReentrant {
        require(amount > 0, "Zero amount");
        require(usdc.balanceOf(address(this)) >= amount, "Insufficient balance");

        _transfer(address(this), manager, amount);

        emit CapitalDeployed(amount);
    }

    function returnCapital(uint256 amount) external onlyManager nonReentrant {
        require(amount > 0, "Zero amount");

        _transferFrom(msg.sender, address(this), amount);

        emit CapitalReturned(amount);
    }

    function confirmDeposit(address investor, uint256 pendingId)
        external
        onlyManager
        notShutdown
        nonReentrant
    {
        PendingDeposit storage p = pendingDeposits[pendingId];

        require(p.active, "Not active");
        require(p.investor == investor, "Wrong investor");
        require(p.amountUsdc > 0, "Zero amount");

        uint256 amount = p.amountUsdc;

        require(nav > 0, "NAV is zero");

        uint256 mintedShares = (amount * SHARE_MULTIPLIER) / nav;
        require(mintedShares > 0, "Amount too small");

        uint256 totalSharesAfterMint = totalShares + mintedShares;
        require(
            (totalSharesAfterMint * nav) / SHARE_MULTIPLIER <= maxTvl,
            "Max TVL exceeded"
        );

        _registerInvestor(investor);

        uint256 existingBalance = balances[investor];
        InvestorFeeState storage st = investorFeeState[investor];
        if (existingBalance > 0 && st.initialized) {
            _settlePerformanceFee(investor);
        }

        bool wasZeroBalance = existingBalance == 0;

        balances[investor] += mintedShares;
        totalShares += mintedShares;

        if (firstDepositTimestamp[investor] == 0) {
            firstDepositTimestamp[investor] = block.timestamp;
        }

        if (wasZeroBalance) {
            if (!st.initialized) {
                st.lastSharePrice = _sharePrice();
                st.initialized = true;
            }
        }

        isInvestorActive[investor] = true;
        _updateVipStatus(investor);

        emit Deposited(investor, amount, mintedShares);

        p.active = false;

        uint256 index = investorPendingDepositsIndex[pendingId];
        uint256[] storage investorPendings = investorPendingDeposits[investor];
        uint256 lastPendingId = investorPendings[investorPendings.length - 1];

        if (pendingId != lastPendingId) {
            investorPendings[index] = lastPendingId;
            investorPendingDepositsIndex[lastPendingId] = index;
        }

        investorPendings.pop();
        delete investorPendingDepositsIndex[pendingId];
    }

    function fulfillWithdrawal(address user) external onlyManager notShutdown nonReentrant {
        _settlePerformanceFee(user);

        uint256 shares = pendingWithdrawalShares[user];
        uint256 amountUsdc = pendingWithdrawalAmountUsdc[user];

        uint256 balance = balances[user];

        if (shares > balance) {
            uint256 adjustedShares = balance;
            uint256 adjustedAmount = (amountUsdc * adjustedShares) / shares;

            shares = adjustedShares;
            amountUsdc = adjustedAmount;

            pendingWithdrawalShares[user] = adjustedShares;
            pendingWithdrawalAmountUsdc[user] = adjustedAmount;
            pendingWithdrawalTimestamp[user] = uint64(block.timestamp);
        }

        require(shares > 0 && amountUsdc > 0, "Nothing pending");

        uint256 sharePriceNow = _sharePrice();
        require(sharePriceNow > 0, "NAV is zero");

        uint256 userTotalShares = balances[user];
        uint256 totalValueNow = (userTotalShares * sharePriceNow) / PRICE_PRECISION;

        uint256 payout;
        uint256 sharesToBurn;

        if (totalValueNow > amountUsdc) {
            payout = amountUsdc;
            sharesToBurn = (payout * PRICE_PRECISION) / sharePriceNow;

            if (sharesToBurn > shares) {
                sharesToBurn = shares;
            }

            if (sharesToBurn > userTotalShares) {
                sharesToBurn = userTotalShares;
            }
        } else {
            payout = totalValueNow;
            sharesToBurn = userTotalShares;
        }

        _transferFrom(msg.sender, address(this), payout);
        _transfer(address(this), user, payout);

        pendingWithdrawalShares[user] = 0;
        pendingWithdrawalAmountUsdc[user] = 0;
        pendingWithdrawalTimestamp[user] = 0;
        balances[user] -= sharesToBurn;
        totalShares -= sharesToBurn;

        _updateVipStatus(user);
        _updateInvestorActivity(user);

        emit WithdrawalProcessed(user, payout);
    }

    function setMigrationTarget(address newVault) external onlyManager nonReentrant {
        require(newVault != address(0), "Zero address");
        require(migrationTarget == address(0), "Already set");
        require(_isContract(newVault), "Not a contract");

        migrationTarget = newVault;

        emit MigrationTargetSet(newVault);
    }

    function setMinLimits(uint256 newMin) external onlyManager nonReentrant {
        require(newMin > 0, "min too small");
        minDeposit = newMin;
        minWithdrawal = newMin;
    }

    function setVipThreshold(uint256 newVipThreshold) external onlyManager nonReentrant {
        require(newVipThreshold > 0, "vip too small");
        vipThreshold = newVipThreshold;
    }

    function setMinReferrerTvl(uint256 newMinReferrerTvl) external onlyManager nonReentrant {
        require(newMinReferrerTvl > 0, "min ref too small");
        minReferrerTvl = newMinReferrerTvl;
    }

    function shutdownVault() external onlyManager nonReentrant {
        require(!isShutdown, "Already shutdown");

        isShutdown = true;
        frozenNav = nav;
        performanceFeeStopped = true;
        performanceFeeCutoffSharePrice = _sharePrice();

        emit Shutdown();
    }

    // ===== View helpers =====

    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }

    function pendingWithdrawalOf(address user) external view returns (uint256) {
        return pendingWithdrawalShares[user];
    }

    function pendingWithdrawalAmount(address user) external view returns (uint256) {
        return pendingWithdrawalAmountUsdc[user];
    }

    function getPendingDeposit(uint256 pendingId)
        external
        view
        returns (address investor, uint256 amountUsdc, uint64 timestamp, bool active)
    {
        PendingDeposit storage p = pendingDeposits[pendingId];
        return (p.investor, uint256(p.amountUsdc), p.timestamp, p.active);
    }

    function getInvestorPendingDeposits(address investor) external view returns (uint256[] memory) {
        return investorPendingDeposits[investor];
    }

    function tvl() public view returns (uint256) {
        return (totalShares * nav) / SHARE_MULTIPLIER;
    }

    function referralOf(address user) external view returns (address) {
        return referrerOf[user];
    }

    function refBalance(address user) external pure returns (uint256) {
        user;
        return 0;
    }

    function isReferrerActive(address referrer) internal view returns (bool) {
        if (referrer == address(0)) {
            return false;
        }

        uint256 referrerShares = balances[referrer];
        if (referrerShares == 0) {
            return false;
        }

        uint256 sharePrice = (performanceFeeStopped || isShutdown)
            ? frozenNav
            : nav;
        uint256 valueUsdc = (referrerShares * sharePrice) / SHARE_MULTIPLIER;
        return valueUsdc >= minReferrerTvl;
    }

    function investorsCount() external view returns (uint256) {
        return investors.length;
    }

    function investorAt(uint256 index) external view returns (address) {
        return investors[index];
    }

    // ===== Internal helpers =====

    function _createPendingDeposit(uint256 amount) internal returns (uint256 pendingId) {
        require(amount <= type(uint128).max, "Amount too large");

        pendingId = nextPendingDepositId;
        nextPendingDepositId++;

        pendingDeposits[pendingId] = PendingDeposit({
            investor: msg.sender,
            amountUsdc: uint128(amount),
            timestamp: uint64(block.timestamp),
            active: true
        });

        investorPendingDeposits[msg.sender].push(pendingId);
        investorPendingDepositsIndex[pendingId] = investorPendingDeposits[msg.sender].length - 1;
    }

    function _sharePrice() internal view returns (uint256 price) {
        if (totalShares == 0) {
            return nav;
        }

        uint256 totalAssets = (nav * totalShares) / SHARE_MULTIPLIER;
        return (totalAssets * PRICE_PRECISION) / totalShares;
    }

    function crystallizeFees(uint256 fromIndex, uint256 toIndex) external onlyManager notShutdown nonReentrant {
        require(fromIndex < toIndex, "Bad range");
        require(toIndex <= investors.length, "Out of range");
        require(toIndex - fromIndex <= MAX_FEE_BATCH_SIZE, "batch too large");

        uint256 currentPrice = _currentFeeSharePrice();
        for (uint256 i = fromIndex; i < toIndex; i++) {
            address investor = investors[i];
            if (!isInvestorActive[investor]) {
                continue;
            }
            _settlePerformanceFeeForPeriod(investor, currentPrice);
            _updateVipStatus(investor);
        }
    }

    function _settlePerformanceFeeForPeriod(address investor) internal {
        uint256 currentPrice = _currentFeeSharePrice();
        _settlePerformanceFeeForPeriod(investor, currentPrice);
    }

    function _settlePerformanceFee(address investor) internal {
        uint256 currentPrice = _currentFeeSharePrice();
        _settlePerformanceFeeForPeriod(investor, currentPrice);
    }

    function _settlePerformanceFeeForPeriod(address investor, uint256 currentPrice) internal {
        uint256 shares = balances[investor];
        if (shares == 0) {
            return;
        }

        InvestorFeeState storage st = investorFeeState[investor];
        if (!st.initialized) {
            st.lastSharePrice = currentPrice;
            st.initialized = true;
            return;
        }

        if (currentPrice <= st.lastSharePrice) {
            return;
        }

        uint256 priceDelta = currentPrice - st.lastSharePrice;
        uint256 profitValue = (priceDelta * shares) / PRICE_PRECISION;

        uint256 managerBps;
        uint256 referralBps;
        address ref = referrerOf[investor];
        bool vip = isVip[investor];
        bool hasActiveRef = isReferrerActive(ref);

        if (!vip && !hasActiveRef) {
            managerBps = 1200;
            referralBps = 0;
        }
        if (!vip && hasActiveRef) {
            managerBps = 1000;
            referralBps = 100;
        }

        if (vip && !hasActiveRef) {
            managerBps = 1000;
            referralBps = 0;
        }
        if (vip && hasActiveRef) {
            managerBps = 800;
            referralBps = 100;
        }

        uint256 managerFeeValue = (profitValue * managerBps) / 10_000;
        uint256 referralFeeValue = (profitValue * referralBps) / 10_000;
        uint256 totalFeeValue = managerFeeValue + referralFeeValue;

        uint256 feeShares = (totalFeeValue * PRICE_PRECISION) / currentPrice;
        if (feeShares == 0) {
            st.lastSharePrice = currentPrice;
            return;
        }

        if (feeShares > shares) {
            feeShares = shares;
        }

        uint256 managerShares;
        uint256 referralShares;

        if (referralFeeValue > 0 && hasActiveRef) {
            managerShares = (managerFeeValue * PRICE_PRECISION) / currentPrice;
            referralShares = feeShares - managerShares;
        } else {
            managerShares = feeShares;
            referralShares = 0;
        }

        balances[investor] -= feeShares;
        if (managerShares > 0) {
            balances[manager] += managerShares;
        }

        if (referralShares > 0 && hasActiveRef) {
            balances[ref] += referralShares;
            emit ReferralRewardAccrued(ref, referralShares);
            _updateVipStatus(ref);
        }

        st.lastSharePrice = currentPrice;

        _updateVipStatus(investor);
        if (managerShares > 0) {
            _updateVipStatus(manager);
        }
    }

    function _currentFeeSharePrice() internal view returns (uint256) {
        if (performanceFeeStopped && performanceFeeCutoffSharePrice > 0) {
            return performanceFeeCutoffSharePrice;
        }

        return _sharePrice();
    }

    function _isCalendarFirstDay() internal view returns (bool) {
        (, , uint256 dayOfMonth) = _timestampToYMD(block.timestamp);
        return dayOfMonth == 1;
    }

    function _timestampToYMD(uint256 timestamp) internal pure returns (uint256 year, uint256 month, uint256 day) {
        uint256 _days = timestamp / 1 days;

        uint256 L = _days + 68569 + 2440588;
        uint256 N = (4 * L) / 146097;
        L = L - (146097 * N + 3) / 4;
        uint256 _year = (4000 * (L + 1)) / 1461001;
        L = L - (1461 * _year) / 4 + 31;
        uint256 _month = (80 * L) / 2447;
        uint256 _day = L - (2447 * _month) / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        return (_year, _month, _day);
    }

    function _mint(address to, uint256 shares) internal {
        require(to != address(0), "Zero address");
        require(shares > 0, "Zero shares");

        balances[to] += shares;
        totalShares += shares;
    }

    function _updateVipStatus(address investor) internal {
        uint256 sharePrice = isShutdown ? frozenNav : nav;
        uint256 balance = balances[investor];
        uint256 pendingShares = pendingWithdrawalShares[investor];
        uint256 activeShares = balance;

        if (pendingShares > activeShares) {
            activeShares = 0;
        } else {
            activeShares -= pendingShares;
        }

        uint256 currentValue = (activeShares * sharePrice) / SHARE_MULTIPLIER;
        isVip[investor] = currentValue >= vipThreshold;
    }

    function _registerInvestor(address user) internal {
        if (
            !isInvestorKnown[user] &&
            balances[user] == 0 &&
            pendingWithdrawalShares[user] == 0 &&
            pendingWithdrawalAmountUsdc[user] == 0
        ) {
            isInvestorKnown[user] = true;
            isInvestorActive[user] = true;
            investors.push(user);
            return;
        }

        if (
            isInvestorKnown[user] &&
            !isInvestorActive[user] &&
            (balances[user] > 0 || pendingWithdrawalShares[user] > 0 || pendingWithdrawalAmountUsdc[user] > 0)
        ) {
            isInvestorActive[user] = true;
        }
    }

    function _updateInvestorActivity(address user) internal {
        if (
            balances[user] == 0 &&
            pendingWithdrawalShares[user] == 0 &&
            pendingWithdrawalAmountUsdc[user] == 0 &&
            investorPendingDeposits[user].length == 0
        ) {
            isInvestorActive[user] = false;
        }
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from == address(this), "Invalid sender");
        if (amount == 0) {
            return;
        }

        (bool success, bytes memory data) = address(usdc).call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "USDC transfer failed"
        );
    }

    function _transferFrom(address from, address to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        (bool success, bytes memory data) = address(usdc).call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "USDC transfer failed"
        );
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
