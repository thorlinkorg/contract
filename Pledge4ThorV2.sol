pragma solidity ^0.6.3;

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function initOwnable() internal{
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    function initPausable() internal{
        _paused = false;
    }
    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {UpgradeableProxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {

    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || _isConstructor() || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    /// @dev Returns true if and only if the function is running in the constructor
    function _isConstructor() private view returns (bool) {
        return !Address.isContract(address(this));
    }
}

interface IOdin{
    function addUserPower(address user, uint256 power) external;
}

contract PledgeContract is Ownable, Pausable, Initializable{ 
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    
    //variant values
    EnumerableSet.Bytes32Set unApprovedRigSet;
    mapping(bytes32 => address) public unApprovedRigBinders;
    mapping(bytes32 => address) public approvedRigBinders;
    mapping(bytes32 => address) public rigOwners;
    mapping(address => EnumerableSet.Bytes32Set) private ownerRigSet;
    mapping(address => uint256) public ownerDeposits;
    mapping(uint256 => bytes32) public blockRigHistory;
    mapping(address => uint256) public ownerLastUnbindTime;
    mapping(bytes32 => uint256) public rigUnbindTime;
    mapping(bytes32 => address) public rigLastOwners;
    uint256 public _requiredBlockNumber;
    uint256 public _totalDeduction;
    uint256 public _addRigFee;
    uint256 public _fuel;
    uint256 public _fuelDelta;
    uint256 public _nextFuel;
    uint256 public _nextFuelDelta;
    uint256 public _nextFuelHeight;
    uint256 public _thorHeight;
    bool public _migrate;
    address public _defaultRigOwner;
    address private _bridge;
    address public _odinContractAddress;//Odin contract address
    
    //constant values
    address payable public constant blackhole = address(0);
    uint256 public constant power2CoinRate = 640; //Percent
    uint256 public constant decimals = 18;
    
    //events
    event InternalTransfer(address indexed from, address indexed to, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event Deposit(address indexed from, uint256 amount);
    event AddRig(bytes32 rig, address indexed binder);
    event TransferRig(bytes32 rig, address indexed newBinder);
    event ApproveRig(bytes32 rig, address indexed binder);
    event RejectRig(bytes32 rig);
    event BindRig(bytes32 rig, address indexed owner);
    event UnBindRig(bytes32 rig, address indexed owner);
    event DeductDeposit(bytes32 rig, uint256 height, address indexed owner, uint256 amount);
    constructor() public { 

    } 
    
    function initialize() public initializer {
        //initialize base contract
        initOwnable();
        initPausable();
        
        _requiredBlockNumber = 8;
        _totalDeduction = 0;
        _addRigFee = 0;
        _fuel = 15000000000000000000000; // value at _thorHeight + 1 (70000)
        _fuelDelta = 130000000000000000; 
        _nextFuel = 15000000000000000000000;
        _nextFuelDelta = 130000000000000000;
        _nextFuelHeight = 70000;
         _thorHeight = 69999;
        _migrate = true;
        _defaultRigOwner = address(0);
        _odinContractAddress = address(0);
    }
    

    /**
     * @dev Throws if called by any account other than the bridge.
     */
    modifier onlyBridge() {
        require(isBridge(), "caller is not the bridge");
        _;
    }


    /**
     * @dev Returns true if the caller is the current bridge.
     */
    function isBridge() public view returns (bool) {
        return _msgSender() == _bridge;
    }
    
    function setBridge(address bridge) onlyOwner public { 
        _bridge = bridge;
    }
    
    function setOdinContractAddress(address odinContractAddress) onlyOwner public { 
        require(Address.isContract(odinContractAddress), "odinContractAddress must be a contract");
        _odinContractAddress = odinContractAddress;
    }
    

    function completeMigrate() onlyOwner public  {
        _migrate = false;
    }
    
    function pause() onlyOwner public  {
        _pause();
    }
    
    function unpause() onlyOwner public  {
        _unpause();
    }
    
    function setAddRigFee(uint256 fee) onlyOwner public { 
        _addRigFee = fee;
    }
    
    function setNextFuel(uint256 nextFuel, uint256 nextFuelDelta, uint256 nextFuelHeight) onlyOwner public { 
        _nextFuel = nextFuel;
        _nextFuelDelta = nextFuelDelta;
        _nextFuelHeight = nextFuelHeight;
    }
    
    function setDefaultRigOwner(address owner)  onlyOwner public { 
        _defaultRigOwner = owner;
    }

    /**
     * Migrate process in last day before 70000 height:
     * 0. Deploy contract with _fuel, _fuelDelta values from old contract, and set _nextFuel, _nextFuelDelta with proper values
     * 1. Add and bind all rigs
     * 2. All existing pools must deposit at least 20 * _fuel  into new contract
     * 3. All existing pools must keep deposit sufficient（1 days fuel) in old contract, and deposit 1 odin into old contract
     * 4. All nodes must switch to new contract address
     * 5. Migrate blockRigHistory, and continue to migrate until 69999
     * 6. Bridge begin to use new contract address at 70000
     * 7. Miners begin to Withdraw from old contract
     * 8. Pause old contract
     */
    function migrateBlockRigHistory(bytes32 [] memory rigs, uint256 [] memory heights) onlyOwner public { 
        require(_migrate, "Migrate is not allowed");
        
        for (uint i = 0; i < rigs.length; i ++){
            if (blockRigHistory[heights[i]] != 0){
                continue;
            }
            blockRigHistory[heights[i]] = rigs[i];
        }
    }
    
    function migrateRigs(bytes32 [] memory rigs, address [] memory binders, address [] memory owners) onlyOwner public { 
        require(_migrate, "Migrate is not allowed");
        
        for (uint i = 0; i < rigs.length; i ++){
            if (rigOwners[rigs[i]] != address(0)){
                continue;
            }
            rigOwners[rigs[i]] = owners[i];
            ownerRigSet[owners[i]].add(rigs[i]);
            approvedRigBinders[rigs[i]] = binders[i];
        }
    }
    
    function setBlockRigHistory(bytes32 rig, uint256 height) onlyOwner public { 
        blockRigHistory[height] = rig;
    }
    
    function addRig(bytes32 rig) whenNotPaused public payable{ 
        uint256 amount = msg.value; 
        require(amount >= _addRigFee, "insufficient add rig fee");
        require(unApprovedRigBinders[rig] == address(0) && approvedRigBinders[rig] == address(0), "rig is added");
        address binder = _msgSender();
        unApprovedRigBinders[rig] = binder;
        unApprovedRigSet.add(rig);
        
        address owner = owner();
        uint256 deposit = ownerDeposits[owner];
        ownerDeposits[owner] = deposit.add(amount);
        
        emit AddRig(rig, binder);
    }
    
    function transferRig(bytes32 rig, address newBinder) whenNotPaused public { 
        require(approvedRigBinders[rig] == _msgSender(), "binder is incorrect or rig is not approved");
        require(rigOwners[rig] == address(0), "Rig must be unbind first");
        
        approvedRigBinders[rig] = newBinder;
        emit TransferRig(rig, newBinder);
    }
    
    /**
     * Bind rig to binder only
     */
    function bindRig(bytes32 rig) whenNotPaused public { 
        require(approvedRigBinders[rig] == _msgSender(), "binder is incorrect or rig is not approved");
        require(rigOwners[rig] == address(0), "Rig is bound already!");
        require(hour() >= rigUnbindTime[rig] + 24, "Rebind rig must be 24 hours later than unbind");
        
        address owner = _msgSender();
        rigOwners[rig] = owner;
        ownerRigSet[owner].add(rig);
        emit BindRig(rig, owner);
    }
    
    function unBindRig(bytes32 rig) whenNotPaused public { 
        require(approvedRigBinders[rig] == _msgSender(), "rig binder is not this user or rig is not approved");
        address owner = rigOwners[rig];
        require(owner != address(0), "Rig is not bound yet!");
        
        rigOwners[rig] = address(0);
        ownerRigSet[owner].remove(rig);
        rigUnbindTime[rig] = hour();
        ownerLastUnbindTime[owner] = hour();
        rigLastOwners[rig] = owner;
        
        emit UnBindRig(rig, owner);
    }
    
    function approveRig(bytes32 rig) onlyOwner public { 
        address binder = unApprovedRigBinders[rig];
        require(binder != address(0), "Rig is not added yet");
        
        approvedRigBinders[rig] = binder;
        unApprovedRigBinders[rig] = address(0);
        unApprovedRigSet.remove(rig);
        
        emit ApproveRig(rig, binder);
    }
    
    function rejectRig(bytes32 rig) onlyOwner public { 
        approvedRigBinders[rig] = address(0);
        unApprovedRigBinders[rig] = address(0);
        unApprovedRigSet.remove(rig);
        address owner = rigOwners[rig];
        if (owner != address(0)){
            rigOwners[rig] = address(0);
            ownerRigSet[owner].remove(rig);
            rigUnbindTime[rig] = hour();
            ownerLastUnbindTime[owner] = hour();
            rigLastOwners[rig] = owner;
        }
        
        emit RejectRig(rig);
    }
    
    function getOwnerRig(address owner, uint256 index) public view returns (bytes32)   {
        return ownerRigSet[owner].at(index);
    }
    
    function getOwnerRigNumber(address owner) public view returns (uint256)   {
        return ownerRigSet[owner].length();
    }
    
    function getUnApprovedRig(uint256 index) public view returns (bytes32)   {
        return unApprovedRigSet.at(index);
    }
     

    /**
     * require fuel * 8 as minimal
     */
    function calcMinimalFuel(uint256 height) public view returns (uint256){ 
    	uint256 minimalFuel = _fuel.mul(_requiredBlockNumber);
        if (height <= _thorHeight) return minimalFuel;//Need 8 blocks fuel during migration period
        
        if (height + _requiredBlockNumber >= _nextFuelHeight){//height + 8  is larger than nextFuelHeight
        	uint256 firstFuelAfterNextHeight = _nextFuel;
            uint256 blocksAfterNextHeight = height.add(_requiredBlockNumber).sub(_nextFuelHeight);
            if (blocksAfterNextHeight > _requiredBlockNumber) {
                blocksAfterNextHeight = _requiredBlockNumber;
                firstFuelAfterNextHeight = (height.sub(_nextFuelHeight)).mul(_nextFuelDelta) + _nextFuel;
            }
            uint256 fuelAfterNextHeight = firstFuelAfterNextHeight.mul(blocksAfterNextHeight)  + _nextFuelDelta.mul(blocksAfterNextHeight.sub(1)).mul(blocksAfterNextHeight).div(2);
            
            uint256 fuelBeforeNextHeight = 0;
            uint256 blocksBeforeNextHeight =  _requiredBlockNumber.sub(blocksAfterNextHeight);
            if (blocksBeforeNextHeight > 0) {
                uint256 firstFuelBeforeNextHeight = (height.sub(_thorHeight).sub(1)).mul(_fuelDelta) + _fuel;
                fuelBeforeNextHeight = firstFuelBeforeNextHeight.mul(blocksBeforeNextHeight) + _fuelDelta.mul(blocksBeforeNextHeight.sub(1)).mul(blocksBeforeNextHeight).div(2);
            }
             
            minimalFuel = fuelAfterNextHeight + fuelBeforeNextHeight;
        }
        else{
            uint256 firstFuel = (height.sub(_thorHeight).sub(1)).mul(_fuelDelta) + _fuel;
            minimalFuel = firstFuel.mul(_requiredBlockNumber) + _fuelDelta.mul(_requiredBlockNumber.sub(1)).mul(_requiredBlockNumber).div(2);
        }
        
        return minimalFuel;
    
    }
    
    /**
     * Check if Rig has enough deposit to mine a Thor block. 
     * This method must be called as soon as a Thor node receives a block of tip or catching blocks
     */
    function isRigEligible(bytes32 rig, uint256 height) whenNotPaused public view returns (bool){ 
        // when the height is new
        if (blockRigHistory[height] == 0){ 
            address rigOwner = rigOwners[rig];
            if (rigOwner == address(0)){
                return false;
            }
            uint256 deposit = ownerDeposits[rigOwner];
            if(deposit > calcMinimalFuel(height)) {//must be larger than minimal for safety reason
                return true;
            }
            else{
                return false;
            }
        }
        // the height is in History
        else if (blockRigHistory[height] == rig){ 
            return true;
        }
        else{
            return false;
        }
    }
    
    /**
     * Deduct the rig's deposit at the time when 8 blocks after a rig produces a Thor block. 
     * This method must be called by the bridge at the time when 8 blocks later than a Thor node receives a block.
     */
    function deductDeposit(bytes32 rig, uint256 height) whenNotPaused onlyBridge public { 
        require(blockRigHistory[height] == 0, "Deduction for this height has been completed already");
        address rigOwner = rigOwners[rig];
        if (rigOwner == address(0)){//may unbind recently
            rigOwner = rigLastOwners[rig];//get owner from last owners
        }
        if (rigOwner == address(0)){//never happen, for safety purpose
            rigOwner = _defaultRigOwner;
        }
        uint256 deposit = ownerDeposits[rigOwner];
        if (height == _nextFuelHeight){
            _fuel = _nextFuel;
            _fuelDelta = _nextFuelDelta;
            _nextFuelHeight = _nextFuelHeight.add(70000);//set the nextFuelHeight temporally
        }
        uint256 deduction = 0;
        if(deposit >= _fuel){
            deduction = _fuel;
        }
        else{
            deduction = deposit;
        }
        
        ownerDeposits[rigOwner] = deposit.sub(deduction);
        _fuel = _fuel.add(_fuelDelta);
        blockRigHistory[height] = rig;
        
        blackhole.transfer(deduction);
        _totalDeduction = _totalDeduction.add(deduction);
        _thorHeight = height;
        
        if(_odinContractAddress != address(0)){
            uint256 powerAdd = deduction.mul(100).div(power2CoinRate).div(10 ** decimals);
            IOdin(_odinContractAddress).addUserPower(rigOwner, powerAdd);
        }
        
        emit InternalTransfer(address(this), blackhole, deduction);
        emit DeductDeposit(rig, height, rigOwner, deduction);
        
    }
    
    /**
    * fallback deposit function
    **/
    receive() whenNotPaused external payable{ 
        address owner = _msgSender();
        uint256 amount = msg.value; 
        uint256 deposit = ownerDeposits[owner];
        ownerDeposits[owner] = deposit.add(amount);
        emit Deposit(owner, amount);
    }
    

    function withdraw() whenNotPaused public { 
        address payable payee = _msgSender();
        require(ownerRigSet[payee].length() == 0, "can not withdraw when the owner has rigs bound");
        require(hour() >= ownerLastUnbindTime[payee] + 24, "Withdraw must be 24 hours later than the last unbind");
        uint256 deposit = ownerDeposits[payee];
        ownerDeposits[payee] = 0;
        
        payee.transfer(deposit);
        emit InternalTransfer(address(this), payee, deposit);
        emit Withdraw(payee, deposit);

    }

    function hour() public view returns (uint256) {
        return block.timestamp / 1 hours;
    }
    
}

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     *
     * _Available since v2.4.0._
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }
}

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}


