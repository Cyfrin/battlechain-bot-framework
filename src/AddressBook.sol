// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AddressBook
/// @notice Multi-chain categorized registry for protocol addresses
/// @dev Structure: Category ->Name -> Address
contract AddressBook is Ownable {

    event AddressRegistered(
        Category indexed category,
        string name,
        address indexed addr,
        string description
      );
    
    event AddressUpdated(
        Category indexed category,
        string name,
        address indexed oldAddr,
        address newAddr
      );      

    event AddressRemoved(
        Category indexed category,
        string name,
        address indexed addr
      );            

    
    error ZeroAddress();
    error EntryAlreadyExists(Category category, string name);
    error EntryNotFound(Category category, string name);


    enum Category {
        TOKEN,          // ERC20 tokens (USDC, WETH, DAI)
        POOL,           // LP pools (UniV2Pair, CurvePool)
        ROUTER,         // DEX routers (UniswapV2Router)
        FACTORY,        // Factory contracts (UniswapV3Factory)
        LENDING,        // Lending protocols (AavePool)
        ORACLE,         // Price oracles (ChainlinkETHUSD)
        FLASH_LOAN,     // Flash loan providers
        VAULT,          // Yield vaults
        GOVERNANCE,     // Governance contracts
        BATTLECHAIN,    // BattleChain core
        UTILITY,        // Utilities (Multicall, Permit2)
        OTHER
    }
    
    struct Entry {
        address addr;
        Category category;
        string name;
        string description;
        uint256 addedAt;
        bool exists;
    }

    /// @notice Main registry: category => name => address
    mapping(Category => mapping(string => address)) private _registry;

    /// @notice Check existence: category => name => exists
    mapping(Category => mapping(string => bool)) private _exists;

    /// @notice Names per category : category => names[]
    mapping(Category => string[]) private _names;

    /// @notice Entry metadata: keccak256(category, chainId, name) => Entry
    mapping(bytes32 => Entry) private _entries;


    
    constructor() Ownable(msg.sender) {}


    // Registration functions
    /// @notice Register a new address
    function register(
            Category category,
            string calldata name,
            address addr,
            string calldata description
        ) external onlyOwner {
            _register(category, name, addr, description);
    }

    /// @notice Batch register (same chain)
    function batchRegister(
        Category[] calldata categories,
        string[] calldata names,
        address[] calldata addrs,
        string[] calldata descriptions
    ) external onlyOwner {
        require(
            categories.length == names.length &&
            names.length == addrs.length &&
            addrs.length == descriptions.length,
            "Length mismatch"
        );

        for (uint256 i = 0; i < categories.length; i++) {
            _register(categories[i], names[i], addrs[i], descriptions[i]);
        }
    }

    function update(
        Category category,
        string calldata name,
        address newAddr
    ) external onlyOwner {
        if (newAddr == address(0)) revert ZeroAddress();
        if (!_exists[category][name]) {
            revert EntryNotFound(category, name);
        }

        address oldAddr = _registry[category][name];
        _registry[category][name] = newAddr;

        // Update entry
        bytes32 key = _getKey(category, name);
        _entries[key].addr = newAddr;
        _entries[key].addedAt = block.timestamp;

        emit AddressUpdated(category, name, oldAddr, newAddr);
    }

    function remove( Category category, 
                     string calldata name) external onlyOwner {                                                                                                                                                                                            
        bytes32 key = _getKey(category, name);                                                                                                                                                                        
        if (!_entries[key].exists) {                                                                                                                                                                                  
            revert EntryNotFound(category, name);                                                                                                                                                                     
        }
        address addr = _registry[category][name];
        delete _registry[category][name]; 
        delete _entries[key];   

        string[] storage names = _names[category];
        for (uint256 i = 0; i < names.length; i++) { 
            if (keccak256(bytes(names[i])) == keccak256(bytes(name))) {                                                                                                                                               
                names[i] = names[names.length - 1];                                                                                                                                                                   
                names.pop();
                break;
            }
        }
        emit AddressRemoved(category, name, addr); 
    }  


    // getter functions
    function get(Category category, string calldata name) external view returns (address) {  
        if (!_exists[category][name]) {
            revert EntryNotFound(category, name);
        }
        return _registry[category][name];
    }

    function exists(Category category, string calldata name) external view returns (bool) {                                                                                                                           
        bytes32 key = _getKey(category, name);                                                                                                                                                                        
        return _entries[key].exists;                                                                                                                                                                                  
    }

    function token(string calldata name) external view returns (address) {                                                                                                                                            
        return _registry[Category.TOKEN][name];                                                                                                                                                                       
    }

    function router(string calldata name) external view returns (address) {                                                                                                                                           
        return _registry[Category.ROUTER][name];                                                                                                                                                                      
    }

    // private functions
    function _register(
          Category category,
          string calldata name,
          address addr,
          string calldata description
      ) internal {
          if (addr == address(0)) revert ZeroAddress();
          if (_exists[category][name]) {
              revert EntryAlreadyExists(category, name);
          }

          // Store in registry
          _registry[category][name] = addr;
          _exists[category][name] = true;
          _names[category].push(name);

          // Store entry metadata
          bytes32 key = _getKey(category, name);
          _entries[key] = Entry({
              addr: addr,
              category: category,
              name: name,
              description: description,
              addedAt: block.timestamp,
              exists: true
          });

          emit AddressRegistered(category, name, addr, description);
      }

      function _getKey(
          Category category,
          string memory name
      ) internal pure returns (bytes32) {
          return keccak256(abi.encode(category, name));
      }


}