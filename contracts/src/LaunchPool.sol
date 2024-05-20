// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CErc20} from "../lib/clm/src/CErc20.sol";
import {Comptroller} from "../lib/clm/src/Comptroller.sol";

interface BaseV1Router01 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

/**
 * @title LaunchPool
 * @dev Contract for managing token sales, airdrops, and liquidity on DEXs.
 */
contract LaunchPool is ERC20 {
    uint256 public maxSupply;
    uint256 public allocatedSupply;
    uint256 public reservedSupply;
    uint256 public creatorSupply;
    uint256 public saleStartTime;
    uint256 public saleDuration;

    bytes32 public merkleRootForWhitelists;
    address public creator;

    // this is for testnet only - [NOTE, USDC, USDT, ETH, ATOM]
    address[5] public assets = [
        0x03F734Bd9847575fDbE9bEaDDf9C166F880B5E5f,
        0xc51534568489f47949A828C8e3BF68463bdF3566,
        0x4fC30060226c45D8948718C95a78dFB237e88b40,
        0xCa03230E7FB13456326a234443aAd111AC96410A,
        0x40E41DC5845619E7Ba73957449b31DFbfB9678b2
    ];
    mapping(address => address) public cTokenMapping;

    // ratios denote how many tokens will a buyer get in exchange of existing token
    // for eg. ratios[0] = 10*10**18 meaning each user will get 10 tokens for each NOTE
    uint256[5] public ratios;

    bool public airdropped;
    bool public whitelistdropped;
    bool public creatordropped;

    address[] public buyers;
    mapping(address => bool) exists;
    mapping(address => uint256) buyerAmounts;
    mapping(address => bool) public whitelistClaimed;

    // Custom errors
    /**
     * @dev The amount provided is invalid.
     */
    error InvalidAmount();

    /**
     * @dev The token sale has maxed out.
     */
    error SaleMaxedOut();

    /**
     * @dev Failed to transfer asset tokens.
     */
    error TransferFailed();

    /**
     * @dev The token sale has ended.
     */
    error SaleEnded();

    /**
     * @dev Airdrop has already taken place.
     */
    error AirdropAlreadyDone();

    /**
     * @dev Airdrop is not available yet.
     */
    error AirdropNotAvailable();

    /**
     * @dev Creator drop has already taken place.
     */
    error CreatorDropAlreadyDone();

    /**
     * @dev Creator drop is not available yet.
     */
    error CreatorDropNotAvailable();

    /**
     * @dev Tokens have already been claimed.
     */
    error TokensAlreadyClaimed();

    /**
     * @dev Constructs the LaunchPool contract.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param _maxSupply The maximum supply of the token.
     * @param _creatorSupply The supply allocated to the creator.
     * @param _allocatedSupply The allocated supply for the sale.
     * @param _saleStartTime The start time of the token sale.
     * @param _saleDuration The duration of the token sale.
     * @param _creator The address of the creator.
     * @param _root The Merkle root for whitelisted addresses.
     * @param _ratios The ratios used in the sale.
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 _maxSupply,
        uint256 _creatorSupply,
        uint256 _allocatedSupply,
        uint256 _saleStartTime,
        uint256 _saleDuration,
        address _creator,
        bytes32 _root,
        uint256[5] memory _ratios
    ) ERC20(name, symbol) {
        maxSupply = _maxSupply;
        creatorSupply = _creatorSupply;
        allocatedSupply = _allocatedSupply;
        reservedSupply = (_maxSupply - _allocatedSupply) / 2;
        saleStartTime = _saleStartTime;
        saleDuration = _saleDuration;
        creator = _creator;
        merkleRootForWhitelists = _root;
        ratios = _ratios;
        // asset -> cAsset
        cTokenMapping[
            0x03F734Bd9847575fDbE9bEaDDf9C166F880B5E5f
        ] = 0x04E52476d318CdF739C38BD41A922787D441900c;
        cTokenMapping[
            0xc51534568489f47949A828C8e3BF68463bdF3566
        ] = 0x9160c5760a540cAfA24F90102cAA14C50497d5b7;
        cTokenMapping[
            0x4fC30060226c45D8948718C95a78dFB237e88b40
        ] = 0x3BEe0A8209e6F8c5c743F21e0cA99F2cb780D0D8;
        cTokenMapping[
            0xCa03230E7FB13456326a234443aAd111AC96410A
        ] = 0x260fCD909ab9dfF97B03591F83BEd5bBfc89A571;
        cTokenMapping[
            0x40E41DC5845619E7Ba73957449b31DFbfB9678b2
        ] = 0x90FCcb79Ad6f013A4bf62Ad43577eed7a8eb961B;
        // setting all bools to false
        airdropped = false;
        whitelistdropped = false;
        creatordropped = false;
    }

    /**
     * @dev Allows users to buy tokens during the sale period.
     * @param asset_index The index of the asset being used to buy tokens.
     * @param amount The amount of tokens to buy.
     */
    function buy(uint8 asset_index, uint256 amount) external {
        if (amount <= 0) {
            revert InvalidAmount();
        }
        uint256 ratio = ratios[asset_index];
        uint256 requiredAmount = amount * ratio;
        if (allocatedSupply + amount > maxSupply - reservedSupply) {
            revert SaleMaxedOut();
        }
        if (
            !IERC20(assets[asset_index]).transferFrom(
                msg.sender,
                address(this),
                requiredAmount
            )
        ) {
            revert TransferFailed();
        }
        if (
            block.timestamp >= saleStartTime &&
            block.timestamp <= saleStartTime + saleDuration
        ) {
            if (!exists[msg.sender]) {
                buyers.push(msg.sender);
                exists[msg.sender] = true;
                buyerAmounts[msg.sender] = amount;
                allocatedSupply += amount;
            } else {
                buyerAmounts[msg.sender] += amount;
                allocatedSupply += amount;
            }
        } else {
            revert SaleEnded();
        }
    }

    /**
     * @dev Verifies the Merkle proof and mints tokens to the whitelisted address.
     * @param proof The Merkle proof.
     * @param addr The address to claim tokens for.
     * @param amount The amount of tokens to claim.
     */
    function claim(
        bytes32[] memory proof,
        address addr,
        uint256 amount
    ) public {
        if (block.timestamp <= saleStartTime + saleDuration) {
            revert AirdropNotAvailable();
        }

        if (whitelistClaimed[addr]) {
            revert TokensAlreadyClaimed();
        }

        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(addr, amount)))
        );

        require(
            MerkleProof.verify(proof, merkleRootForWhitelists, leaf),
            "Invalid proof"
        );

        whitelistClaimed[addr] = true;
        _mint(addr, amount);
    }

    /**
     * @dev Airdrops tokens to buyers after the sale has ended.
     */
    function airdrop() external {
        if (airdropped) {
            revert AirdropAlreadyDone();
        }
        if (block.timestamp <= saleStartTime + saleDuration) {
            revert AirdropNotAvailable();
        }

        clm_and_dex_calls();

        for (uint256 i = 0; i < buyers.length; i++) {
            address buyer = buyers[i];
            uint256 amount = buyerAmounts[buyer];
            if (amount > 0) {
                mint(buyer, amount);
                delete buyerAmounts[buyer];
            }
        }
        airdropped = true;
    }

    /**
     * @dev Mints tokens for the creator after a specified period.
     */
    function creatordrop() external {
        if (creatordropped) {
            revert CreatorDropAlreadyDone();
        }
        if (block.timestamp <= saleStartTime + saleDuration + (86400 * 180)) {
            revert CreatorDropNotAvailable();
        }
        mint(creator, creatorSupply);
        creatordropped = true;
    }

    /**
     * @dev Mints the specified amount of tokens to the given address.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) internal {
        _mint(to, amount);
    }

    /**
     * @dev Handles CLM and DEX calls for liquidity provision and borrowing.
     */
    function clm_and_dex_calls() internal {
        // Minting cTokens = Supplying to CLM
        for (uint256 i = 0; i < assets.length; i++) {
            ERC20 underlying = ERC20(assets[i]);
            uint256 token_balance = underlying.balanceOf(address(this));
            if (token_balance > 0) {
                CErc20 cToken = CErc20(cTokenMapping[assets[i]]);
                underlying.approve(address(cToken), token_balance);
                assert(cToken.mint(token_balance) == 0);
            }
        }
        // Checking Liquidity - Testnet address is being used
        Comptroller troll = Comptroller(
            0xA51436eF5D46EE56B0906DeC620466153f7fb77e
        );
        (uint256 error, uint256 liquidity, uint256 shortfall) = troll
            .getAccountLiquidity(address(this));

        require(error == 0, "Something went wrong");
        require(shortfall == 0, "Negative liquidity balance");
        require(liquidity > 0, "Not enough collateral");

        // Borrowing NOTE - Testnet cNOTE address is being used
        CErc20 cNOTE = CErc20(0x04E52476d318CdF739C38BD41A922787D441900c);
        uint256 amt_borrow = liquidity - 1;
        require(cNOTE.borrow(amt_borrow) == 0, "Not enough collateral");

        // Creating new pair on DEX - Testnet address is being used for Router as well as for NOTE
        BaseV1Router01 testnet_dex = BaseV1Router01(
            0x463e7d4DF8fE5fb42D024cb57c77b76e6e74417a
        );
        (uint256 amountA, uint256 amountB, ) = testnet_dex.addLiquidity(
            address(this),
            0x03F734Bd9847575fDbE9bEaDDf9C166F880B5E5f,
            false,
            reservedSupply,
            amt_borrow,
            reservedSupply,
            amt_borrow,
            address(0),
            16725205800
        );

        require(
            amountA == reservedSupply && amountB == amt_borrow,
            "Couldn't add liquidity"
        );
    }
}
