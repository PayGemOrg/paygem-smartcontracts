// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SubscriptionManager is ReentrancyGuard {
    
    struct Service {
        uint256 id;
        address merchant;
        string name;
        string description;
        bool isActive;
        string tags;
    }

    struct Plan {
        uint256 id;
        uint256 serviceId;
        uint256 merchantId;
        string name;
        string description;
        uint256 price;
        string currency;
        string billingCycle; 
        bool isActive;
        uint256 subscribersLimit;
        uint256 subscriberCount;
    }

    struct Subscription {
        uint256 id;
        address user;
        uint256 planId;
        uint256 merchantId;
        uint256 nextBillingDate;
        bool isActive;
        string status;
        uint256 amount;
    }

    struct Transaction {
        uint256 id;
        address user;
        address merchant;
        uint256 planId;
        uint256 amount;
        string serviceName;
        string currency;
        string status; 
        uint256 timestamp;
    }

    
    uint256 private serviceCounter;
    uint256 private planCounter;
    uint256 private subscriptionCounter;
    uint256 private transactionCounter;

    mapping(uint256 => Service) private services;
    mapping(uint256 => Plan) private plans;
    mapping(uint256 => Subscription) private subscriptions;
    mapping(uint256 => Transaction) private transactions;

    mapping(address => uint256) private userBalances;

    
    event ServiceCreated(uint256 indexed serviceId, address indexed merchant, string name);
    event PlanCreated(uint256 indexed planId, uint256 indexed serviceId, string name);
    event SubscriptionCreated(uint256 indexed subscriptionId, address indexed user, uint256 planId);
    event TransactionLogged(
        uint256 indexed transactionId,
        address indexed user,
        address indexed merchant,
        uint256 planId,
        uint256 amount,
        string status
    );
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);

    
    modifier onlyMerchant(uint256 serviceId) {
        require(services[serviceId].merchant == msg.sender, "Not authorized");
        _;
    }

    modifier onlyActiveService(uint256 serviceId) {
        require(services[serviceId].isActive, "Service is not active");
        _;
    }

    modifier onlyActivePlan(uint256 planId) {
        require(plans[planId].isActive, "Plan is not active");
        _;
    }

    
    function deposit() external payable {
        require(msg.value > 0, "Deposit must be greater than zero");
        userBalances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Withdrawal amount must be greater than zero");
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        userBalances[msg.sender] -= amount;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");
        emit Withdrawal(msg.sender, amount);
    }

    
    function createService(string memory name, string memory description, string memory tags) external {
        require(bytes(name).length > 0, "Service name is required");
        serviceCounter++;
        services[serviceCounter] = Service(serviceCounter, msg.sender, name, description, true, tags);
        emit ServiceCreated(serviceCounter, msg.sender, name);
    }

    function toggleServiceStatus(uint256 serviceId) external onlyMerchant(serviceId) {
        services[serviceId].isActive = !services[serviceId].isActive;
    }

    
    function createPlan(
        uint256 serviceId,
        uint256 merchant_id,
        string memory name,
        string memory description,
        uint256 price,
        string memory currency,
        string memory billingCycle,
        uint256 subscribersLimit
    ) external onlyActiveService(serviceId) onlyMerchant(serviceId) {
        require(bytes(name).length > 0, "Plan name is required");
        require(price > 0, "Plan price must be greater than zero");

        planCounter++;
        plans[planCounter] = Plan(
            planCounter,
            serviceId,
            merchant_id,
            name,
            description,
            price,
            currency,
            billingCycle,
            true,
            subscribersLimit,
            0
        );
        emit PlanCreated(planCounter, serviceId, name);
    }

    function togglePlanStatus(uint256 planId) external {
        Plan storage plan = plans[planId];
        require(services[plan.serviceId].merchant == msg.sender, "Not authorized");
        plan.isActive = !plan.isActive;
    }

    
    function createSubscription(uint256 planId, uint256 merchantId, string memory status, uint256 amount) external payable onlyActivePlan(planId) {
        Plan storage plan = plans[planId];
        require(plan.subscribersLimit == 0 || plan.subscriberCount < plan.subscribersLimit, "Subscriber limit reached");
        require(msg.value == plan.price, "Incorrect subscription amount");

        subscriptionCounter++;
        subscriptions[subscriptionCounter] = Subscription(
            subscriptionCounter,
            msg.sender,
            planId,
            merchantId,
            block.timestamp + 30 days,
            true,
            status,
            amount
        );

        userBalances[services[plan.serviceId].merchant] += msg.value;
        plan.subscriberCount++;
        emit SubscriptionCreated(subscriptionCounter, msg.sender, planId);
    }

    
    function makePayment(uint256 subscriptionId) external {
        Subscription storage subscription = subscriptions[subscriptionId];
        require(subscription.isActive, "Subscription is not active");
        require(subscription.user == msg.sender, "Not authorized");

        Plan storage plan = plans[subscription.planId];
        require(userBalances[msg.sender] >= plan.price, "Insufficient balance");

        userBalances[msg.sender] -= plan.price;
        userBalances[services[plan.serviceId].merchant] += plan.price;

        transactionCounter++;
        transactions[transactionCounter] = Transaction(
            transactionCounter,
            msg.sender,
            services[plan.serviceId].merchant,
            plan.id,
            plan.price,
            services[plan.serviceId].name,
            plan.currency,
            "successful",
            block.timestamp
        );
        emit TransactionLogged(transactionCounter, msg.sender, services[plan.serviceId].merchant, plan.id, plan.price, "successful");
    }

    
    function getUserBalance(address user) external view returns (uint256) {
        return userBalances[user];
    }

    function getService(uint256 serviceId) external view returns (Service memory) {
        return services[serviceId];
    }

    function getPlan(uint256 planId) external view returns (Plan memory) {
        return plans[planId];
    }
}
