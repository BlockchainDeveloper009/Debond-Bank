// SPDX-License-Identifier: MIT


pragma solidity ^0.8.0;

import "debond-governance-contracts/utils/GovernanceOwnable.sol";
import "debond-erc3475-contracts/interfaces/IDebondBond.sol";
import "debond-erc3475-contracts/interfaces/IProgressCalculator.sol";
import "erc3475/IERC3475.sol";
import "./libraries/DebondMath.sol";
import "./interfaces/IBankData.sol";


abstract contract BankBondManager is IProgressCalculator, GovernanceOwnable {

    using DebondMath for uint256;

    enum InterestRateType {FixedRate, FloatingRate}

    address debondBondAddress;
    address bankData;

    // class MetadataIds
    uint public constant symbolMetadataId = 0;
    uint public constant tokenAddressMetadataId = 1;
    uint public constant interestRateTypeMetadataId = 2;
    uint public constant periodMetadataId = 3;

    // nonce MetadataIds
    uint public constant issuanceDateMetadataId = 0;
    uint public constant maturityDateMetadataId = 1;

    uint public constant EPOCH = 30;


    constructor(
        address _governanceAddress,
        address _debondBondAddress,
        address _bankData
    ) GovernanceOwnable(_governanceAddress) {
        debondBondAddress = _debondBondAddress;
        bankData = _bankData;
    }

    function mapClassValuesFrom(
        string memory symbol,
        address tokenAddress,
        InterestRateType interestRateType,
        uint256 period
    ) internal pure returns (uint[] memory, IERC3475.Values[] memory) {
        uint[] memory _metadataIds = new uint[](4);
        _metadataIds[0] = symbolMetadataId;
        _metadataIds[1] = tokenAddressMetadataId;
        _metadataIds[2] = interestRateTypeMetadataId;
        _metadataIds[3] = periodMetadataId;

        IERC3475.Values[] memory _values = new IERC3475.Values[](4);
        _values[0] = IERC3475.Values(symbol, 0, address(0), false);
        _values[1] = IERC3475.Values("", 0, tokenAddress, false);
        _values[2] = IERC3475.Values("", uint(interestRateType), address(0), false);
        _values[3] = IERC3475.Values("", period, address(0), false);
        return  (_metadataIds, _values);
    }

    function mapNonceValuesFrom(
        uint256 issuanceDate,
        uint256 maturityDate
    ) internal pure returns (uint[] memory, IERC3475.Values[] memory) {
        uint[] memory _metadataIds = new uint[](2);
        _metadataIds[0] = issuanceDateMetadataId;
        _metadataIds[1] = maturityDateMetadataId;

        IERC3475.Values[] memory _values = new IERC3475.Values[](2);
        _values[0] = IERC3475.Values("", issuanceDate, address(0), false);
        _values[1] = IERC3475.Values("", maturityDate, address(0), false);

        return (_metadataIds, _values);
    }

    function createClassMetadatas(uint256[] memory metadataIds, IERC3475.Metadata[] memory metadatas) external onlyGovernance {
        _createClassMetadatas(metadataIds, metadatas);
    }

    function _createClassMetadatas(uint256[] memory metadataIds, IERC3475.Metadata[] memory metadatas) internal {
        IDebondBond(debondBondAddress).createClassMetadataBatch(metadataIds, metadatas);
    }

    function _createInitClassMetadatas() internal {
        uint256[] memory metadataIds = new uint256[](4);
        metadataIds[0] = symbolMetadataId;
        metadataIds[1] = tokenAddressMetadataId;
        metadataIds[2] = interestRateTypeMetadataId;
        metadataIds[3] = periodMetadataId;

        IERC3475.Metadata[] memory metadatas = new IERC3475.Metadata[](4);
        metadatas[0] = IERC3475.Metadata("symbol", "string", "the collateral token's symbol");
        metadatas[1] = IERC3475.Metadata("token address", "address", "the collateral token's address");
        metadatas[2] = IERC3475.Metadata("interest rate type", "int", "the interest rate type");
        metadatas[3] = IERC3475.Metadata("period", "int", "the base period for the class");
        IDebondBond(debondBondAddress).createClassMetadataBatch(metadataIds, metadatas);
    }

    function createClass(uint256 classId, string memory symbol, address tokenAddress, InterestRateType interestRateType, uint256 period) external onlyGovernance {
        _createClass(classId, symbol, tokenAddress, interestRateType, period);
    }

    function _createClass(uint256 classId, string memory symbol, address tokenAddress, InterestRateType interestRateType, uint256 period) internal {
        (uint[] memory _metadataIds, IERC3475.Values[] memory _values) = mapClassValuesFrom(symbol, tokenAddress, interestRateType, period);
        IDebondBond(debondBondAddress).createClass(classId, _metadataIds, _values);
        pushClassIdPerToken(tokenAddress, classId);
        addNewClassId(classId);
        _createNonceMetadatas(classId);
    }

    function _createNonceMetadatas(uint256 classId) internal {
        uint256[] memory metadataIds = new uint256[](2);
        metadataIds[0] = issuanceDateMetadataId;
        metadataIds[1] = maturityDateMetadataId;

        IERC3475.Metadata[] memory metadatas = new IERC3475.Metadata[](2);
        metadatas[0] = IERC3475.Metadata("issuance date", "int", "the issuance date of the bond");
        metadatas[1] = IERC3475.Metadata("maturity date", "int", "the maturity date of the bond");
        IDebondBond(debondBondAddress).createNonceMetadataBatch(classId, metadataIds, metadatas);
    }

    function issueBonds(address to, uint256 classId, uint256 amount) internal {
        uint instant = block.timestamp;
        uint _nowNonce = getNonceFromDate(block.timestamp);
        (,, uint period) = classValues(classId);
        uint _nonceToCreate = _nowNonce + getNonceFromPeriod(period);
        (uint _lastNonceCreated,) = IDebondBond(debondBondAddress).getLastNonceCreated(classId);
        if (_nonceToCreate != _lastNonceCreated) {
            createNewNonce(classId, _nonceToCreate, instant);
            _lastNonceCreated = _nonceToCreate;
        }
        _issue(to, classId, _lastNonceCreated, amount);
    }

    function createNewNonce(uint classId, uint newNonceId, uint creationTimestamp) private {
        (,, uint period) = classValues(classId);
        (uint[] memory _metadataIds, IERC3475.Values[] memory _values) = mapNonceValuesFrom(creationTimestamp, creationTimestamp + period);

        IDebondBond(debondBondAddress).createNonce(classId, newNonceId, _metadataIds, _values);
        _updateLastNonce(classId, newNonceId, creationTimestamp);
    }

    function _issue(address to, uint256 classId, uint256 nonceId, uint256 amount) internal {
        (address tokenAddress, InterestRateType interestRateType,) = classValues(classId);
        _issueERC3475(to, classId, nonceId, amount);
        setTokenInterestRateSupply(tokenAddress, interestRateType, amount);
        setTokenTotalSupplyAtNonce(tokenAddress, nonceId, _tokenTotalSupply(tokenAddress));

    }

    function getNonceFromDate(uint256 date) public view returns (uint256) {
        return getNonceFromPeriod(date - getBaseTimestamp());
    }

    function getNonceFromPeriod(uint256 period) private pure returns (uint256) {
        return period / EPOCH;
    }

    function getProgress(uint256 classId, uint256 nonceId) external view returns (uint256 progressAchieved, uint256 progressRemaining) {
        (address _tokenAddress, InterestRateType _interestRateType, uint _periodTimestamp) = classValues(classId);
        (, uint256 _maturityDate) = nonceValues(classId, nonceId);
        if (_interestRateType == InterestRateType.FixedRate) {
            progressRemaining = _maturityDate <= block.timestamp ? 0 : (_maturityDate - block.timestamp) * 100 / _periodTimestamp;
            progressAchieved = 100 - progressRemaining;
            return (progressAchieved, progressRemaining);
        }

        uint BsumNL = _tokenTotalSupply(_tokenAddress);
        uint BsumN = getTokenTotalSupplyAtNonce(_tokenAddress, nonceId);
        uint BsumNInterest = BsumN + BsumN.mul(getBenchmarkInterest());

        progressRemaining = BsumNInterest < BsumNL ? 0 : 100;
        progressAchieved = 100 - progressRemaining;
    }

    function _updateLastNonce(uint classId, uint nonceId, uint createdAt) internal {
        IDebondBond(debondBondAddress).updateLastNonce(classId, nonceId, createdAt);
    }
    // READS

    //TODO TEST
    function getETA(uint256 classId, uint256 nonceId) external view returns (uint256) {
        (address _tokenAddress, InterestRateType _interestRateType,) = classValues(classId);
        (, uint256 _maturityDate) = nonceValues(classId, nonceId);

        if (_interestRateType == InterestRateType.FixedRate) {
            return _maturityDate;
        }

        uint BsumNL = _tokenTotalSupply(_tokenAddress);
        uint BsumN = getTokenTotalSupplyAtNonce(_tokenAddress, nonceId);

        (uint lastNonceCreated,) = IDebondBond(debondBondAddress).getLastNonceCreated(classId);
        uint liquidityFlowOver30Nonces = _supplyIssuedOnPeriod(_tokenAddress, lastNonceCreated - 30, lastNonceCreated);
        uint Umonth = liquidityFlowOver30Nonces / 30;
        return DebondMath.floatingETA(_maturityDate, BsumN, getBenchmarkInterest(), BsumNL, EPOCH, Umonth);
    }

    function _getSupplies(address tokenAddress, InterestRateType interestRateType, uint supplyToAdd) internal view returns (uint fixRateSupply, uint floatRateSupply) {
        fixRateSupply = getTokenInterestRateSupply(tokenAddress, InterestRateType.FixedRate);
        floatRateSupply = getTokenInterestRateSupply(tokenAddress, InterestRateType.FloatingRate);

        // we had the client amount to the according bond balance to calculate interest rate after deposit
        if (supplyToAdd > 0 && interestRateType == InterestRateType.FixedRate) {
            fixRateSupply += supplyToAdd;
        }
        if (supplyToAdd > 0 && interestRateType == InterestRateType.FloatingRate) {
            floatRateSupply += supplyToAdd;
        }
    }


    function classValues(uint256 classId) public view returns (address _tokenAddress, InterestRateType _interestRateType, uint256 _periodTimestamp) {
        _tokenAddress = (IERC3475(debondBondAddress).classValues(classId, tokenAddressMetadataId)).addressValue;
        uint interestType = (IERC3475(debondBondAddress).classValues(classId, interestRateTypeMetadataId)).uintValue;
        _interestRateType = interestType == 0 ? InterestRateType.FixedRate : InterestRateType.FloatingRate;
        _periodTimestamp = (IERC3475(debondBondAddress).classValues(classId, periodMetadataId)).uintValue;
    }

    function nonceValues(uint256 classId, uint256 nonceId) public view returns (uint256 _issuanceDate, uint256 _maturityDate) {
        _issuanceDate = (IERC3475(debondBondAddress).nonceValues(classId, nonceId, issuanceDateMetadataId)).uintValue;
        _maturityDate = (IERC3475(debondBondAddress).nonceValues(classId, nonceId, maturityDateMetadataId)).uintValue;
    }

    function _tokenTotalSupply(address tokenAddress) internal view returns (uint256) {
        return getTokenInterestRateSupply(tokenAddress, InterestRateType.FixedRate) + getTokenInterestRateSupply(tokenAddress, InterestRateType.FloatingRate);
    }

    function _supplyIssuedOnPeriod(address tokenAddress, uint256 fromNonceId, uint256 toNonceId) internal view returns (uint256 supply) {
        require(fromNonceId <= toNonceId, "DebondBond Error: Invalid Input");
        // we loop on every nonces required of every token's classes
        uint[] memory _classIdsPerTokenAddress = getClassIdsFromTokenAddress(tokenAddress);
        for (uint i = fromNonceId; i <= toNonceId; i++) {
            for (uint j = 0; j < _classIdsPerTokenAddress.length; j++) {
                supply += (IDebondBond(debondBondAddress).activeSupply(_classIdsPerTokenAddress[j], i) + IDebondBond(debondBondAddress).redeemedSupply(_classIdsPerTokenAddress[j], i));
            }
        }
    }

    function _issueERC3475(address to, uint classId, uint nonceId, uint amount) internal {
        IERC3475.Transaction[] memory transactions = new IERC3475.Transaction[](1);
        IERC3475.Transaction memory transaction = IERC3475.Transaction(classId, nonceId, amount);
        transactions[0] = transaction;
        IDebondBond(debondBondAddress).issue(to, transactions);
    }

    function _redeemERC3475(address from, uint classId, uint nonceId, uint amount) internal {
        IERC3475.Transaction[] memory transactions = new IERC3475.Transaction[](1);
        IERC3475.Transaction memory transaction = IERC3475.Transaction(classId, nonceId, amount);
        transactions[0] = transaction;
        IDebondBond(debondBondAddress).redeem(from, transactions);
    }

    function setTokenInterestRateSupply(address tokenAddress, BankBondManager.InterestRateType interestRateType, uint amount) internal {
        IBankData(bankData).setTokenInterestRateSupply(tokenAddress, interestRateType, amount);
    }

    function setTokenTotalSupplyAtNonce(address tokenAddress, uint nonceId, uint amount) internal {
        IBankData(bankData).setTokenTotalSupplyAtNonce(tokenAddress, nonceId, amount);
    }

    function pushClassIdPerToken(address tokenAddress, uint classId) internal {
        IBankData(bankData).pushClassIdPerToken(tokenAddress, classId);
    }

    function addNewClassId(uint classId) internal {
        IBankData(bankData).addNewClassId(classId);
    }

    function setBenchmarkInterest(uint _benchmarkInterest) internal {
        IBankData(bankData).setBenchmarkInterest(_benchmarkInterest);
    }

    function getBaseTimestamp() public view returns (uint) {
        return IBankData(bankData).getBaseTimestamp();
    }

    function getClasses() public view returns (uint[] memory) {
        return IBankData(bankData).getClasses();
    }

    function getTokenInterestRateSupply(address tokenAddress, BankBondManager.InterestRateType interestRateType) public view returns (uint) {
        return IBankData(bankData).getTokenInterestRateSupply(tokenAddress, interestRateType);
    }

    function getClassIdsFromTokenAddress(address tokenAddress) public view returns (uint[] memory) {
        return IBankData(bankData).getClassIdsFromTokenAddress(tokenAddress);
    }

    function getTokenTotalSupplyAtNonce(address tokenAddress, uint nonceId) public view returns (uint) {
        return IBankData(bankData).getTokenTotalSupplyAtNonce(tokenAddress, nonceId);
    }

    function getBenchmarkInterest() public view returns (uint) {
        return IBankData(bankData).getBenchmarkInterest();
    }


}
