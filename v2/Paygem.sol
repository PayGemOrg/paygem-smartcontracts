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
    event TransactionLogged(uint256 indexed transactionId, address indexed user, address indexed merchant, uint256 planId, uint256 amount, string status);
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event ServiceUpdated(uint256 indexed serviceId, string name, string description, string tags);
    event PlanUpdated(uint256 indexed planId, string name, uint256 price, string billingCycle);
    event ServiceDeleted(uint256 indexed serviceId);
    event PlanDeleted(uint256 indexed planId);

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
        uint256 merchantId,
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
            merchantId,
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

    function getAllTransactions() external view returns (Transaction[] memory) {
        Transaction[] memory allTransactions = new Transaction[](transactionCounter);
        for (uint256 i = 1; i <= transactionCounter; i++) {
            allTransactions[i - 1] = transactions[i];
        }
        return allTransactions;
    }

    function getService(uint256 serviceId) external view returns (Service memory) {
        return services[serviceId];
    }

    function getPlan(uint256 planId) external view returns (Plan memory) {
        return plans[planId];
    }

    function getUserBalance(address user) external view returns (uint256) {
        return userBalances[user];
    }
}
