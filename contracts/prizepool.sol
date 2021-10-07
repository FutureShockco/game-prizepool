pragma solidity 0.8.0;
pragma experimental ABIEncoderV2;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract PrizePoolMerkleRedeem is Ownable {
    using SafeMath for uint256;

    IERC20 public token;

    event Claimed(address _claimant, uint256 _balance); //claimed event
    event NewDelay(uint indexed newDelay); //delay change event
    event NewPercentage(uint indexed newPercentage); //percentage change event

    uint public constant MINIMUM_DELAY = 2 minutes;
    uint public constant MAXIMUM_DELAY = 48 hours;
    uint public constant MAX_PERCENTAGE = 5;
    uint public percentage; //percentage of rewards that can be paid based on total tokens in the contract (minus allocated rewards)
    uint public delay; //delay between each rewards triggering 
    uint public nextAllocation; //timestamp
    uint public totalAllocated; //current allocated rewards
    
    address public admin;

    // Recorded days
    mapping(uint => bytes32) public dayMerkleRoots;
    mapping(uint => mapping(address => bool)) public claimed;

    constructor(address _admin, 
        address _token, uint _delay, uint _percentage
    ) public {
        require(_delay >= MINIMUM_DELAY, "Delay must exceed minimum delay.");
        require(_delay <= MAXIMUM_DELAY, "Delay must not exceed maximum delay.");
        require(_percentage <= MAX_PERCENTAGE, "Percentage must not exceed maximum percentage.");
        admin = _admin;
        token = IERC20(_token);
        delay = _delay;
        percentage = _percentage;
        nextAllocation = 0;
        totalAllocated = 0;
    }

    function disburse(
        address _user,
        uint _balance
    )
        private
    {
        if (_balance > 0) {
            emit Claimed(_user, _balance);
            require(token.transfer(_user, _balance), "ERR_TRANSFER_FAILED");
        }
    }
    
    function getBlockTimestamp() internal view returns (uint) {
        return block.timestamp;
    }
    
    function setDelay(uint _delay) external onlyOwner {
        require(_delay >= MINIMUM_DELAY, "Timelock::setDelay: Delay must exceed minimum delay.");
        require(_delay <= MAXIMUM_DELAY, "Timelock::setDelay: Delay must not exceed maximum delay.");
        delay = _delay;

        emit NewDelay(delay);
    }
    
    function setPercentage(uint _percentage) external onlyOwner {
        require(_percentage <= MAXIMUM_DELAY, "Percentage must not exceed maximum percentage.");
        percentage = _percentage;
        emit NewPercentage(percentage);
    }

    function claimDay(
        address _user,
        uint _day,
        uint _claimedBalance,
        bytes32[] memory _merkleProof
    )
        public
    {
        require(!claimed[_day][_user]);
        require(verifyClaim(_user, _day, _claimedBalance, _merkleProof), 'Incorrect merkle proof');

        claimed[_day][_user] = true;
        totalAllocated -= _claimedBalance;
        disburse(_user, _claimedBalance);
    }

    struct Claim {
        uint day;
        uint balance;
        bytes32[] merkleProof;
    }

    function claimDays(
        address _user,
        Claim[] memory claims
    )
        public
    {
        uint totalBalance = 0;
        Claim memory claim ;
        for(uint i = 0; i < claims.length; i++) {
            claim = claims[i];

            require(!claimed[claim.day][_user]);
            require(verifyClaim(_user, claim.day, claim.balance, claim.merkleProof), 'Incorrect merkle proof');

            totalBalance += claim.balance;
            claimed[claim.day][_user] = true;
        }
        totalAllocated -= totalBalance;
        disburse(_user, totalBalance);
    }

    function claimStatus(
        address _user,
        uint _begin,
        uint _end
    )
        external
        view
        returns (bool[] memory)
    {
        uint size = 1 + _end - _begin;
        bool[] memory arr = new bool[](size);
        for(uint i = 0; i < size; i++) {
            arr[i] = claimed[_begin + i][_user];
        }
        return arr;
    }

    function merkleRoots(
        uint _begin,
        uint _end
    ) 
        external
        view 
        returns (bytes32[] memory)
    {
        uint size = 1 + _end - _begin;
        bytes32[] memory arr = new bytes32[](size);
        for(uint i = 0; i < size; i++) {
            arr[i] = dayMerkleRoots[_begin + i];
        }
        return arr;
    }

    function verifyClaim(
        address _user,
        uint _day,
        uint _claimedBalance,
        bytes32[] memory _merkleProof
    )
        public
        view
        returns (bool valid)
    {
        bytes32 leaf = keccak256(abi.encodePacked(_user, _claimedBalance));
        return MerkleProof.verify(_merkleProof, dayMerkleRoots[_day], leaf);
    }

    function seedAllocations(
        uint _day,
        bytes32 _merkleRoot,
        uint _totalAllocation
    )
        public
    {
        require(msg.sender == admin, "Call must come from admin.");
        require(_totalAllocation <= token.balanceOf(address(this)).sub(totalAllocated).div(100).mul(percentage), "cannot pay more than the defined percentage");
        require(dayMerkleRoots[_day] == bytes32(0), "cannot rewrite merkle root");
        require(nextAllocation <= getBlockTimestamp(), "next allocation block must satisfy delay");
        totalAllocated += _totalAllocation;
        dayMerkleRoots[_day] = _merkleRoot;
        nextAllocation = getBlockTimestamp().add(delay);
    }
    
}
