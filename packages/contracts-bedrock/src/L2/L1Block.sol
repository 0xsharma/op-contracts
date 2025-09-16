// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Libraries
import { Constants } from "src/libraries/Constants.sol";
import { NotDepositor } from "src/libraries/L1BlockErrors.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000015
/// @title L1Block
/// @notice Provides the last known L1 block information to the L2 system. Values are updated
///         every epoch by the depositor account. This version includes support for a custom
///         gas token multiplier that scales fee scalars proportionally.
contract L1Block is ISemver {
    /// @notice Address of the special depositor account.
    function DEPOSITOR_ACCOUNT() public pure returns (address addr_) {
        addr_ = Constants.DEPOSITOR_ACCOUNT;
    }

    /// @notice The latest L1 block number known by the L2 system.
    uint64 public number;

    /// @notice The latest L1 timestamp known by the L2 system.
    uint64 public timestamp;

    /// @notice The latest L1 base fee.
    uint256 public basefee;

    /// @notice The latest L1 blockhash.
    bytes32 public hash;

    /// @notice The number of L2 blocks in the same epoch.
    uint64 public sequenceNumber;

    /// @notice The scalar value applied to the L1 blob base fee portion of the cost func.
    uint32 public blobBaseFeeScalar;

    /// @notice The scalar value applied to the L1 base fee portion of the cost func.
    uint32 public baseFeeScalar;

    /// @notice The versioned hash to authenticate the batcher by.
    bytes32 public batcherHash;

    /// @notice The overhead value applied to the L1 portion of the transaction fee.
    /// @custom:legacy
    uint256 public l1FeeOverhead;

    /// @notice The scalar value applied to the L1 portion of the transaction fee.
    /// @custom:legacy
    uint256 public l1FeeScalar;

    /// @notice The latest L1 blob base fee.
    uint256 public blobBaseFee;

    /// @notice The constant value applied to the operator fee.
    uint64 public operatorFeeConstant;

    /// @notice The scalar value applied to the operator fee.
    uint32 public operatorFeeScalar;

    /// ---------------------------
    /// Custom gas token multiplier
    /// ---------------------------

    /// @notice Multiplier admin (can update the multiplier).
    address public multiplierAdmin;

    /// @notice Multiplier applied to baseFeeScalar and blobBaseFeeScalar (1e27 = 1x).
    uint256 public gasTokenMultiplierRay;

    /// @custom:semver 1.7.0
    function version() public pure virtual returns (string memory) {
        return "1.7.0";
    }

    /// @notice Initialize multiplier admin and multiplier. Callable only once.
    function initializeMultiplier(address newAdmin, uint256 multRay) external {
        require(multiplierAdmin == address(0), "already initialized");
        require(newAdmin != address(0), "admin=0");
        require(multRay > 0, "mult=0");
        multiplierAdmin = newAdmin;
        gasTokenMultiplierRay = multRay;
    }

    /// @notice Update the multiplier (in RAY format, 1e27 = 1.0x).
    function setGasTokenMultiplier(uint256 newMultRay) external {
        require(msg.sender == multiplierAdmin, "not admin");
        require(newMultRay > 0, "mult=0");
        gasTokenMultiplierRay = newMultRay;
    }

    /// @notice Change the multiplier admin.
    function setMultiplierAdmin(address newAdmin) external {
        require(msg.sender == multiplierAdmin, "not admin");
        require(newAdmin != address(0), "admin=0");
        multiplierAdmin = newAdmin;
    }

    /// ---------------------------
    /// Gas token identity (legacy)
    /// ---------------------------

    function gasPayingToken() public pure returns (address addr_, uint8 decimals_) {
        addr_ = Constants.ETHER;
        decimals_ = 18;
    }

    function gasPayingTokenName() public pure returns (string memory name_) {
        name_ = "Ether";
    }

    function gasPayingTokenSymbol() public pure returns (string memory symbol_) {
        symbol_ = "ETH";
    }

    function isCustomGasToken() public pure returns (bool is_) {
        is_ = false;
    }

    /// ---------------------------
    /// Legacy setter
    /// ---------------------------

    function setL1BlockValues(
        uint64 _number,
        uint64 _timestamp,
        uint256 _basefee,
        bytes32 _hash,
        uint64 _sequenceNumber,
        bytes32 _batcherHash,
        uint256 _l1FeeOverhead,
        uint256 _l1FeeScalar
    )
        external
    {
        require(msg.sender == DEPOSITOR_ACCOUNT(), "L1Block: only depositor");

        number = _number;
        timestamp = _timestamp;
        basefee = _basefee;
        hash = _hash;
        sequenceNumber = _sequenceNumber;
        batcherHash = _batcherHash;
        l1FeeOverhead = _l1FeeOverhead;
        l1FeeScalar = _l1FeeScalar;
    }

    /// ---------------------------
    /// Ecotone setter (with multiplier)
    /// ---------------------------

    function setL1BlockValuesEcotone() public {
        _setL1BlockValuesEcotone();
    }

    function _setL1BlockValuesEcotone() internal {
        address depositor = DEPOSITOR_ACCOUNT();
        uint256 mult = gasTokenMultiplierRay == 0 ? 1e27 : gasTokenMultiplierRay;
        assembly {
            // Check depositor
            if xor(caller(), depositor) {
                mstore(0x00, 0x3cc50b45) // NotDepositor()
                revert(0x1C, 0x04)
            }

            // w0 layout (después del selector, @+4):
            // [ baseFeeScalar(4) | blobBaseFeeScalar(4) | sequenceNumber(8) | timestamp(8) | number(8) ]
            let w0 := calldataload(4)

            // Extrae crudos
            let rawBase := and(shr(224, w0), 0xffffffff)         // uint32 (ojo: orden!)
            let rawBlob := and(shr(192, w0), 0xffffffff)         // uint32
            let seq     := and(shr(128, w0), 0xffffffffffffffff) // uint64
            let ts      := and(shr(64,  w0), 0xffffffffffffffff) // uint64
            let num     := and(        w0,  0xffffffffffffffff)  // uint64

            // Escala (RAY = 1e27)
            let RAY := 1000000000000000000000000000
            let sBase := div(mul(rawBase, mult), RAY)
            if gt(sBase, 0xffffffff) { sBase := 0xffffffff }
            let sBlob := div(mul(rawBlob, mult), RAY)
            if gt(sBlob, 0xffffffff) { sBlob := 0xffffffff }

            // Empaqueta UNA SOLA VEZ: [ base(32b) | blob(32b) | seq(64b) ]
            let packed := or(or(shl(96, sBase), shl(64, sBlob)), seq)
            sstore(sequenceNumber.slot, packed)          // << único sstore para el slot empaquetado

            // number|timestamp (empaquetado)
            sstore(number.slot, or(shl(64, ts), num))

            // Resto de campos
            sstore(basefee.slot,     calldataload(36))
            sstore(blobBaseFee.slot, calldataload(68))
            sstore(hash.slot,        calldataload(100))
            sstore(batcherHash.slot, calldataload(132))
        }
    }

    /// ---------------------------
    /// Isthmus setter (extends Ecotone)
    /// ---------------------------

    function setL1BlockValuesIsthmus() public {
        _setL1BlockValuesIsthmus();
    }

    function _setL1BlockValuesIsthmus() internal {
        _setL1BlockValuesEcotone();
        assembly {
            // Load the packed 96-bit operator fees (operatorFeeScalar:uint32 | operatorFeeConstant:uint64)
            // from calldata (shifted right by 160 to bring the high 12 bytes down to the low 12 bytes).
            let newLow96 := shr(160, calldataload(164)) // 96 bits in the low part

            // Read current slot that packs:
            // [ multiplierAdmin (160 bits high) | operatorFeeScalar (32) | operatorFeeConstant (64) ]
            let prev := sload(operatorFeeConstant.slot)

            // Mask to preserve the high 160 bits (multiplierAdmin) and clear the low 96 bits
            // mask = (~((1<<96)-1)) = 0xFFFF...FFFF000000000000000000000000000000000000000000000000000000
            let mask := not(sub(shl(96, 1), 1))

            // Merge: keep high 160 bits from prev, put newLow96 in the low 96 bits
            let merged := or(and(prev, mask), newLow96)

            sstore(operatorFeeConstant.slot, merged)
        }
    }
}
