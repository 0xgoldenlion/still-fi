#![cfg(test)]
extern crate std;

use super::*;
use soroban_sdk::{
    testutils::{Address as _, Ledger},
    Address, Env,
};

// Import the actual contract WASMs for testing
const LOP_WASM: &[u8] = include_bytes!("../../../target/wasm32v1-none/release/soroban_lop_contract.wasm");
const DUTCH_AUCTION_WASM: &[u8] = include_bytes!("../../../target/wasm32v1-none/release/soroban_dutch_auction_contract.wasm");

fn create_factory_contract(e: &Env) -> SorobanLOPFactoryClient {
    SorobanLOPFactoryClient::new(e, &e.register(SorobanLOPFactory, ()))
}

#[test]
fn test_initialize() {
    let env = Env::default();
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    let lop_wasm_hash = BytesN::from_array(&env, &[1; 32]);
    let dutch_auction_wasm_hash = BytesN::from_array(&env, &[2; 32]);

    // Should initialize successfully
    factory.initialize(&admin, &lop_wasm_hash, &dutch_auction_wasm_hash);
    
    // Should fail to initialize again
    assert_eq!(
        factory.try_initialize(&admin, &lop_wasm_hash, &dutch_auction_wasm_hash),
        Err(Ok(Error::AlreadyInitialized))
    );

    // Check stored values
    assert_eq!(factory.get_admin(), admin);
    assert_eq!(factory.get_lop_wasm_hash(), lop_wasm_hash);
    assert_eq!(factory.get_dutch_auction_wasm_hash(), dutch_auction_wasm_hash);
}

#[test]
fn test_deploy_lop() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set up factory
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    
    // Upload the contract WASMs
    let lop_wasm_hash = env.deployer().upload_contract_wasm(LOP_WASM);
    let dutch_auction_wasm_hash = env.deployer().upload_contract_wasm(DUTCH_AUCTION_WASM);
    
    factory.initialize(&admin, &lop_wasm_hash, &dutch_auction_wasm_hash);

    let salt = BytesN::from_array(&env, &[42; 32]);
    let lop_admin = Address::generate(&env);

    // Deploy LOP
    let lop_address = factory.deploy_lop(&salt, &lop_admin);
    
    // Verify the LOP was deployed and initialized
    let lop_client = lop::Client::new(&env, &lop_address);
    
    assert_eq!(lop_client.get_admin(), lop_admin);
}

#[test]
fn test_deploy_dutch_auction() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set up factory
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    
    // Upload the contract WASMs
    let lop_wasm_hash = env.deployer().upload_contract_wasm(LOP_WASM);
    let dutch_auction_wasm_hash = env.deployer().upload_contract_wasm(DUTCH_AUCTION_WASM);
    
    factory.initialize(&admin, &lop_wasm_hash, &dutch_auction_wasm_hash);

    let salt = BytesN::from_array(&env, &[42; 32]);

    // Deploy Dutch auction
    let dutch_auction_address = factory.deploy_dutch_auction(&salt);
    
    // Verify the contract was deployed
    let dutch_auction_client = dutch_auction::Client::new(&env, &dutch_auction_address);
    
    // Test that it works - set a timestamp first
    env.ledger().with_mut(|li| { li.timestamp = 1500; });
    let result = dutch_auction_client.calculate_taking_amount(
        &100, &1000, &500, &1000, &2000
    );
    assert!(result > 0); // Should return a valid amount
}

#[test]
fn test_get_addresses() {
    let env = Env::default();
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    
    // Upload the contract WASMs
    let lop_wasm_hash = env.deployer().upload_contract_wasm(LOP_WASM);
    let dutch_auction_wasm_hash = env.deployer().upload_contract_wasm(DUTCH_AUCTION_WASM);
    
    factory.initialize(&admin, &lop_wasm_hash, &dutch_auction_wasm_hash);

    let lop_salt = BytesN::from_array(&env, &[42; 32]);
    let dutch_auction_salt = BytesN::from_array(&env, &[43; 32]); // Use different salt

    // Get predicted addresses
    let predicted_lop_address = factory.get_lop_address(&lop_salt);
    let predicted_dutch_auction_address = factory.get_dutch_auction_address(&dutch_auction_salt);

    // Deploy contracts with respective salts
    let lop_admin = Address::generate(&env);
    let actual_lop_address = factory.deploy_lop(&lop_salt, &lop_admin);
    let actual_dutch_auction_address = factory.deploy_dutch_auction(&dutch_auction_salt);

    // Addresses should match predictions
    assert_eq!(predicted_lop_address, actual_lop_address);
    assert_eq!(predicted_dutch_auction_address, actual_dutch_auction_address);
}

#[test]
fn test_update_wasm_hashes() {
    let env = Env::default();
    env.mock_all_auths();
    
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    let initial_lop_wasm_hash = BytesN::from_array(&env, &[1; 32]);
    let initial_dutch_auction_wasm_hash = BytesN::from_array(&env, &[2; 32]);
    let new_lop_wasm_hash = BytesN::from_array(&env, &[3; 32]);
    let new_dutch_auction_wasm_hash = BytesN::from_array(&env, &[4; 32]);

    factory.initialize(&admin, &initial_lop_wasm_hash, &initial_dutch_auction_wasm_hash);
    
    // Update WASM hashes
    factory.update_lop_wasm_hash(&new_lop_wasm_hash);
    factory.update_dutch_auction_wasm_hash(&new_dutch_auction_wasm_hash);
    
    // Verify updates
    assert_eq!(factory.get_lop_wasm_hash(), new_lop_wasm_hash);
    assert_eq!(factory.get_dutch_auction_wasm_hash(), new_dutch_auction_wasm_hash);
}