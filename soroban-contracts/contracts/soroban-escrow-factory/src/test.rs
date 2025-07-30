#![cfg(test)]
extern crate std;

use super::*;
use soroban_sdk::{
    testutils::{Address as _, Ledger},
    token, Address, Env,
};

fn create_token_contract<'a>(
    e: &Env,
    admin: &Address,
) -> (token::Client<'a>, token::StellarAssetClient<'a>) {
    let sac = e.register_stellar_asset_contract_v2(admin.clone());
    (
        token::Client::new(e, &sac.address()),
        token::StellarAssetClient::new(e, &sac.address()),
    )
}

fn create_factory_contract(e: &Env) -> SorobanEscrowFactoryClient {
    SorobanEscrowFactoryClient::new(e, &e.register(SorobanEscrowFactory, ()))
}

#[test]
fn test_initialize() {
    let env = Env::default();
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    let wasm_hash = BytesN::from_array(&env, &[1; 32]);

    // Should initialize successfully
    factory.initialize(&admin, &wasm_hash);
    
    // Should fail to initialize again
    assert_eq!(
        factory.try_initialize(&admin, &wasm_hash),
        Err(Ok(Error::AlreadyInitialized))
    );

    // Check stored values
    assert_eq!(factory.get_escrow_wasm_hash(), wasm_hash);
    assert_eq!(factory.get_admin(), admin);
}

#[test]
fn test_deploy_escrow() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set up factory
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    
    // Upload the escrow contract WASM
    let escrow_wasm_hash = env.deployer().upload_contract_wasm(escrow::WASM);
    
    factory.initialize(&admin, &escrow_wasm_hash);

    // Set up test data
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, token_admin_client) = create_token_contract(&env, &token_admin);
    
    let immutables = escrow::Immutables {
        hashlock: BytesN::from_array(&env, &[1; 32]),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 12345,
    };

    let salt = BytesN::from_array(&env, &[42; 32]);

    // Deploy escrow
    let escrow_address = factory.deploy_escrow(&immutables, &salt);
    
    // Verify the escrow was deployed and initialized
    let escrow_client = escrow::Client::new(&env, &escrow_address);
    
    let result = escrow_client.get_immutables();
    assert_eq!(result, immutables);
}

#[test]
fn test_get_escrow_address() {
    let env = Env::default();
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    
    // Upload the escrow contract WASM
    let escrow_wasm_hash = env.deployer().upload_contract_wasm(escrow::WASM);
    
    factory.initialize(&admin, &escrow_wasm_hash);

    let salt = BytesN::from_array(&env, &[42; 32]);

    // Get predicted address
    let predicted_address = factory.get_escrow_address(&salt);

    // Deploy escrow with same salt
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, _) = create_token_contract(&env, &token_admin);
    
    let immutables = escrow::Immutables {
        hashlock: BytesN::from_array(&env, &[1; 32]),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 12345,
    };

    let actual_address = factory.deploy_escrow(&immutables, &salt);

    // Addresses should match
    assert_eq!(predicted_address, actual_address);
}

#[test]
fn test_update_escrow_wasm_hash() {
    let env = Env::default();
    env.mock_all_auths();
    
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    let initial_wasm_hash = BytesN::from_array(&env, &[1; 32]);
    let new_wasm_hash = BytesN::from_array(&env, &[2; 32]);

    factory.initialize(&admin, &initial_wasm_hash);
    
    // Update WASM hash
    factory.update_escrow_wasm_hash(&new_wasm_hash);
    
    // Verify update
    assert_eq!(factory.get_escrow_wasm_hash(), new_wasm_hash);
}

#[test]
fn test_end_to_end_escrow_flow() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set initial timestamp
    env.ledger().with_mut(|li| {
        li.timestamp = 10000;
    });

    // Set up factory
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    let escrow_wasm_hash = env.deployer().upload_contract_wasm(escrow::WASM);
    factory.initialize(&admin, &escrow_wasm_hash);

    // Set up test participants and token
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, token_admin_client) = create_token_contract(&env, &token_admin);
    
    // Create secret and its hash
    let secret = BytesN::from_array(&env, &[42; 32]);
    let secret_hash = env.crypto().sha256(&secret.into());
    
    let immutables = escrow::Immutables {
        hashlock: BytesN::from_array(&env, &secret_hash.into()),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 15000,
    };

    let salt = BytesN::from_array(&env, &[1; 32]);

    // Deploy escrow
    let escrow_address = factory.deploy_escrow(&immutables, &salt);
    let escrow_client = escrow::Client::new(&env, &escrow_address);
    
    // Fund the escrow
    token_admin_client.mint(&escrow_address, &1000);
    
    // Test successful withdrawal - create a fresh secret for withdrawal
    let secret_for_withdrawal = BytesN::from_array(&env, &[42; 32]);
    escrow_client.withdraw(&secret_for_withdrawal);
    assert_eq!(token.balance(&taker), 1000);
    assert_eq!(token.balance(&escrow_address), 0);
}

#[test]
fn test_escrow_cancellation_flow() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set initial timestamp after cancellation time
    env.ledger().with_mut(|li| {
        li.timestamp = 20000;
    });

    // Set up factory and deploy escrow
    let factory = create_factory_contract(&env);
    let admin = Address::generate(&env);
    let escrow_wasm_hash = env.deployer().upload_contract_wasm(escrow::WASM);
    factory.initialize(&admin, &escrow_wasm_hash);

    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, token_admin_client) = create_token_contract(&env, &token_admin);
    
    let immutables = escrow::Immutables {
        hashlock: BytesN::from_array(&env, &[1; 32]),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 15000,
    };

    let salt = BytesN::from_array(&env, &[2; 32]);
    let escrow_address = factory.deploy_escrow(&immutables, &salt);
    let escrow_client = escrow::Client::new(&env, &escrow_address);
    
    // Fund the escrow
    token_admin_client.mint(&escrow_address, &1000);
    
    // Test successful cancellation
    escrow_client.cancel();
    assert_eq!(token.balance(&maker), 1000);
    assert_eq!(token.balance(&escrow_address), 0);
}