# @version >=0.3

from vyper.interfaces import ERC165
from vyper.interfaces import ERC721

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


interface IERC721Enumerable:
    def totalSupply() -> uint256: view
    def tokenOfOwnerByIndex(owner: address, index: uint256) -> uint256: view
    def tokenByIndex(index: uint256) -> uint256: view

interface IERC1155Metadata:
    def uri(tokenId: uint256) -> String[300]: view
    def supportsInterface(interfaceId: bytes4) -> bool: view


# Interface IDs
ERC165_INTERFACE_ID: constant(bytes4)  = 0x01ffc9a7
ERC1155_INTERFACE_ID: constant(bytes4) = 0xd9b67a26
ERC1155_INTERFACE_ID_METADATA: constant(bytes4) = 0x0e89341c

#=============List=============#
# owner
createdOwner: HashMap[uint256, address]
# price
createdPrice: HashMap[address, HashMap[uint256, uint256]]
# times
createdTime: HashMap[address, HashMap[uint256, uint256]]
# is list
is_activateForOrder: HashMap[address, HashMap[uint256, bool]]

# order id
createdOrderId: HashMap[address, HashMap[uint256, uint256]]
orderId: public(uint256)


# approve
is_approved: HashMap[address, HashMap[address, bool]]

struct MarketOrder:
    orderId: uint256
    nftContract: address
    tokenId: uint256
    seller: address
    buyer: address
    price: uint256

event MarketOrderCreated:
    orderId: uint256
    nftContract: indexed(address)
    tokenId: uint256
    seller: indexed(address)
    price: uint256
    time: uint256

event MarketOrderSold:
    orderId: uint256
    nftContract: indexed(address)
    tokenId: uint256
    seller: indexed(address)
    buyer: indexed(address)
    price: uint256
    time: uint256

event SetOrderPrice:
    orderId: uint256
    nftContract: indexed(address)
    tokenId: uint256
    seter: indexed(address)
    price: uint256
    time: uint256

event CancelOrder:
    orderId: uint256
    nftContract: indexed(address)
    tokenId: uint256
    canceler: indexed(address)
    time: uint256

owner: public(address)
fund: public(address)

@external
def __init__(_fund: address):
    self.owner = msg.sender
    self.fund = _fund


@view
@external
def getCreatedOrdersPrice(nftContract:address, tokenId: uint256) -> uint256:
    return self.createdPrice[nftContract][tokenId]


@view
@external
def getCreatedOrdersTime(nftContract:address, tokenId: uint256) -> uint256:
    return self.createdTime[nftContract][tokenId]


@view
@external
def getCreatedOrdersId(nftContract:address, tokenId: uint256) -> uint256:
    return self.createdOrderId[nftContract][tokenId]


@view
@external
def getOrderIsActivate(nftContract: address, tokenId: uint256) -> bool:
    return self.is_activateForOrder[nftContract][tokenId]


# =========NFT INFO=========#
@view
@external
def getNFTName(nftContract:address) -> (String[100], String[100]):
    return IERC721Metadata(nftContract).name(), IERC721Metadata(nftContract).symbol()

@view
@external
def getOwnerOf(nftContract:address, tokenId: uint256) -> address:
    return IERC721Metadata(nftContract).ownerOf(tokenId)

@view
@external
def getContractOwner(nftContract: address) -> address:
    return IERC721Metadata(nftContract).owner()

@view
@external
def getBaseURI(nftContract: address) -> String[300]:
    return IERC721Metadata(nftContract).baseURI()

@view
@external
def getTotalSupply(nftContract: address, tokenId: uint256) -> uint256:
    return IERC721Enumerable(nftContract).totalSupply()

@view
@external
def getERC721Uri(nftContract: address, tokenId: uint256) -> String[300]:
    return IERC721Metadata(nftContract).tokenURI(tokenId)

@view
@external
def getERC1155Uri(nftContract: address, tokenId: uint256) -> String[300]:
    return IERC1155Metadata(nftContract).uri(tokenId)

@view
@external
def getSupportInterface(nftContract: address, interfaceId: bytes4) -> bool:
    return IERC1155Metadata(nftContract).supportsInterface(interfaceId)


@external
def market_order_create(nftContract: address, createAddress: address, tokenId: uint256, createPrice: uint256):
    # list order
    assert nftContract != empty(address), "CONTRACT NOT'T ZEROADDRESS"
    assert msg.sender != empty(address), "SENDERs NOT'T ZEROADDRESS!!!"
    assert createAddress == msg.sender, "SENDER WARNING"
    assert createPrice > 0, "PRICE NOT'T ZERO"
    assert not self.is_activateForOrder[nftContract][tokenId], "ALREADY ON THE SHELF"

    ownerAddress: address = IERC721Metadata(nftContract).ownerOf(tokenId)
    assert ownerAddress == msg.sender, "OWNER WARNING"
    is_operator: bool = IERC721Metadata(nftContract).isApprovedForAll(msg.sender, self)
    assert is_operator, "UNAPPROVED"

    self.createdPrice[nftContract][tokenId] = createPrice
    self.createdTime[nftContract][tokenId] = block.timestamp
    self.orderId += 1
    self.createdOrderId[nftContract][tokenId] = self.orderId
    self.createdOwner[self.orderId] = msg.sender
    self.is_activateForOrder[nftContract][tokenId] = True

    log MarketOrderCreated(self.orderId, nftContract, tokenId, createAddress, createPrice, block.timestamp)


