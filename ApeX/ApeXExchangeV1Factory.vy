# @version 0.3.7
"""
@title ApeX Exchange V1 Factory
@author 0x0077
"""


from vyper.interfaces import ERC165
from vyper.interfaces import ERC721
from vyper.interfaces import ERC20

interface IERC721Metadata:
    def name() -> String[100]: view
    def symbol()-> String[100]: view
    def tokenURI(tokenId: uint256) -> String[300]: view
    def balanceOf(owner: address) -> uint256: view
    def ownerOf(tokenId: uint256) -> address: view
    def getApproved(tokenId: uint256) -> address: view
    def isApprovedForAll(owner: address, operator: address) -> bool: view
    def baseURI() -> String[300]: view
    def owner() -> address: view
    def setApprovalForAll(operator: address, approved: bool): nonpayable

interface IERC721Enumerable:
    def totalSupply() -> uint256: view
    def tokenOfOwnerByIndex(owner: address, index: uint256) -> uint256: view
    def tokenByIndex(index: uint256) -> uint256: view
    def supportsInterface(interfaceId: bytes4) -> bool: view


interface ApeXExchangeV1Pair:
    def setup(
        _router: address, 
        _factory: address, 
        _controller: address, 
        _token0: address, 
        _token1: address,
        _trade: bool) -> bool: nonpayable

interface ApeXExchangeV1Libray:
    def getInputValue(
        _riseType: uint256,
        _pair: address,
        _numberItems: uint256,
        _currentPrice: uint256,
        _riseCurve: uint256,
        _swapFee: uint256) -> (uint256, uint256, uint256): view
    def getOutputValue(
        _riseType: uint256,
        _pair: address,
        _numberItems: uint256,
        _currentPrice: uint256,
        _riseCurve: uint256,
        _swapFee: uint256) -> (uint256, uint256, uint256): view

event PairCreated:
    pairType: uint256
    pairLength: uint256
    token0: indexed(address)
    token1: indexed(address)
    pair: indexed(address)
    riseType: uint256
    riseCurve: uint256
    fee: uint256
    tokenIds: DynArray[uint256, MAX_SIZE]
    amountIn: uint256
    time: uint256

event SetNewPair:
    controller: indexed(address)
    oldPair: indexed(address)
    newPair: indexed(address)

event SetNewRouter:
    controller: indexed(address)
    oldRouter: indexed(address)
    newRouter: indexed(address)  

event SetNewLibrary:
    controller: indexed(address)
    oldLibrary: indexed(address)
    newLibrary: indexed(address)  


struct ApeXPairETH:
    id: uint256
    token0: address
    pair: address
    riseType: uint256 # rise method id: 0--linear rise, 1--exponential rise
    riseCurve: uint256
    fee: uint256
    price: uint256
    NFTIDs: DynArray[uint256, MAX_SIZE]
    time: uint256

RISE_TYPE: constant(uint256[3]) = [
    0, # linear rise
    1, # exponential rise
    2 # xyk rise
]

PAIR_TYPE: constant(uint256[3]) = [
    0, # trade
    1, # ETH
    2  # NFT
]

MAX_SIZE: constant(uint256) = 30

INTERFACE_ID: constant(bytes4[2]) = [
    0x01ffc9a7, # ERC165
    0x80ac58cd, # ERC721
]

pairETHForERC721: HashMap[address, HashMap[address, HashMap[uint256, address]]]
pairERC20ForERC721: HashMap[address, HashMap[address, address]]
pairInfo: HashMap[uint256, ApeXPairETH]
pairId: HashMap[address, uint256]

owner: public(address)
apeXPair: public(address)
apeXRouter: public(address)
apeXLibray: public(address)

allPairs: public(HashMap[uint256, address])
allPairLength: public(uint256)
nextPairLength: public(uint256)
allTokenPairLength: public(HashMap[address, uint256])
pairOfOwnerToIndex: HashMap[address, HashMap[address, uint256]]
pairOfTokenToIndex: HashMap[address, HashMap[uint256, address]]

