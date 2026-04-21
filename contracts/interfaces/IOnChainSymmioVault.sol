// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

interface IOnChainSymmioVault {
    struct WithdrawRequest {
        address receiver;
        address sender;
        uint256 amount;
        uint256 minAmountOut;
        RequestStatus status;
        uint256 acceptedAmount;
        uint256 acceptedWithdrawRequestTimestamp;
        uint256 claimableAt;
    }

    enum RequestStatus {
        Pending,
        Ready,
        Done,
        Canceled,
        Rejected
    }

    event WithdrawalPeriodUpdate(uint256 withdrawalPeriod);

    event Deposit(address indexed depositor, uint256 amount);
    event WithdrawRequestEvent(
        uint256 indexed requestId, address indexed sender, address indexed receiver, uint256 amount, uint256 nonce
    );
    event WithdrawRequestCanceled(uint256 indexed requestId);
    event WithdrawRequestRejected(uint256 indexed requestId);
    event WithdrawRequestAcceptedEvent(uint256 providedAmount, uint256[] acceptedRequestIds, uint256[] _acceptedAmounts);
    event WithdrawClaimedEvent(uint256 indexed requestId, address indexed receiver);
    event SymmioAddressUpdatedEvent(address indexed newSymmioAddress);
    event DepositLimitUpdatedEvent(uint256 depositLimit);
    event MinimumPaybackRatioUpdatedEvent(uint256 minimumPaybackRatio);
    event SolverUpdatedEvent(address indexed solver);
    event DepositToSymmio(address indexed depositor, address indexed solver, uint256 amount);
    event SignerUpdatedEvent(address indexed signer);
}