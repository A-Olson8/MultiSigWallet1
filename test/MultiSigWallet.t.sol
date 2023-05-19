// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/MultiSigWallet.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC721.sol";
import "./TestHelper.sol";

// 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84 address(this)
// 0xEFc56627233b02eA95bAE7e19F648d7DcD5Bb132 multisig
// 0xCe71065D4017F316EC606Fe4422e11eB2c47c246 token
// 0x185a4dc360CE69bDCceE33b3784B0282f7961aea nft

contract MultiSigTest1 is Test {
    MultiSigCore public multiSig; // main contract
    MockERC20 public token; 
    MockNFT public nft; 
    MultiSigTest2 public test2;  // test2 and test3 are used for the other two multiSig wallets..all the testing is done in MultiSigTest1
    MultiSigTest3 public test3;
    MultiSigTest4 public test4; // test4 is used to test that onlyOwner works (it is not an owner)

    address adr1 = address(this); // The three multiSig wallets used passed into constructor
    address adr2 = address(test2);
    address adr3 = address(test3);

    // sets all the above addresses
    function setUp() public {
        test2 = new MultiSigTest2();
        test3 = new MultiSigTest3();
        test4 = new MultiSigTest4();
        token = new MockERC20(address(test3));
        adr1 = address(this);
        adr2 = address(test2);
        adr3 = address(test3);
        nft = new MockNFT();
        nft.safeMint(address(test2), 0);
        nft.safeMint(address(test2), 1);
        address[] memory sigs = new address[](3);
        sigs[0] = adr1;
        sigs[1] = adr2;
        sigs[2] = adr3;
        multiSig = new MultiSigCore(sigs, 3);
    }

    // The three tests below are for transferring Eth, erc20, and nft tokens to the multiSig wallet;
    function testETHDeposit(uint96 _amount) public {
        multiSig.depositEth{value: _amount}();
        uint balance = multiSig.getEtherBalance();
        assertEq(balance, _amount);
    }

    function testNFTDeposit() public {
        test2.transferNFT(address(nft), address(multiSig), 0); // transfers two nfts and checks balance
        test2.transferNFT(address(nft), address(multiSig), 1);
        uint balance = multiSig.getNFTBalance(address(nft));
        assertEq(balance, 2);
    }

    function testERC20Deposit(uint96 _amount) public {
        test3.transferERC20(address(token), address(multiSig), _amount);
        uint balance = multiSig.getErc20Balance(address(token));
        assertEq(balance, _amount);
    }

    //the 4 functions below are for testing the modifiers in MultiSig
    function testOnlyOwner() public {
        vm.expectRevert(notOwner.selector);
        test4.checkOnlyOwner(address(multiSig), 0); // test4 is not an owner
    }

    function testTransactionExists() public {
        vm.expectRevert(TxDoesNotExist.selector);
        multiSig.revokeApproval(1);
    }

    function testNotEcecuted(uint96 _amount) public {
        multiSig.depositEth{value: _amount}();
        multiSig.requestEthTransfer(adr2, _amount, "");

        multiSig.approveTransaction(1); // three approvals
        test2.approveTransfer(address(multiSig), 1);
        test3.approveTransfer(address(multiSig), 1);
        multiSig.executeEthTransaction(1); // executes transaction

        vm.expectRevert(TxAlreadyExecuted.selector);
        multiSig.executeEthTransaction(1);
    }

    function testNotApproved(uint96 _amount) public {
        multiSig.depositEth{value: _amount}();
        multiSig.requestEthTransfer(adr2, _amount, "");

        test2.approveTransfer(address(multiSig), 1); // approves once
        vm.expectRevert(TxAlreadyConfirmed.selector);
        test2.approveTransfer(address(multiSig), 1); // can't approve twice
    }

    // Tests that the approvals will increment when they are supposed to, and that they will be revoked when revokeApproval is called;
    function testApproveThenRevoke(uint96 _amount) public {
        multiSig.depositEth{value: _amount}();
        multiSig.requestEthTransfer(adr2, _amount, "");

        multiSig.approveTransaction(1); // approve
        test2.approveTransfer(address(multiSig), 1); // approve
        test3.approveTransfer(address(multiSig), 1); // approve

        uint88 numberOfApproved = multiSig.getNumberofApprovals(1);
        assertEq(numberOfApproved, 3);

        multiSig.revokeApproval(1); // revoke
        test2.revokeApproveTransfer(address(multiSig), 1); // revoke
        test3.revokeApproveTransfer(address(multiSig), 1); // revoke

        uint88 numberOfApproved2 = multiSig.getNumberofApprovals(1);
        assertEq(numberOfApproved2, 0);
    }

    // The 3 functions below are testing that the require statements that check the balances actually works (lines 65, 82, 99)

    function testBalancerevert1(uint96 _amount) public { // line 65
        vm.assume(_amount < type(uint96).max);
        multiSig.depositEth{value: _amount}();
        vm.expectRevert(EtherBalanceTooLow.selector);
        multiSig.requestEthTransfer(adr1, _amount + 1, "");
    }

    function testBalancerevert2(uint96 _amount) public { // line 82
        vm.assume(_amount < type(uint96).max);
        test3.transferERC20(address(token), address(multiSig), _amount);
        vm.expectRevert(TokenBalanceTooLow.selector);
        test2.requestERC20Transfer(address(multiSig), address(token), adr2, _amount + 1);
    }

    function testBalancerevert3() public { // line 99
        test2.transferNFT(address(nft), address(multiSig), 0);
        vm.expectRevert(ContractDoesNotOwnToken.selector);
        test3.requestNFTTransfer(address(multiSig), address(nft), adr1, 1);
    }

    // The 3 functions below are testing that approved eth transfers can't be used in the executeErc20Transaction or executeNFTTransaction...
    // Or that approved ERC20 transfers can't be used in the executeEthTransaction or executeNFTTransaction...
    // Or that NFT transfers can't be used in the executeEthTransaction or executeErc20Transaction functions (lines 159, 183, 203)

    function testTransactionRevert1(uint96 _amount, uint96 _amountToSend) public { // line 159
        vm.assume(_amount >= _amountToSend && _amountToSend > 0);
        multiSig.depositEth{value: _amount}();
        test3.requestEthTransfer(address(multiSig), adr1, _amountToSend);

        multiSig.approveTransaction(1);
        test2.approveTransfer(address(multiSig), 1);
        test3.approveTransfer(address(multiSig), 1);

        vm.expectRevert(TransactionIsNotERC20Token.selector);
        multiSig.executeErc20Transaction(1);

        vm.expectRevert(TransactionIsNotAnNFTToken.selector); // can only be used for eth transaction
        test3.executeNFTTransaction(address(multiSig), 1);
    }

    function testTransactionRevert2(uint96 _amount, uint96 _amountToSend) public { // line 183
        vm.assume(_amount >= _amountToSend && _amountToSend > 0);
        test3.transferERC20(address(token), address(multiSig), _amount);
        multiSig.requestErc20Transfer(adr3, address(token), _amountToSend);

        multiSig.approveTransaction(1);
        test2.approveTransfer(address(multiSig), 1);
        test3.approveTransfer(address(multiSig), 1);

        vm.expectRevert(TransactionIsNotAnEtherTransaction.selector);
        test2.executeEthTransaction(address(multiSig), 1);
        vm.expectRevert(TransactionIsNotAnNFTToken.selector); // can only be used for an erc20 transaction
        test3.executeNFTTransaction(address(multiSig), 1);
    }

    function testTransactionRevert3() public { // line 203
        test2.transferNFT(address(nft), address(multiSig), 1);
        test3.requestNFTTransfer(address(multiSig), address(nft), adr3, 1);

        multiSig.approveTransaction(1);
        test2.approveTransfer(address(multiSig), 1);
        test3.approveTransfer(address(multiSig), 1);

        vm.expectRevert(TransactionIsNotAnEtherTransaction.selector);
        test3.executeEthTransaction(address(multiSig), 1);
        vm.expectRevert(TransactionIsNotERC20Token.selector); // can only be used on an erc20 transaction
        multiSig.executeErc20Transaction(1);
    }

    // The functions below are testing if the executeEthTransaction, executeErc20Transaction, or executeNFTTransaction...
    // revert if there is not enough approvals to execute these transactions (lines 158, 182, 202)

    function testlowApprovalEth(uint96 _amount, uint96 _amountToSend) public  { // line 158
        vm.assume(_amount >= _amountToSend && _amountToSend > 0);
        multiSig.depositEth{value: _amount}();
        test3.requestEthTransfer(address(multiSig), adr1, _amountToSend);
        
        test2.approveTransfer(address(multiSig), 1); // approval 1
        vm.expectRevert(NotEnoughApprovalsToExecuteTx.selector);
        test2.executeEthTransaction(address(multiSig), 1);

        test3.approveTransfer(address(multiSig), 1); // approval 2 (3 needed)
        vm.expectRevert(NotEnoughApprovalsToExecuteTx.selector);
        test3.executeEthTransaction(address(multiSig), 1);
    }

    function testlowApprovalErc20(uint96 _amount, uint96 _amountToSend) public { // line 182
        vm.assume(_amount >= _amountToSend && _amountToSend > 0);
        test3.transferERC20(address(token), address(multiSig), _amount);
        multiSig.requestErc20Transfer(adr3, address(token), _amountToSend);

        multiSig.approveTransaction(1); // approval 1
        vm.expectRevert(NotEnoughApprovalsToExecuteTx.selector);
        multiSig.executeErc20Transaction(1);

        test2.approveTransfer(address(multiSig), 1); // approval 2
        vm.expectRevert(NotEnoughApprovalsToExecuteTx.selector);
        multiSig.executeErc20Transaction(1);
    }

    function testlowApprovalNFT() public { // line 182
        test2.transferNFT(address(nft), address(multiSig), 1);
        test3.requestNFTTransfer(address(multiSig), address(nft), adr3, 1);

        multiSig.approveTransaction(1); // approval 1
        vm.expectRevert(NotEnoughApprovalsToExecuteTx.selector);
        test3.executeNFTTransaction(address(multiSig), 1);

        test3.approveTransfer(address(multiSig), 1); // approval 2
        vm.expectRevert(NotEnoughApprovalsToExecuteTx.selector);
        test2.executeNFTTransaction(address(multiSig), 1);
    }

    // The function below checks that the transactionKey actually increments with each new transaction 

    function testTransactionKeyIncrement(uint96 _amount, uint96 _amountToSend) public {
        vm.assume(_amount >= _amountToSend && _amountToSend > 0);
        multiSig.depositEth{value: _amount}();
        test3.requestEthTransfer(address(multiSig), adr1, _amountToSend);
        uint key = multiSig.getTransactionCount();
        assertEq(key, 1); // nonce/key = 1

        test3.transferERC20(address(token), address(multiSig), _amount);
        multiSig.requestErc20Transfer(adr3, address(token), _amountToSend);
        uint key2 = multiSig.getTransactionCount();
        assertEq(key2, 2); // key = 2

        test2.transferNFT(address(nft), address(multiSig), 1);
        test2.requestNFTTransfer(address(multiSig), address(nft), adr1, 1);
        uint key3 = multiSig.getTransactionCount();
        assertEq(key3, 3); // key = 3
    }


    // The functions below test that the transactions actually go through when modifiers and require statements are passed

    function testEthTransaction(uint96 _amount, uint96 _amountToSend) public {
        vm.assume(_amount >= _amountToSend && _amountToSend > 0);
        multiSig.depositEth{value: _amount}();
        test2.requestEthTransfer(address(multiSig), adr1, _amountToSend);
        multiSig.approveTransaction(1);
        test2.approveTransfer(address(multiSig), 1);
        test3.approveTransfer(address(multiSig), 1); 

        test2.executeEthTransaction(address(multiSig), 1); // transfer eth

        uint balance1 = multiSig.getEtherBalance();
        assertEq(balance1, _amount - _amountToSend);
    }

    function testErc20Transaction(uint96 _amount, uint96 _amountToSend) public {
        vm.assume(_amount >= _amountToSend && _amountToSend > 0);
        test3.transferERC20(address(token), address(multiSig), _amount);
        multiSig.requestErc20Transfer(adr1, address(token), _amountToSend);
        multiSig.approveTransaction(1);
        test2.approveTransfer(address(multiSig), 1);
        test3.approveTransfer(address(multiSig), 1);

        multiSig.executeErc20Transaction(1); // transfer erc20

        uint balance1 = IERC20(address(token)).balanceOf(address(multiSig));
        uint balance2 = IERC20(address(token)).balanceOf(adr1);
        assertEq(balance1, _amount - _amountToSend);
        assertEq(balance2, _amountToSend);
    }

    function testNFTTransaction() public {
        test2.transferNFT(address(nft), address(multiSig), 0);
        test2.transferNFT(address(nft), address(multiSig), 1);
        test2.requestNFTTransfer(address(multiSig), address(nft), adr1, 1);
        multiSig.approveTransaction(1);
        test2.approveTransfer(address(multiSig), 1);
        test3.approveTransfer(address(multiSig), 1);

        test2.executeNFTTransaction(address(multiSig), 1); // execute nft transaction

        uint balance1 = IERC721(address(nft)).balanceOf(address(multiSig));
        uint balance2 = IERC721(address(nft)).balanceOf(adr1);
        assertEq(balance1, balance2);
    }

    // used to receive nft
    function onERC721Received(
        address operator, 
        address from, 
        uint256 tokenId, 
        bytes calldata data) 
        external pure
        returns (bytes4){  
        return IERC721Receiver.onERC721Received.selector;
    }

    // for receiving eth in testEthTransaction()
    receive() external payable {}
}







