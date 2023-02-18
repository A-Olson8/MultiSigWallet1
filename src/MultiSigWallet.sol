// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// process flow: to deposit tokens, call depositEth, depositErc20, depositNFT

// to withdraw (must be an owner), call:
// requestEthTransfer() => approveTransaction() (must be called by other owners until numApprovalsRequired is reached) => ExecuteEthTransaction();
// requestErc20Transfer() => approveTransaction() => ExecuteErc20Transaction();
// requestNFTTransfer() => approveTransaction() => ExecuteNFTTransaction();


contract MultiSigState is ReentrancyGuard {
    event EthDeposited(address indexed sender, uint indexed amount, uint ContractBalance);
    event ERC20Deposited(address indexed sender, address indexed token, uint indexed amount, uint ContractBalance);
    event NFTDeposited(address indexed sender, address indexed nftContract, uint indexed tokenId, uint ContractBalance);
    event TransactionRequested(address indexed from, address contractAddress, bool isERC20, bool isNFT, uint indexed txIndex, address indexed to, uint valueOrTokenId, bytes data);
    event TransactionApprovedBy(address indexed from, uint indexed txIndex);
    event ApprovalRevokedBy(address indexed from, uint indexed txIndex);
    event TransactionExecuted(address indexed from, uint indexed txIndex, bool isERC20, bool isNFT);

    address[] public owners;  // array of owners
    uint128 public numApprovalsRequired;  // number of approvals required to transfer ETH, ERC20, or NFT;
    uint128 public transactionKey;  // the transaction index used to calculate the transaction mapping key;
    mapping(address => bool) public isOwner;  // used to confirm address is an owner;
    mapping(uint => mapping(address => bool)) public isApproved;  // mapping from tx index => owner => bool
    mapping(uint128 => Transaction) public transactions;  // array of transactions

    struct Transaction {
        bool isNFT; // will be used for a check in 
        address to;  // to address;
        address tokenContract;  // used in ERC20/NFT transfers, otherwise set to address(0)
        bool isExecuted;  // used in notExecuted modifiers
        uint88 numberOfApprovals;  // everytime an owner approves, this number get incremented until it equals numApprovalsRequested;
        uint valueOrTokenId; // used as value amount in ETH/ERC20 transfers, and used as tokenId for NFT transfers
        bytes data; // any function selector that can be used in sendETHTransaction
    }

    modifier onlyOwners() {  //checks that msg.sender is an owner
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint _txIndex) {  // checks that the tx is within the transactions array
        require(_txIndex <= transactionKey, "tx does not exist");
        _;
    }

    modifier notExecuted(uint128 _txIndex) { // verifies that the tx hasn't been executed
        require(!transactions[_txIndex].isExecuted, "tx already executed");
        _;
    }

    modifier notApproved(uint _txIndex) {  // checks if an owner approved a certain transaction within the isApproved double mapping
        require(!isApproved[_txIndex][msg.sender], "tx already confirmed");  
        _;
    }
}

contract MultiSigTransferLogic is MultiSigState{
    // requests other owners to approve of the eth transfer
    function requestEthTransfer(
        address _to, 
        uint _value, 
        bytes memory _data) 
        external 
        onlyOwners {

        require(address(this).balance >= _value, "Ether balance too low");
        transactionKey++;
        uint128 txIndex = transactionKey;

        transactions[txIndex] = Transaction(false, _to, address(0), false, 0, _value, _data);

        emit TransactionRequested(msg.sender, address(0), false, false, txIndex, _to, _value, _data);
    }

    // requests other owners to approve of the ERC20 transfer
    function requestErc20Transfer(
        address _to, 
        address _contractAddress, 
        uint _value) 
        external 
        onlyOwners { 

        require(IERC20(_contractAddress).balanceOf(address(this)) >= _value, "Token balance too low");
        transactionKey++;
        uint128 txIndex = transactionKey;

        transactions[txIndex] = Transaction(false, _to, _contractAddress, false, 0, _value, "");

        emit TransactionRequested(msg.sender, address(0), true, false, txIndex, _to, _value, "");
    }

    // requests other owners to approve of the NFT transfer
    function requestNFTTransfer(
        address _to, 
        address _contractAddress, 
        uint _tokenId) 
        external 
        onlyOwners { 

        require(IERC721(_contractAddress).ownerOf(_tokenId) == address(this), "Contract does not own token");
        transactionKey++;
        uint128 txIndex = transactionKey; 

        transactions[txIndex] = Transaction(true, _to, _contractAddress, false, 0, _tokenId, "");

        emit TransactionRequested(msg.sender, address(0), false, true, txIndex, _to, _tokenId, "");
    }

    // allows each owner to sign requested transaction (reguardless if it is for Eth, ERC20, or NFT)
    function approveTransaction(
        uint128 _txIndex) 
        external 
        onlyOwners 
        txExists(_txIndex) 
        notExecuted(_txIndex) 
        notApproved(_txIndex) 
        returns (bool approved) {  

        Transaction storage transaction = transactions[_txIndex];
        transaction.numberOfApprovals += 1;
        isApproved[_txIndex][msg.sender] = true;

        emit TransactionApprovedBy(msg.sender, _txIndex);

        return(approved);
    }

    // allows each owner to revoke their approval if they want
    function revokeApproval(
        uint128 _txIndex) 
        external 
        onlyOwners 
        txExists(_txIndex) 
        notExecuted(_txIndex) 
        returns (bool revoked) {   

        Transaction storage transaction = transactions[_txIndex];

        require(isApproved[_txIndex][msg.sender], "tx not confirmed");

        transaction.numberOfApprovals -= 1;
        isApproved[_txIndex][msg.sender] = false;

        emit ApprovalRevokedBy(msg.sender, _txIndex);
        return revoked;
    }

    // allows transaction to execute only if numberOfApprovals within the Transaction struct is >= numApprovalsRequired
    function executeEthTransaction(
        uint128 _txIndex) 
        external 
        onlyOwners 
        txExists(_txIndex) 
        notExecuted(_txIndex) 
        nonReentrant {  

        Transaction storage transaction = transactions[_txIndex];

        require(transaction.numberOfApprovals >= numApprovalsRequired, "Not enough approvals to execute tx");
        require(transaction.isNFT == false && transaction.tokenContract == address(0), "transaction is not an Ether transaction");

        transaction.isExecuted = true;

        (bool success, ) = transaction.to.call{value: transaction.valueOrTokenId}(
            transaction.data
        );
        require(success, "tx failed");

        emit TransactionExecuted(msg.sender, _txIndex, false, false);
    }

    // allows transaction to execute only if numberOfApprovals within the Transaction struct is >= numApprovalsRequired
    function executeErc20Transaction(
        uint128 _txIndex) 
        external 
        onlyOwners 
        txExists(_txIndex) 
        notExecuted(_txIndex) {

        Transaction storage transaction = transactions[_txIndex];
        address token = transaction.tokenContract;

        require(transaction.numberOfApprovals >= numApprovalsRequired, "Not enough approvals to execute tx");
        require(transaction.isNFT == false && token != address(0), "transaction is not ERC20 token");

        transaction.isExecuted = true;

        IERC20(token).transfer(transaction.to, transaction.valueOrTokenId);

        emit TransactionExecuted(msg.sender, _txIndex, true, false);
    }

    // allows transaction to execute only if numberOfApprovals within the Transaction struct is >= numApprovalsRequired
    function executeNFTTransaction(
        uint128 _txIndex) 
        external onlyOwners 
        txExists(_txIndex) 
        notExecuted(_txIndex) {

        Transaction storage transaction = transactions[_txIndex];
        address token = transaction.tokenContract;

        require(transaction.numberOfApprovals >= numApprovalsRequired, "Not enough approvals to execute tx");
        require(transaction.isNFT == true && token != address(0), "transaction is not an NFT Token");

        transaction.isExecuted = true;

        IERC721(token).safeTransferFrom(address(this), transaction.to, transaction.valueOrTokenId);

        emit TransactionExecuted(msg.sender, _txIndex, false, true);
    }
}