is_approved: HashMap[address, HashMap[address, bool]]

@external
def __init__(_pair: address, _router: address, _library: address):
    self.owner = msg.sender
    self.apeXPair = _pair
    self.apeXRouter = _router
    self.apeXLibray = _library


@view
@external
def pairOf(_owner: address, _token0: address) -> uint256:
    return self.pairOfOwnerToIndex[_owner][_token0]


@view
@external
def pairOfOwnerByIndex(_owner: address, _token0: address, _index: uint256) -> address:
    return self.pairETHForERC721[_owner][_token0][_index]


@view
@external
def pairOfTokenByIndex(_token0: address, _index: uint256) -> address:
    return self.pairOfTokenToIndex[_token0][_index]


@view
@external
def getPairDynamicInfo(pair: address) -> (uint256, uint256, uint256, uint256):
    _pairId: uint256 = self.pairId[pair]
    _pairStruct: ApeXPairETH = self.pairInfo[_pairId]
    _riseType: uint256 = _pairStruct.riseType
    _rise: uint256 = _pairStruct.riseCurve
    _fee: uint256 = _pairStruct.fee
    _price: uint256 = _pairStruct.price

    return _riseType, _rise, _fee, _price


@internal
def _transferERC721NFT(_token0: address, _sender: address, _spender: address, _tokenIds: DynArray[uint256, MAX_SIZE]) -> bool:
    
    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            raw_call(
                _token0,
                concat(
                    method_id("transferFrom(address,address,uint256)"),
                    convert(_sender, bytes32),
                    convert(_spender, bytes32),
                    convert(_tokenIds[i], bytes32)
                )
            )

    return True


@internal
def _transferERC20(_token1: address, _sender: address, _spender: address, _amountIn: uint256) -> bool:
    
    if not self.is_approved[self][_token1]:
        _response: Bytes[32] = raw_call(
            _token1,
            concat(
                method_id("approve(address,uint256)"),
                convert(self, bytes32),
                convert(max_value(uint256), bytes32)
            ),
            max_outsize=32
        )
        if len(_response) != 0:
            assert convert(_response, bool)
        self.is_approved[self][_token1] = True

    raw_call(
        _token1,
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(_sender, bytes32),
            convert(_spender, bytes32),
            convert(_amountIn, bytes32)
        )
    )

    return True


@internal
def _pairSetup(_pairType: uint256, _pairAddress: address, _token0: address, _token1: address, _sender: address, _trade: bool) -> bool:

    raw_call(
        _pairAddress,
        concat(
            method_id("setup(uint256,address,address,address,address,address,bool)"),
            convert(_pairType, bytes32),
            convert(self.apeXRouter, bytes32),
            convert(self, bytes32),
            convert(_sender, bytes32),
            convert(_token0, bytes32),
            convert(_token1, bytes32),
            convert(_trade, bytes32)
        )
    )

    return True


@internal
def _writePairStruct(
    _owner: address,
    _token0: address,
    _newPairAddress: address,
    _riseType: uint256,
    _riseCurve: uint256,
    _fee: uint256,
    _price: uint256,
    _tokenIds: DynArray[uint256, MAX_SIZE]) -> bool:

    _pairLength: uint256 = self.allPairLength

    _newPairStruct: ApeXPairETH = ApeXPairETH({
        id: _pairLength,
        token0: _token0,
        pair: _newPairAddress,
        riseType: _riseType,
        riseCurve: _riseCurve,
        fee: _fee,
        price: _price,
        NFTIDs: _tokenIds,
        time: block.timestamp
    })

    self.pairInfo[_pairLength] = _newPairStruct
    self.pairId[_newPairAddress] = _pairLength
    self.allPairs[_pairLength] = _newPairAddress
    self.allPairLength += 1
    self.nextPairLength = self.allPairLength + 1
    
    self.pairETHForERC721[_owner][_token0][self.pairOfOwnerToIndex[_owner][_token0]] = _newPairAddress
    self.pairOfTokenToIndex[_token0][self.allTokenPairLength[_token0]] = _newPairAddress
    self.allTokenPairLength[_token0] += 1
    self.pairOfOwnerToIndex[_owner][_token0] += 1

    return True


