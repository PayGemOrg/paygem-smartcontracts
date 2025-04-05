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
        address merchant;
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
        address merchant;
        uint256 nextBillingDate;
        bool isActive;
        string status;
        uint256 amount;
    }

    struct UserMetrics {
        uint256 totalSubscriptions;
        uint256 activeSubscriptions;
        uint256 totalSpent;
        uint256 monthlySpent;
    }

    struct PaymentProcessed {
        uint256 subscriptionId;
        address user;
        address merchant;
        uint256 planId;
        uint256 amount;
        string status; 
        uint256 timestamp;
    }

    uint256 private serviceCounter;
    uint256 private planCounter;
    uint256 private subscriptionCounter;

    mapping(uint256 => Service) private services;
    mapping(uint256 => Plan) private plans;
    mapping(uint256 => Subscription) private subscriptions;
    mapping(address => Subscription[]) private userSubscriptions;
    mapping(address => Service[]) private merchantServices;
    mapping(address => Plan[]) private merchantPlans;
    mapping(address => PaymentProcessed[]) private userPaymentProcessed;
    mapping(address => UserMetrics) private userMetrics;
    mapping(address => uint256) private userBalances;

    event ServiceCreated(uint256 indexed serviceId, address indexed merchant, string name);
    event PlanCreated(uint256 indexed planId, uint256 indexed serviceId, string name);
    event SubscriptionCreated(uint256 indexed subscriptionId, address indexed user, uint256 planId);
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event ServiceUpdated(uint256 indexed serviceId, string name, string description, string tags);
    event PlanUpdated(uint256 indexed planId, string name, uint256 price, string billingCycle);
    event ServiceDeleted(uint256 indexed serviceId);
    event PlanDeleted(uint256 indexed planId);
    event SubscriptionCancelled(uint256 indexed subscriptionId);
    event PaymentProcessedEvent(uint256 indexed subscriptionId, address indexed user, address indexed merchant, uint256 planId, uint256 amount, string status);


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

    function updateService(uint256 serviceId, string memory name, string memory description, string memory tags) external onlyMerchant(serviceId) {
        Service storage service = services[serviceId];
        service.name = name;
        service.description = description;
        service.tags = tags;
        emit ServiceUpdated(serviceId, name, description, tags);
    }

    function deleteService(uint256 serviceId) external onlyMerchant(serviceId) {
        delete services[serviceId];
        emit ServiceDeleted(serviceId);
    }

    function toggleServiceStatus(uint256 serviceId) external onlyMerchant(serviceId) {
        services[serviceId].isActive = !services[serviceId].isActive;
    }

    function createPlan(
        uint256 serviceId,
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
            msg.sender,
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

    function updatePlan(uint256 planId, string memory name, uint256 price, string memory billingCycle) external {
        Plan storage plan = plans[planId];
        require(services[plan.serviceId].merchant == msg.sender, "Not authorized");
        plan.name = name;
        plan.price = price;
        plan.billingCycle = billingCycle;
        emit PlanUpdated(planId, name, price, billingCycle);
    }

    function deletePlan(uint256 planId) external {
        require(services[plans[planId].serviceId].merchant == msg.sender, "Not authorized");
        delete plans[planId];
        emit PlanDeleted(planId);
    }

    function togglePlanStatus(uint256 planId) external {
        Plan storage plan = plans[planId];
        require(services[plan.serviceId].merchant == msg.sender, "Not authorized");
        plan.isActive = !plan.isActive;
    }

    function getAllServices() external view returns (Service[] memory) {
        Service[] memory allServices = new Service[](serviceCounter);
        for (uint256 i = 1; i <= serviceCounter; i++) {
            allServices[i - 1] = services[i];
        }
        return allServices;
    }

    function getAllPlans() external view returns (Plan[] memory) {
        Plan[] memory allPlans = new Plan[](planCounter);
        for (uint256 i = 1; i <= planCounter; i++) {
            allPlans[i - 1] = plans[i];
        }
        return allPlans;
    }

    function getAllSubscriptions() external view returns (Subscription[] memory) {
        Subscription[] memory allSubscriptions = new Subscription[](subscriptionCounter);
        for (uint256 i = 1; i <= subscriptionCounter; i++) {
            allSubscriptions[i - 1] = subscriptions[i];
        }
        return allSubscriptions;
    }

    function getService(uint256 serviceId) external view returns (Service memory) {
        return services[serviceId];
    }

    function getServiceById(uint256 serviceId) external view returns (Service memory) {
        return services[serviceId];
    }

    function getPlan(uint256 planId) external view returns (Plan memory) {
        return plans[planId];
    }

    function getSubscription(uint256 subscriptionId) external view returns (Subscription memory) {
        return subscriptions[subscriptionId];
    }

    function getUserBalance(address user) external view returns (uint256) {
        return userBalances[user];
    }

    function getUserSubscriptions(address user) external view returns (Subscription[] memory) {
        return userSubscriptions[user];
    }

    function getMerchantServices(address merchant) external view returns (Service[] memory) {
        return merchantServices[merchant];
    }

    function getMerchantPlans(address merchant) external view returns (Plan[] memory) {
        return merchantPlans[merchant];
    }

    function getUserMetrics(address user) external view returns (UserMetrics memory) {
        return userMetrics[user];
    }

    function getUserPaymentProcessed(address user) external view returns (PaymentProcessed[] memory) {
        return userPaymentProcessed[user];
    }


    function createSubscription(uint256 planId) external nonReentrant onlyActivePlan(planId) {
        Plan storage plan = plans[planId];
        require(plan.subscriberCount < plan.subscribersLimit, "Subscriber limit reached");
        require(userBalances[msg.sender] >= plan.price, "Insufficient balance");

        subscriptionCounter++;
        subscriptions[subscriptionCounter] = Subscription(
            subscriptionCounter,
            msg.sender,
            planId,
            plan.merchant,
            block.timestamp + 30 days,
            true,
            "Active",
            plan.price
        );

        userPaymentProcessed[msg.sender].push(PaymentProcessed(
            subscriptionCounter,
            msg.sender,
            plan.merchant,
            planId,
            plan.price,
            "Completed",
            block.timestamp
        ));


        userBalances[msg.sender] -= plan.price;
        userSubscriptions[msg.sender].push(subscriptions[subscriptionCounter]);
        merchantPlans[services[plan.serviceId].merchant].push(plans[planId]);

        userMetrics[msg.sender].totalSubscriptions++;

        emit SubscriptionCreated(subscriptionCounter, msg.sender, planId);
        emit PaymentProcessedEvent(subscriptionCounter, msg.sender, plan.merchant, planId, plan.price, "Completed");}

    function cancelSubscription(uint256 subscriptionId) external nonReentrant {
        Subscription storage subscription = subscriptions[subscriptionId];
        require(subscription.user == msg.sender, "Not authorized");
        require(subscription.isActive, "Subscription is not active");

        subscription.isActive = false;
        plans[subscription.planId].subscriberCount--;

        userMetrics[subscription.user].activeSubscriptions--;
        userMetrics[subscription.user].totalSubscriptions--;
        userMetrics[subscription.user].monthlySpent -= subscription.amount;
        userMetrics[subscription.user].totalSpent -= subscription.amount;

        emit SubscriptionCancelled(subscriptionId);
    }
}
