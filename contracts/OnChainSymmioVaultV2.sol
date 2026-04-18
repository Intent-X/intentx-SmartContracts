// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IOnChainSymmioVault.sol";
import "./interfaces/ISymmio.sol";

contract OnChainSymmioVaultV2 is
    IOnChainSymmioVault,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable
{
    // Use SafeERC20 for safer token transfers
    using SafeERC20 for IERC20;

    bytes32 public constant BALANCER_ROLE = keccak256("BALANCER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    uint256 public constant MIN_PAYBACK_RATIO = 0.5e18; // 50%
    bytes32 public constant TYPE_HASH = keccak256(
        "WithdrawRequest(uint256 amount,uint256 minAmountOut,address receiver,uint256 nonce,uint256 deadline)"
    );

    ISymmio public symmio;
    address public solver;
    address public signer;
    address public collateralTokenAddress;
    uint256 public lockedBalance;
    uint256 public minimumPaybackRatio;
    uint256 public depositLimit;
    uint256 public currentDeposit;
    uint256 public collateralTokenDecimals;
    WithdrawRequest[] public withdrawRequests;
    uint256 public withdrawalPeriod;
    mapping(address => uint256) public pendingWithdrawalAmount;
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _symmioAddress,
        address _solver,
        address _signer,
        uint256 _minimumPaybackRatio,
        uint256 _depositLimit
    ) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __EIP712_init("OnChainSymmioVaultV2", "1");
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(SETTER_ROLE, _msgSender());

        setSymmioAddress(_symmioAddress);
        setSolver(_solver);
        setDepositLimit(_depositLimit);
        setSigner(_signer);
        setMinimumPaybackRatio(_minimumPaybackRatio);
        _setWithdrawalPeriod(100);
    }

    function deposit(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "SymmioSolverDepositor: Amount must be greater than 0");
        require(currentDeposit + amount <= depositLimit, "SymmioSolverDepositor: Deposit limit reached");

        IERC20 collateralToken = IERC20(collateralTokenAddress);
        collateralToken.safeTransferFrom(_msgSender(), address(this), amount);
        currentDeposit += amount;
        emit Deposit(_msgSender(), amount);

        collateralToken.forceApprove(address(symmio), amount);
        symmio.depositFor(solver, amount);
        emit DepositToSymmio(_msgSender(), solver, amount);
    }

    function requestWithdraw(
        uint256 amount,
        uint256 minAmountOut,
        address receiver,
        uint256 nonce,
        uint256 deadline,
        bytes memory signature
    ) external whenNotPaused {
        require(receiver != address(0), "SymmioSolverDepositor: Zero address for receiver");
        require(deadline > block.timestamp, "SymmioSolverDepositor: Deadline must be in the future");
        require(!usedNonces[receiver][nonce], "SymmioSolverDepositor: Nonce already used");
        require(
            _verifySignature(amount, minAmountOut, receiver, nonce, deadline, signature),
            "SymmioSolverDepositor: Invalid signature"
        );
        usedNonces[receiver][nonce] = true;
        withdrawRequests.push(
            WithdrawRequest({
                sender: _msgSender(),
                receiver: receiver,
                amount: amount,
                minAmountOut: minAmountOut,
                status: RequestStatus.Pending,
                acceptedRatio: 0,
                acceptedWithdrawRequestTimestamp: 0,
                claimableAt: 0
            })
        );
        pendingWithdrawalAmount[_msgSender()] += amount;
        emit WithdrawRequestEvent(withdrawRequests.length - 1, _msgSender(), receiver, amount, nonce);
    }

    function cancelWithdrawRequest(uint256 id) external whenNotPaused {
        require(id < withdrawRequests.length, "SymmioSolverDepositor: Invalid request ID");
        WithdrawRequest storage request = withdrawRequests[id];
        require(request.sender == _msgSender(), "SymmioSolverDepositor: Only the sender of request can cancel it");
        require(request.status == RequestStatus.Pending, "SymmioSolverDepositor: Invalid status");
        request.status = RequestStatus.Canceled;
        pendingWithdrawalAmount[_msgSender()] -= request.amount;
        emit WithdrawRequestCanceled(id);
    }

    function acceptWithdrawRequest(uint256 providedAmount, uint256[] memory _acceptedRequestIds, uint256 _paybackRatio)
        external
        onlyRole(BALANCER_ROLE)
        whenNotPaused
    {
        IERC20(collateralTokenAddress).safeTransferFrom(_msgSender(), address(this), providedAmount);
        require(_paybackRatio >= minimumPaybackRatio, "SymmioSolverDepositor: Payback ratio is too low");
        require(_paybackRatio <= 1e18, "SymmioSolverDepositor: Payback ratio is too high");
        uint256 totalRequiredBalance = lockedBalance;

        for (uint256 i = 0; i < _acceptedRequestIds.length; i++) {
            uint256 id = _acceptedRequestIds[i];
            require(id < withdrawRequests.length, "SymmioSolverDepositor: Invalid request ID");
            require(
                withdrawRequests[id].status == RequestStatus.Pending, "SymmioSolverDepositor: Invalid accepted request"
            );
            uint256 amountOut = (withdrawRequests[id].amount * _paybackRatio) / 1e18;
            require(
                amountOut >= withdrawRequests[id].minAmountOut,
                "SymmioSolverDepositor: Payback ratio is too low for this request"
            );
            totalRequiredBalance += amountOut;
            currentDeposit -= withdrawRequests[id].amount;
            withdrawRequests[id].status = RequestStatus.Ready;
            withdrawRequests[id].acceptedRatio = _paybackRatio;
            withdrawRequests[id].acceptedWithdrawRequestTimestamp = block.timestamp;
            withdrawRequests[id].claimableAt = block.timestamp + withdrawalPeriod;
            pendingWithdrawalAmount[withdrawRequests[id].sender] -= withdrawRequests[id].amount;
        }

        require(
            IERC20(collateralTokenAddress).balanceOf(address(this)) >= totalRequiredBalance,
            "SymmioSolverDepositor: Insufficient contract balance"
        );
        lockedBalance = totalRequiredBalance;
        emit WithdrawRequestAcceptedEvent(providedAmount, _acceptedRequestIds, _paybackRatio);
    }

    function withdrawNotLockedCollateralTokens(address receiver, uint256 amount)
        external
        onlyRole(BALANCER_ROLE)
        whenNotPaused
    {
        require(receiver != address(0), "SymmioSolverDepositor: Zero address for receiver");
        require(amount > 0, "SymmioSolverDepositor: Amount must be greater than 0");
        IERC20 collateralToken = IERC20(collateralTokenAddress);
        uint256 currentBalance = collateralToken.balanceOf(address(this));
        require(amount <= currentBalance - lockedBalance, "SymmioSolverDepositor: Insufficient balance");
        collateralToken.safeTransfer(receiver, amount);
    }

    function claimForWithdrawRequest(uint256 requestId) external whenNotPaused {
        require(requestId < withdrawRequests.length, "SymmioSolverDepositor: Invalid request ID");
        WithdrawRequest storage request = withdrawRequests[requestId];

        require(request.status == RequestStatus.Ready, "SymmioSolverDepositor: Request not ready for withdrawal");

        require(request.claimableAt <= block.timestamp, "SymmioSolverDepositor: Request not pass withdrawal period");

        request.status = RequestStatus.Done;
        uint256 amount = (request.amount * request.acceptedRatio) / 1e18;
        lockedBalance -= amount;
        IERC20(collateralTokenAddress).safeTransfer(request.receiver, amount);
        emit WithdrawClaimedEvent(requestId, request.receiver);
    }

    function setSymmioAddress(address _symmioAddress) public onlyRole(SETTER_ROLE) {
        require(_symmioAddress != address(0), "SymmioSolverDepositor: Zero address");
        symmio = ISymmio(_symmioAddress);
        address beforeCollateral = collateralTokenAddress;
        _updateCollateral();
        require(
            beforeCollateral == collateralTokenAddress || beforeCollateral == address(0),
            "SymmioSolverDepositor: Collateral can not be changed"
        );
        emit SymmioAddressUpdatedEvent(_symmioAddress);
    }

    function setWithdrawalPeriod(uint256 withdrawalPeriod_) public onlyRole(SETTER_ROLE) {
        _setWithdrawalPeriod(withdrawalPeriod_);
    }

    function setSolver(address _solver) public onlyRole(SETTER_ROLE) {
        require(_solver != address(0), "SymmioSolverDepositor: Zero address");
        solver = _solver;
        emit SolverUpdatedEvent(_solver);
    }

    function setSigner(address _signer) public onlyRole(SETTER_ROLE) {
        require(_signer != address(0), "SymmioSolverDepositor: Zero address");
        signer = _signer;
        emit SignerUpdatedEvent(_signer);
    }

    function setDepositLimit(uint256 _depositLimit) public onlyRole(SETTER_ROLE) {
        depositLimit = _depositLimit;
        emit DepositLimitUpdatedEvent(_depositLimit);
    }

    function setMinimumPaybackRatio(uint256 _minimumPaybackRatio) public onlyRole(SETTER_ROLE) {
        require(_minimumPaybackRatio >= MIN_PAYBACK_RATIO, "SymmioSolverDepositor: Minimum buyback ratio is too low");
        require(_minimumPaybackRatio <= 1e18, "SymmioSolverDepositor: Minimum buyback ratio is too high");
        minimumPaybackRatio = _minimumPaybackRatio;
        emit MinimumPaybackRatioUpdatedEvent(_minimumPaybackRatio);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function _setWithdrawalPeriod(uint256 withdrawalPeriod_) internal {
        withdrawalPeriod = withdrawalPeriod_;
        emit WithdrawalPeriodUpdate(withdrawalPeriod_);
    }

    function _updateCollateral() internal {
        collateralTokenAddress = symmio.getCollateral();
        collateralTokenDecimals = IERC20Metadata(collateralTokenAddress).decimals();
        require(
            collateralTokenDecimals <= 18,
            "SymmioSolverDepositor: Collateral decimals should be lower than or equal to 18"
        );
    }

    function _verifySignature(
        uint256 amount,
        uint256 minAmountOut,
        address receiver,
        uint256 nonce,
        uint256 deadline,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 hash =
            _hashTypedDataV4(keccak256(abi.encode(TYPE_HASH, amount, minAmountOut, receiver, nonce, deadline)));
        address realSigner = ECDSA.recover(hash, signature);
        return signer == realSigner;
    }
}