@internal
def _createPairERC721(
    _owner: address,
    _token0: address, 
    _price: uint256, 
    _riseType: uint256,
    _riseCurve: uint256,
    _fee: uint256,
    _numberItems: uint256,
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _trade: bool) -> (address, bool):
    for i in range(2):
        supported: bool = IERC721Enumerable(_token0).supportsInterface(INTERFACE_ID[i])
        assert supported, "APEX:: UNVALID ERC721 INTERFACE ID"

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            returnOwner: address = IERC721Metadata(_token0).ownerOf(_tokenIds[i])
            assert returnOwner == _owner, "APEX:: FORK OWNER"


    _newPairAddress: address = create_minimal_proxy_to(self.apeXPair)
    assert _newPairAddress != empty(address), "APEX:: UNVALID CREATE"

    _transferSuccessful: bool = self._transferERC721NFT(_token0, _owner, _newPairAddress, _tokenIds)
    assert _transferSuccessful, "APEX:: UNVALID TRANSFER"

    writed: bool = self._writePairStruct(
        _owner,
        _token0,
        _newPairAddress,
        _riseType,
        _riseCurve,
        _fee,
        _price,
        _tokenIds
    )
    assert writed, "APEX:: UNVALID WRITE"

    return _newPairAddress, True


@payable
@external
def createPairETHForERC721(
    _pairType: uint256,
    _token0: address, 
    _price: uint256, 
    _riseType: uint256,
    _riseCurve: uint256,
    _fee: uint256,
    _numberItems: uint256,
    _tokenIds: DynArray[uint256, MAX_SIZE]) -> address:
    """
    @dev Create an 'ERC721/NFT' pool
    """

    assert _token0 != empty(address) and msg.sender != empty(address), "APEX:: UNVALID ADDRESS"
    assert len(_tokenIds) <= MAX_SIZE, "APEX:: EXCESS INPUT"
    assert _riseCurve <= (_price * 90 / 100), "APEX:: UNVALID RISE CURVE"
    assert _riseType in RISE_TYPE, "APEX:: UNVALID TYPE"
    assert _pairType in PAIR_TYPE, "APEX:: UNVALID PAIR TRADE TYPE"

    _library: address = self.apeXLibray
    _pair: address = self.apeXPair
    _newCurrentPrice: uint256 = 0
    _depositValue: uint256 = 0
    _protocolFee: uint256 = 0

    if _riseType != 2:
        _newCurrentPrice, _depositValue, _protocolFee = ApeXExchangeV1Libray(_library).getInputValue(_riseType, _pair, _numberItems, _price, _riseCurve, _fee)
        _depositValue += (_depositValue * _fee / 1000)
        assert _depositValue == msg.value and _price != 0, "APEX:: INSUFFICIENT BALANCE"

    _newPairAddress: address = empty(address)
    _successful: bool = False
    _newPairAddress, _successful = self._createPairERC721(
        msg.sender,
        _token0,
        _price,
        _riseType,
        _riseCurve,
        _fee,
        _numberItems,
        _tokenIds,
        True
    )
    assert _successful, "APEX:: UNVALID CALL"

    raw_call(
        _newPairAddress,
        concat(
            method_id("setup(uint256,address,address,address,address,address,bool)"),
            convert(_pairType, bytes32),
            convert(self.apeXRouter, bytes32),
            convert(self, bytes32),
            convert(msg.sender, bytes32),
            convert(_token0, bytes32),
            convert(empty(address), bytes32),
            convert(True, bytes32)
        ),
        value=msg.value
    )

    log PairCreated(
        _pairType,
        self.allPairLength, 
        _token0, 
        empty(address), 
        _newPairAddress, 
        _riseType, 
        _riseCurve, 
        _fee, 
        _tokenIds,
        msg.value,
        block.timestamp)
    
    return _newPairAddress