@payable
@external
@nonreentrant("lock")
def market_order_sold(nftContract: address, buyer: address, tokenId: uint256, buyPrice: uint256):
    # buy
    assert nftContract != empty(address), "CONTRACT NOT'T ZEROADDRESS"
    assert msg.sender != empty(address), "SENDERs NOT'T ZEROADDRESS!!!"
    assert buyer == msg.sender, "SENDER WARNING"
    assert buyPrice == self.createdPrice[nftContract][tokenId], "PRICE != ORDERPRICE"
    assert self.createdPrice[nftContract][tokenId] > 0, "ORDERPRICE NOT'T ZERO"
    assert buyPrice > 0, "PRICE NOT'T ZERO"
    assert buyPrice == msg.value, "PRICE != MSG.VALUE"
    assert msg.value == self.createdPrice[nftContract][tokenId], "PRICE != MSG.VALUE"
    assert self.is_activateForOrder[nftContract][tokenId], "ITEMS NOT'T ACTIVATE"

    ownerAddress: address = IERC721Metadata(nftContract).ownerOf(tokenId)
    iid: uint256 = self.createdOrderId[nftContract][tokenId]
    assert ownerAddress == self.createdOwner[iid], "OWNER WARNING"
    is_operator: bool = IERC721Metadata(nftContract).isApprovedForAll(ownerAddress, self)
    assert is_operator, "UNAPPROVED"

    if not self.is_approved[self][nftContract]:
        response: Bytes[32] = raw_call(
            nftContract,
            concat(
                method_id("setApprovalForAll(address,bool)"),
                convert(self, bytes32),
                convert(True, bytes32)
            ),
            max_outsize=32
        )
        if len(response) != 0:
            assert convert(response, bool)
        self.is_approved[self][nftContract] = True

    raw_call(
        nftContract,
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(ownerAddress, bytes32),
            convert(buyer, bytes32),
            convert(tokenId, bytes32)
        )
    )
    
    fee: uint256 = msg.value / 100
    send(self.fund, fee)
    send(ownerAddress, msg.value-fee)

    self.createdPrice[nftContract][tokenId] = 0
    self.is_activateForOrder[nftContract][tokenId] = False

    log MarketOrderSold(iid, nftContract, tokenId, ownerAddress, buyer, buyPrice, block.timestamp)


@external
def setOrderPrice(nftContract: address, sender: address, tokenId: uint256, setPrice: uint256):
    # update price
    assert nftContract != empty(address), "CONTRACT NOT'T ZEROADDRESS"
    assert msg.sender != empty(address), "SENDERs NOT'T ZEROADDRESS!!!"
    assert sender == msg.sender, "SENDER WARNING"
    assert self.is_activateForOrder[nftContract][tokenId], "ITEMS NOT'T ACTIVATE"

    ownerAddress: address = IERC721Metadata(nftContract).ownerOf(tokenId)
    assert ownerAddress == msg.sender, "OWNER WARNING"
    iid: uint256 = self.createdOrderId[nftContract][tokenId]

    self.createdPrice[nftContract][tokenId] = setPrice
    log SetOrderPrice(iid, nftContract, tokenId, msg.sender, setPrice, block.timestamp)


@external
def cancelOrder(nftContract: address, sender: address, tokenId: uint256):
    # cancel order
    assert nftContract != empty(address), "CONTRACT NOT'T ZEROADDRESS"
    assert msg.sender != empty(address), "SENDERs NOT'T ZEROADDRESS!!!"
    assert sender == msg.sender, "SENDER WARNING"
    assert self.is_activateForOrder[nftContract][tokenId], "ITEMS NOT'T ACTIVATE"

    iid: uint256 = self.createdOrderId[nftContract][tokenId]
    assert self.createdOwner[iid] == msg.sender, "NOLY NFT OWNER"
    ownerAddress: address = IERC721Metadata(nftContract).ownerOf(tokenId)
    assert ownerAddress == msg.sender, "OWNER WARNING"

    self.createdPrice[nftContract][tokenId] = 0
    self.createdTime[nftContract][tokenId] = 0
    self.createdOrderId[nftContract][tokenId] = 0
    self.createdOwner[iid] = empty(address)
    self.is_activateForOrder[nftContract][tokenId] = False

    log CancelOrder(iid, nftContract, tokenId, sender, block.timestamp)