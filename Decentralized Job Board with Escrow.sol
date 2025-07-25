// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Job Board with Escrow
 * @dev A trustless platform for freelance work with automatic escrow and payment release
 */
contract Project {
    
    // Enums
    enum JobStatus { Open, InProgress, Completed, Disputed, Cancelled }
    enum DisputeStatus { None, Raised, Resolved }
    
    // Structs
    struct Job {
        uint256 id;
        string title;
        string description;
        uint256 payment;
        address employer;
        address freelancer;
        JobStatus status;
        uint256 deadline;
        DisputeStatus disputeStatus;
        uint256 createdAt;
    }
    
    struct Dispute {
        uint256 jobId;
        string reason;
        address raisedBy;
        uint256 createdAt;
        bool resolved;
    }
    
    // State variables
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => Dispute) public disputes;
    mapping(address => uint256[]) public employerJobs;
    mapping(address => uint256[]) public freelancerJobs;
    mapping(address => uint256) public userRatings; // Simple rating system (out of 100)
    mapping(address => uint256) public totalRatingsReceived;
    
    uint256 public jobCounter;
    uint256 public platformFeePercentage = 25; // 2.5% platform fee (25/1000)
    address public owner;
    
    // Events
    event JobCreated(uint256 indexed jobId, address indexed employer, string title, uint256 payment);
    event JobAccepted(uint256 indexed jobId, address indexed freelancer);
    event JobCompleted(uint256 indexed jobId, address indexed freelancer);
    event PaymentReleased(uint256 indexed jobId, address indexed freelancer, uint256 amount);
    event DisputeRaised(uint256 indexed jobId, address indexed raisedBy, string reason);
    event DisputeResolved(uint256 indexed jobId, address winner, uint256 amount);
    event JobCancelled(uint256 indexed jobId, address indexed employer);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier jobExists(uint256 _jobId) {
        require(_jobId > 0 && _jobId <= jobCounter, "Job does not exist");
        _;
    }
    
    modifier onlyEmployer(uint256 _jobId) {
        require(jobs[_jobId].employer == msg.sender, "Only employer can call this function");
        _;
    }
    
    modifier onlyFreelancer(uint256 _jobId) {
        require(jobs[_jobId].freelancer == msg.sender, "Only assigned freelancer can call this function");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        jobCounter = 0;
    }
    
    /**
     * @dev Core Function 1: Create a new job posting with escrowed payment
     * @param _title Job title
     * @param _description Job description
     * @param _deadline Job deadline (timestamp)
     */
    function createJob(
        string memory _title,
        string memory _description,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Payment must be greater than 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        
        jobCounter++;
        
        jobs[jobCounter] = Job({
            id: jobCounter,
            title: _title,
            description: _description,
            payment: msg.value,
            employer: msg.sender,
            freelancer: address(0),
            status: JobStatus.Open,
            deadline: _deadline,
            disputeStatus: DisputeStatus.None,
            createdAt: block.timestamp
        });
        
        employerJobs[msg.sender].push(jobCounter);
        
        emit JobCreated(jobCounter, msg.sender, _title, msg.value);
    }
    
    /**
     * @dev Core Function 2: Accept a job and start working (freelancer applies)
     * @param _jobId ID of the job to accept
     */
    function acceptJob(uint256 _jobId) external jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(job.status == JobStatus.Open, "Job is not available");
        require(job.employer != msg.sender, "Employer cannot accept their own job");
        require(block.timestamp < job.deadline, "Job deadline has passed");
        
        job.freelancer = msg.sender;
        job.status = JobStatus.InProgress;
        
        freelancerJobs[msg.sender].push(_jobId);
        
        emit JobAccepted(_jobId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Complete job and release payment automatically
     * @param _jobId ID of the job to complete
     * @param _rating Rating for the employer (1-100)
     */
    function completeJob(uint256 _jobId, uint256 _rating) external jobExists(_jobId) onlyFreelancer(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(job.status == JobStatus.InProgress, "Job is not in progress");
        require(job.disputeStatus == DisputeStatus.None, "Job has an active dispute");
        require(_rating >= 1 && _rating <= 100, "Rating must be between 1 and 100");
        
        job.status = JobStatus.Completed;
        
        // Calculate platform fee
        uint256 platformFee = (job.payment * platformFeePercentage) / 1000;
        uint256 freelancerPayment = job.payment - platformFee;
        
        // Update employer rating
        userRatings[job.employer] = (userRatings[job.employer] * totalRatingsReceived[job.employer] + _rating) / (totalRatingsReceived[job.employer] + 1);
        totalRatingsReceived[job.employer]++;
        
        // Transfer payments
        payable(msg.sender).transfer(freelancerPayment);
        payable(owner).transfer(platformFee);
        
        emit JobCompleted(_jobId, msg.sender);
        emit PaymentReleased(_jobId, msg.sender, freelancerPayment);
    }
    
    // Additional utility functions
    
    /**
     * @dev Cancel a job (only employer, only if not started)
     * @param _jobId ID of the job to cancel
     */
    function cancelJob(uint256 _jobId) external jobExists(_jobId) onlyEmployer(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(job.status == JobStatus.Open, "Can only cancel open jobs");
        
        job.status = JobStatus.Cancelled;
        
        // Refund employer
        payable(job.employer).transfer(job.payment);
        
        emit JobCancelled(_jobId, msg.sender);
    }
    
    /**
     * @dev Raise a dispute for a job
     * @param _jobId ID of the job to dispute
     * @param _reason Reason for the dispute
     */
    function raiseDispute(uint256 _jobId, string memory _reason) external jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(job.status == JobStatus.InProgress, "Job must be in progress to dispute");
        require(job.disputeStatus == DisputeStatus.None, "Dispute already exists");
        require(msg.sender == job.employer || msg.sender == job.freelancer, "Only job parties can raise disputes");
        require(bytes(_reason).length > 0, "Dispute reason cannot be empty");
        
        job.disputeStatus = DisputeStatus.Raised;
        
        disputes[_jobId] = Dispute({
            jobId: _jobId,
            reason: _reason,
            raisedBy: msg.sender,
            createdAt: block.timestamp,
            resolved: false
        });
        
        emit DisputeRaised(_jobId, msg.sender, _reason);
    }
    
    /**
     * @dev Resolve dispute (only owner/admin)
     * @param _jobId ID of the job with dispute
     * @param _winner Address of the dispute winner
     */
    function resolveDispute(uint256 _jobId, address _winner) external jobExists(_jobId) onlyOwner {
        Job storage job = jobs[_jobId];
        Dispute storage dispute = disputes[_jobId];
        
        require(job.disputeStatus == DisputeStatus.Raised, "No active dispute");
        require(_winner == job.employer || _winner == job.freelancer, "Winner must be job party");
        
        job.disputeStatus = DisputeStatus.Resolved;
        job.status = JobStatus.Disputed;
        dispute.resolved = true;
        
        // Award payment to winner
        payable(_winner).transfer(job.payment);
        
        emit DisputeResolved(_jobId, _winner, job.payment);
    }
    
    /**
     * @dev Get job details
     * @param _jobId ID of the job
     */
    function getJob(uint256 _jobId) external view jobExists(_jobId) returns (Job memory) {
        return jobs[_jobId];
    }
    
    /**
     * @dev Get user's jobs as employer
     * @param _user User address
     */
    function getEmployerJobs(address _user) external view returns (uint256[] memory) {
        return employerJobs[_user];
    }
    
    /**
     * @dev Get user's jobs as freelancer
     * @param _user User address
     */
    function getFreelancerJobs(address _user) external view returns (uint256[] memory) {
        return freelancerJobs[_user];
    }
    
    /**
     * @dev Get user rating
     * @param _user User address
     */
    function getUserRating(address _user) external view returns (uint256) {
        return userRatings[_user];
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFeePercentage New fee percentage (in basis points, e.g., 25 = 2.5%)
     */
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 100, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }
    
    /**
     * @dev Get contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