@payable
@external
def createPairETH(
    _pairType: uint256,
    _token0: address,
    _price: uint256,
    _riseType: uint256,
    _riseCurve: uint256,
    _numberItems: uint256) -> address:
    assert _token0 != empty(address) and msg.sender != empty(address), "APEX:: UNVALID ADDRESS"
    assert _price != 0, "APEX:: ENTER UNVALID AMOUNT"
    assert _riseType in RISE_TYPE, "APEX:: UNVALID TYPE"
    assert _pairType in PAIR_TYPE, "APEX:: UNVALID PAIR TRADE TYPE"
    assert _price * _numberItems == msg.value, "APEX:: UNVALID VALUE"
    assert _riseCurve <= (_price * 90 / 100), "APEX:: UNVALID RISE CURVE"

    _newPairAddress: address = create_forwarder_to(self.apeXPair)
    assert _newPairAddress != empty(address), "APEX:: UNVALID CREATE"

    writed: bool = self._writePairStruct(
        msg.sender,
        _token0,
        _newPairAddress,
        _riseType,
        _riseCurve,
        0,
        _price,
        empty(DynArray[uint256, MAX_SIZE])
    )
    assert writed, "APEX:: UNVALID WRITE"

    raw_call(
        _newPairAddress,
        concat(
            method_id("setup(uint256,address,address,address,address,address,bool)"),
            convert(_pairType, bytes32),
            convert(self.apeXRouter, bytes32),
            convert(self, bytes32),
            convert(msg.sender, bytes32),
            convert(_token0, bytes32),
            convert(empty(address), bytes32),
            convert(False, bytes32)
        ),
        value=msg.value
    )

    log PairCreated(
        _pairType,
        self.allPairLength, 
        _token0, 
        empty(address), 
        _newPairAddress, 
        _riseType, 
        _riseCurve, 
        0, 
        empty(DynArray[uint256, MAX_SIZE]),
        msg.value,
        block.timestamp)
    
    return _newPairAddress
        

@external
def createPairERC721NFT(
    _pairType: uint256,
    _token0: address,
    _price: uint256,
    _riseType: uint256,
    _riseCurve: uint256,
    _numberItems: uint256,
    _tokenIds: DynArray[uint256, MAX_SIZE]) -> address:

    assert _token0 != empty(address) and msg.sender != empty(address), "APEX:: UNVALID ADDRESS"
    assert _price != 0, "APEX:: ENTER UNVALID AMOUNT"
    assert _riseType in RISE_TYPE, "APEX:: UNVALID TYPE"
    assert _pairType in PAIR_TYPE, "APEX:: UNVALID PAIR TRADE TYPE"
    assert _riseCurve <= (_price * 90 / 100), "APEX:: UNVALID RISE CURVE"
    assert _numberItems == len(_tokenIds), "APEX:: UNVALID TOKEN ID"

    _newPairAddress: address = empty(address)
    _successful: bool = False

    _newPairAddress, _successful = self._createPairERC721(
        msg.sender,
        _token0,
        _price,
        _riseType,
        _riseCurve,
        0,
        _numberItems,
        _tokenIds,
        False
    )
    assert _successful, "APEX:: UNVALID CALL"

    _setupSuccessful: bool = self._pairSetup(_pairType, _newPairAddress, _token0, empty(address), msg.sender, False)
    assert _setupSuccessful, "APEX:: UNVALID CALL"

    log PairCreated(
        _pairType,
        self.allPairLength, 
        _token0, 
        empty(address), 
        _newPairAddress, 
        _riseType, 
        _riseCurve, 
        0, 
        _tokenIds,
        0,
        block.timestamp)

    return _newPairAddress


