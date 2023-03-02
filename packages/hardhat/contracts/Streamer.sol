// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Streamer is Ownable {
    event Opened(address, uint256);
    event Challenged(address);
    event Withdrawn(address, uint256);
    event Closed(address);

    mapping(address => uint256) balances;
    mapping(address => uint256) canCloseAt;
     bool locked;
     modifier Guard {
        require(!locked,"re-entrancy!");
        locked = true;
        _;
        locked = false;
    }


    function fundChannel() public payable {
        /*
        Checkpoint 3: fund a channel
        complete this function so that it:
        - reverts if msg.sender already has a running channel (ie, if balances[msg.sender] != 0)
        - updates the balances mapping with the eth received in the function call
        - emits an Opened event
        */
        require(
            balances[msg.sender] == 0,
            "sender is already running the channel"
        );
        balances[msg.sender] = msg.value;
        emit Opened(msg.sender, msg.value);
    }

    function timeLeft(address channel) public view returns (uint256) {
        require(canCloseAt[channel] != 0, "channel is not closing");
        return canCloseAt[channel] - block.timestamp;
    }

    function withdrawEarnings(Voucher calldata voucher) public onlyOwner {
        // like the off-chain code, signatures are applied to the hash of the data
        // instead of the raw data itself
        bytes32 hashed = keccak256(abi.encode(voucher.updatedBalance));

        // The prefix string here is part of a convention used in ethereum for signing
        // and verification of off-chain messages. The trailing 32 refers to the 32 byte
        // length of the attached hash message.
        //
        // There are seemingly extra steps here compared to what was done in the off-chain
        // `reimburseService` and `processVoucher`. Note that those ethers signing and verification
        // functions do the same under the hood.
        //
        // again, see https://blog.ricmoo.com/verifying-messages-in-solidity-50a94f82b2ca
        bytes memory prefixed = abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            hashed
        );
        bytes32 prefixedHashed = keccak256(prefixed);

        address clientAddr = ecrecover(
            prefixedHashed,
            voucher.sig.v,
            voucher.sig.r,
            voucher.sig.s
        );
        require(
            balances[clientAddr] != 0 &&
                balances[clientAddr] > voucher.updatedBalance,
            "no running channel or not enough funds"
        );
        uint256 payment = balances[clientAddr] - voucher.updatedBalance;
        balances[clientAddr] -= payment;
        (bool sent, ) = payable(owner()).call{value: payment}("");
        require(sent, "failed to transfer eth");
        emit Withdrawn(clientAddr, payment);
    }

    /*
    Checkpoint 6a: Challenge the channel

    create a public challengeChannel() function that:
    - checks that msg.sender has an open channel
    - updates canCloseAt[msg.sender] to some future time
    - emits a Challenged event
    */
    function challengeChannel() public {
        require(balances[msg.sender] != 0, "no running channel");
        canCloseAt[msg.sender] += block.timestamp + 30 seconds;
        emit Challenged(msg.sender);
    }

    /*
    Checkpoint 6b: Close the channel

    create a public defundChannel() function that:
    - checks that msg.sender has a closing channel
    - checks that the current time is later than the closing time
    - sends the channel's remaining funds to msg.sender, and sets the balance to 0
    - emits the Closed event
    */
  
    function defundChannel() public Guard {
        require(canCloseAt[msg.sender]!=0, "no closing channel");
        require(block.timestamp >= canCloseAt[msg.sender], "time is not up");
        (bool sent,) = payable(msg.sender).call{value: balances[msg.sender]}("");
        require(sent, "failed to transfer eth");
        balances[msg.sender] = 0;
        emit Closed(msg.sender);
    }

    struct Voucher {
        uint256 updatedBalance;
        Signature sig;
    }
    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }
}