contract MultiSigDepositLogic is MultiSigTransferLogic {  
    // for depositing eth;
    function depositEth() external payable onlyOwners {
        emit EthDeposited(msg.sender, msg.value, address(this).balance);  
    }
     
     // must approve on front end or send ERC20 token directly;
    function depositERC20(address _tokenAddress, uint _amount) external onlyOwners {  
        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);

        uint balance = IERC20(_tokenAddress).balanceOf(address(this));

        emit ERC20Deposited(msg.sender, _tokenAddress, _amount, balance);
    }
    
    // allows this contract to run safeTransferFrom on nft contract;
    function onERC721Received(
        address operator, 
        address from, 
        uint256 tokenId, 
        bytes calldata data) 
        external pure
        returns (bytes4){  
        return IERC721Receiver.onERC721Received.selector;
    }

    // must approve on front end or send NFT token directly;
    function depositNFT(address _tokenAddress, uint _tokenId) external onlyOwners {  
        IERC721(_tokenAddress).safeTransferFrom(msg.sender, address(this), _tokenId); 

        uint balance = IERC721(_tokenAddress).balanceOf(address(this));

        emit NFTDeposited(msg.sender, _tokenAddress, _tokenId, balance); 
    }

    // Also used for depositing eth
    receive() external payable {
        emit EthDeposited(msg.sender, msg.value, address(this).balance);
    }
}

contract MultiSigCore is MultiSigDepositLogic {
    constructor(address[] memory _listOfOwners, uint128 _numApprovalsRequired) {
        require(_listOfOwners.length > 0, "owners required");
        require(
            _numApprovalsRequired > 0 &&
                _numApprovalsRequired <= _listOfOwners.length, // the numApprovalsRequired must be > 0 and <= the number of owners;
            "number of required confirmations is out of bount"
        );

        for (uint i = 0; i < _listOfOwners.length; i++) {
            address owner = _listOfOwners[i];

            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");

            isOwner[owner] = true;  // sets owner variables for each owner listed within array
            owners.push(owner);
        }

        numApprovalsRequired = _numApprovalsRequired;
    }

    function getEtherBalance() external view returns(uint) {
        return address(this).balance;
    }

    function getErc20Balance(address _tokenAddress) external view returns(uint) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function getNFTBalance(address _tokenAddress) external view returns(uint) {
        return IERC721(_tokenAddress).balanceOf(address(this));
    }

    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount() public view returns (uint) {
        return transactionKey;
    }

    function getNumberofApprovals(uint128 _index) public view returns (uint88) {
        return transactions[_index].numberOfApprovals;
    }

    function getTransaction(
        uint128 _txIndex
    )
        external
        view
        returns (
            bool isNFT,
            address to,
            address tokenContract,
            uint valueOrTokenId,
            bytes memory data,
            bool isExecuted,
            uint88 numberOfApprovals
        )
    {
        Transaction storage transaction = transactions[_txIndex];

        return (
            transaction.isNFT,
            transaction.to,
            transaction.tokenContract,
            transaction.valueOrTokenId,
            transaction.data,
            transaction.isExecuted,
            transaction.numberOfApprovals
        );
    }
}