@external
def createPairERC20ForERC721(
    _pairType: uint256,
    _token0: address,
    _token1: address,
    _price: uint256,
    _riseType: uint256,
    _riseCurve: uint256,
    _fee: uint256,
    _amountIn: uint256,
    _numberItems: uint256,
    _tokenIds: DynArray[uint256, MAX_SIZE]) -> address:
    assert _token0 != empty(address) and _token1 != empty(address) and msg.sender != empty(address), "APEX:: UNVALID ADDRESS"
    assert _riseType in RISE_TYPE, "APEX:: UNVALID TYPE"
    assert _pairType in PAIR_TYPE, "APEX:: UNVALID PAIR TRADE TYPE"
    assert _riseCurve <= (_price * 90 / 100), "APEX:: UNVALID RISE CURVE"
    assert _amountIn != 0, "APEX:: UNVALID AMOUNT"
    assert _numberItems == len(_tokenIds), "APEX:: UNVALID TOKEN ID"
    
    _library: address = self.apeXLibray
    _pair: address = self.apeXPair
    _newCurrentPrice: uint256 = 0
    _depositValue: uint256 = 0
    _protocolFee: uint256 = 0

    if _riseType != 2:
        _newCurrentPrice, _depositValue, _protocolFee = ApeXExchangeV1Libray(_library).getInputValue(_riseType, _pair, _numberItems, _price, _riseCurve, _fee)
        assert _depositValue == _amountIn and _price != 0, "APEX:: INSUFFICIENT BALANCE"

    _newPairAddress: address = empty(address)
    _successful: bool = False
    _newPairAddress, _successful = self._createPairERC721(
        msg.sender,
        _token0,
        _price,
        _riseType,
        _riseCurve,
        _fee,
        _numberItems,
        _tokenIds,
        True
    )
    assert _successful, "APEX:: UNVALID CALL"

    _transferERC20Successful: bool = self._transferERC20(_token1, msg.sender, _newPairAddress, _amountIn)
    assert _transferERC20Successful, "APEX:: UNVALID CALL"

    _setupSuccessful: bool = self._pairSetup(_pairType, _newPairAddress, _token0, _token1, msg.sender, True)
    assert _setupSuccessful, "APEX:: UNVALID CALL"

    log PairCreated(
        _pairType,
        self.allPairLength, 
        _token0, 
        _token1, 
        _newPairAddress, 
        _riseType, 
        _riseCurve, 
        _fee, 
        _tokenIds,
        _amountIn,
        block.timestamp)

    return _newPairAddress


@external
@nonreentrant('lock')
def createPairERC20(
    _token0: address,
    _token1: address,
    _price: uint256,
    _riseType: uint256,
    _riseCurve: uint256,
    _amountIn: uint256):
    assert _token0 != empty(address) and _token1 != empty(address) and msg.sender != empty(address), "APEX:: UNVALID ADDRESS"
    assert _price != 0, "APEX:: UNVALID ZERO PRICE"
    assert _riseType in RISE_TYPE, "APEX:: UNVALID RISE TYPE"
    assert _amountIn != 0, "APEX:: UNVALID ERC20 AMOUNT"
    
    if _riseType == 0:
        assert _riseCurve <= (_price * 90 / 100), "APEX:: UNVALID LIBEAR RISE CURVE"
    if _riseType == 1:
        assert _riseCurve <= (_price * 90 / 100), "APEX:: UNVALID EXPONENTIAL RISE CURVE"


@external
def updateNewPair(_newPair: address):
    """
    @dev update new 'pair' address
    @param _newPair new 'pair' address
    """
    assert self.owner == msg.sender, "APEX:: ONLY OWNER"

    oldPair: address = self.apeXPair
    self.apeXPair = _newPair
    log SetNewPair(msg.sender, oldPair, _newPair)


@external
def updateNewRouter(_newRouter: address):
    """
    @dev update new 'router' address
    @param _newRouter new 'router' address
    """
    assert self.owner == msg.sender, "APEX:: ONLY OWNER"

    oldRouter: address = self.apeXRouter
    self.apeXRouter = _newRouter
    log SetNewRouter(msg.sender, oldRouter, _newRouter)


@external
def updateLibrary(_newLibrary: address):
    """
    @dev update new 'library' address
    @param _newLibrary new 'library' address
    """
    assert msg.sender == self.owner, "APEX:: ONLY OWNER"

    oldLibrary: address = self.apeXLibray
    self.apeXLibray = _newLibrary
    log SetNewLibrary(msg.sender, oldLibrary, _newLibrary)

