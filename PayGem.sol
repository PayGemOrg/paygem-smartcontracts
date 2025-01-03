// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract SubscriptionSystem is ERC721, AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;

    // Roles
    bytes32 public constant MERCHANT_ROLE = keccak256("MERCHANT_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Counters
    Counters.Counter private _planIds;
    Counters.Counter private _subscriptionIds;
    Counters.Counter private _tokenIds;

    // Constants
    uint256 public constant MIN_BALANCE_THRESHOLD = 0.1 ether;
    uint256 public platformFeePercent = 2;

    // Structs
    struct SubscriptionPlan {
        address merchant;
        uint256 price;
        uint256 duration;
        bool active;
        string metadata;
        uint256 subscriberCount;
        bool offerNFTRewards;
    }

    struct Subscription {
        uint256 planId;
        address subscriber;
        uint256 startTime;
        uint256 nextPaymentDue;
        bool active;
        uint256 totalPayments;
    }

    struct MerchantMetrics {
        uint256 totalSubscribers;
        uint256 activeSubscribers;
        uint256 totalRevenue;
        uint256 monthlyRevenue;
        uint256 churned;
    }

    // Mappings
    mapping(uint256 => SubscriptionPlan) private _plans;
    mapping(uint256 => Subscription) private _subscriptions;
    mapping(address => uint256[]) private _userSubscriptions;
    mapping(address => uint256[]) private _merchantPlans;
    mapping(address => MerchantMetrics) private _merchantMetrics;
    mapping(uint256 => string) private _tokenURIs;
    mapping(address => bool) public pendingMerchants;
    address[] public pendingMerchantList;
    // Events
    event MerchantRegistered(address indexed merchant);
    event PlanCreated(uint256 indexed planId, address merchant, uint256 price);
    event SubscriptionStarted(
        uint256 indexed subscriptionId,
        address subscriber,
        uint256 planId
    );
    event SubscriptionCancelled(uint256 indexed subscriptionId);
    event PaymentProcessed(uint256 indexed subscriptionId, uint256 amount);
    event MetricsUpdated(address indexed merchant);

    constructor() ERC721("Subscription Rewards", "SUBNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        // Set role hierarchy
        _setRoleAdmin(MERCHANT_ROLE, ADMIN_ROLE);
    }

    // Role modifiers
    modifier onlyMerchant() {
        require(hasRole(MERCHANT_ROLE, msg.sender), "Caller is not a merchant");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    // Merchant Management
    function applyForMerchant() external {
    require(!hasRole(MERCHANT_ROLE, msg.sender), "Already a merchant");
    require(!pendingMerchants[msg.sender], "Already applied");

    pendingMerchants[msg.sender] = true;
    pendingMerchantList.push(msg.sender);
}

function approveMerchant(address merchant) external onlyAdmin {
    require(pendingMerchants[merchant], "No pending application");

    _grantRole(MERCHANT_ROLE, merchant);
    pendingMerchants[merchant] = false;

    // Remove the merchant from the pending list
    for (uint256 i = 0; i < pendingMerchantList.length; i++) {
        if (pendingMerchantList[i] == merchant) {
            pendingMerchantList[i] = pendingMerchantList[pendingMerchantList.length - 1];
            pendingMerchantList.pop();
            break;
        }
    }

    emit MerchantRegistered(merchant);
}

function getPendingMerchantApplications() external view onlyAdmin returns (address[] memory) {
    return pendingMerchantList;
}

    // Plan Management
    function createPlan(
        uint256 price,
        uint256 duration,
        string calldata metadata,
        bool offerNFTRewards
    ) external onlyMerchant returns (uint256) {
        _planIds.increment();
        uint256 planId = _planIds.current();

        _plans[planId] = SubscriptionPlan({
            merchant: msg.sender,
            price: price,
            duration: duration,
            active: true,
            metadata: metadata,
            subscriberCount: 0,
            offerNFTRewards: offerNFTRewards
        });

        _merchantPlans[msg.sender].push(planId);

        emit PlanCreated(planId, msg.sender, price);
        return planId;
    }

    function updatePlanPrice(uint256 planId, uint256 newPrice)
        external
        onlyMerchant
    {
        require(_plans[planId].merchant == msg.sender, "Not plan owner");
        _plans[planId].price = newPrice;
    }

    // Subscription Management
    function subscribe(uint256 planId) external payable nonReentrant {
        require(_plans[planId].active, "Plan not active");
        require(msg.value >= _plans[planId].price, "Insufficient payment");

        _subscriptionIds.increment();
        uint256 subscriptionId = _subscriptionIds.current();

        _subscriptions[subscriptionId] = Subscription({
            planId: planId,
            subscriber: msg.sender,
            startTime: block.timestamp,
            nextPaymentDue: block.timestamp + _plans[planId].duration,
            active: true,
            totalPayments: 1
        });

        _userSubscriptions[msg.sender].push(subscriptionId);
        _plans[planId].subscriberCount++;

        _processPayment(subscriptionId);
        _updateMetrics(planId, true);

        emit SubscriptionStarted(subscriptionId, msg.sender, planId);
    }

    function cancelSubscription(uint256 subscriptionId) external {
        require(
            _subscriptions[subscriptionId].subscriber == msg.sender,
            "Not subscriber"
        );
        require(_subscriptions[subscriptionId].active, "Not active");

        _subscriptions[subscriptionId].active = false;
        _plans[_subscriptions[subscriptionId].planId].subscriberCount--;

        _updateMetricsOnCancellation(subscriptionId);

        emit SubscriptionCancelled(subscriptionId);
    }

    // View Functions
    function getPlanDetails(uint256 planId)
        external
        view
        returns (
            address merchant,
            uint256 price,
            uint256 duration,
            bool active,
            string memory metadata
        )
    {
        SubscriptionPlan storage plan = _plans[planId];
        return (
            plan.merchant,
            plan.price,
            plan.duration,
            plan.active,
            plan.metadata
        );
    }

    function getUserSubscriptions(address user)
        external
        view
        returns (uint256[] memory)
    {
        return _userSubscriptions[user];
    }

    function getMerchantPlans(address merchant)
        external
        view
        returns (uint256[] memory)
    {
        return _merchantPlans[merchant];
    }

    function getMerchantMetrics(address merchant)
        external
        view
        returns (
            uint256 totalSubscribers,
            uint256 activeSubscribers,
            uint256 totalRevenue,
            uint256 monthlyRevenue,
            uint256 churned
        )
    {
        MerchantMetrics storage metrics = _merchantMetrics[merchant];
        return (
            metrics.totalSubscribers,
            metrics.activeSubscribers,
            metrics.totalRevenue,
            metrics.monthlyRevenue,
            metrics.churned
        );
    }

    // Internal Functions
    function _processPayment(uint256 subscriptionId) internal {
        Subscription storage sub = _subscriptions[subscriptionId];
        SubscriptionPlan storage plan = _plans[sub.planId];

        uint256 platformFee = (plan.price * platformFeePercent) / 100;
        uint256 merchantPayment = plan.price - platformFee;

        (bool success, ) = payable(plan.merchant).call{value: merchantPayment}(
            ""
        );
        require(success, "Merchant payment failed");

        emit PaymentProcessed(subscriptionId, plan.price);
    }

    function _updateMetrics(uint256 planId, bool newSubscriber) internal {
        MerchantMetrics storage metrics = _merchantMetrics[
            _plans[planId].merchant
        ];
        if (newSubscriber) {
            metrics.totalSubscribers++;
            metrics.activeSubscribers++;
        }
        metrics.totalRevenue += _plans[planId].price;
        metrics.monthlyRevenue += _plans[planId].price;

        emit MetricsUpdated(_plans[planId].merchant);
    }

    function _updateMetricsOnCancellation(uint256 subscriptionId) internal {
        address merchant = _plans[_subscriptions[subscriptionId].planId]
            .merchant;
        MerchantMetrics storage metrics = _merchantMetrics[merchant];
        metrics.activeSubscribers--;
        metrics.churned++;

        emit MetricsUpdated(merchant);
    }

    // Required overrides
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ETH handling
    receive() external payable {}

    fallback() external payable {}
}
