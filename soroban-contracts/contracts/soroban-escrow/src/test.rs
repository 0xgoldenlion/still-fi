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

fn create_escrow_contract(e: &Env) -> SorobanEscrowClient {
    SorobanEscrowClient::new(e, &e.register(SorobanEscrow, ()))
}

#[test]
fn test_initialize() {
    let env = Env::default();
    let escrow = create_escrow_contract(&env);
    
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, _) = create_token_contract(&env, &token_admin);
    
    let immutables = Immutables {
        hashlock: BytesN::from_array(&env, &[1; 32]),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 12345,
    };

    // Should initialize successfully
    assert_eq!(escrow.initialize(&immutables), ());
    
    // Should fail to initialize again
    assert_eq!(escrow.try_initialize(&immutables), Err(Ok(Error::AlreadyInitialized)));
}

#[test]
fn test_withdraw_success() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set ledger timestamp before cancellation
    env.ledger().with_mut(|li| {
        li.timestamp = 10000;
    });

    let escrow = create_escrow_contract(&env);
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, token_admin_client) = create_token_contract(&env, &token_admin);
    
    // Create secret and its hash
    let secret = BytesN::from_array(&env, &[42; 32]);
    let secret_hash = env.crypto().sha256(&secret.clone().into());
    
    let immutables = Immutables {
        hashlock: secret_hash.into(),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 12345,
    };

    // Initialize escrow
    escrow.initialize(&immutables);
    
    // Fund the escrow contract
    token_admin_client.mint(&escrow.address, &1000);
    
    // Withdraw should succeed
    assert_eq!(escrow.withdraw(&secret), ());
    
    // Check token balance
    assert_eq!(token.balance(&taker), 1000);
    assert_eq!(token.balance(&escrow.address), 0);
}

#[test]
fn test_withdraw_invalid_secret() {
    let env = Env::default();
    env.mock_all_auths();
    
    env.ledger().with_mut(|li| {
        li.timestamp = 10000;
    });

    let escrow = create_escrow_contract(&env);
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, token_admin_client) = create_token_contract(&env, &token_admin);
    
    let immutables = Immutables {
        hashlock: BytesN::from_array(&env, &[1; 32]),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 12345,
    };

    escrow.initialize(&immutables);
    token_admin_client.mint(&escrow.address, &1000);
    
    // Wrong secret should fail
    let wrong_secret = BytesN::from_array(&env, &[42; 32]);
    assert_eq!(escrow.try_withdraw(&wrong_secret), Err(Ok(Error::InvalidSecret)));
}

#[test]
fn test_withdraw_after_cancellation_time() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set ledger timestamp after cancellation
    env.ledger().with_mut(|li| {
        li.timestamp = 15000;
    });

    let escrow = create_escrow_contract(&env);
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, _) = create_token_contract(&env, &token_admin);
    
    let secret = BytesN::from_array(&env, &[42; 32]);
    let secret_hash = env.crypto().sha256(&secret.clone().into());
    
    let immutables = Immutables {
        hashlock: secret_hash.into(),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 12345,
    };

    escrow.initialize(&immutables);
    
    // Should fail due to time predicate
    assert_eq!(escrow.try_withdraw(&secret), Err(Ok(Error::TimePredicateNotMet)));
}

#[test]
fn test_cancel_success() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set ledger timestamp after cancellation
    env.ledger().with_mut(|li| {
        li.timestamp = 15000;
    });

    let escrow = create_escrow_contract(&env);
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, token_admin_client) = create_token_contract(&env, &token_admin);
    
    let immutables = Immutables {
        hashlock: BytesN::from_array(&env, &[1; 32]),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 12345,
    };

    escrow.initialize(&immutables);
    token_admin_client.mint(&escrow.address, &1000);
    
    // Cancel should succeed
    assert_eq!(escrow.cancel(), ());
    
    // Check token balance
    assert_eq!(token.balance(&maker), 1000);
    assert_eq!(token.balance(&escrow.address), 0);
}

#[test]
fn test_cancel_before_cancellation_time() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set ledger timestamp before cancellation
    env.ledger().with_mut(|li| {
        li.timestamp = 10000;
    });

    let escrow = create_escrow_contract(&env);
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, _) = create_token_contract(&env, &token_admin);
    
    let immutables = Immutables {
        hashlock: BytesN::from_array(&env, &[1; 32]),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: 1000,
        cancellation_timestamp: 12345,
    };

    escrow.initialize(&immutables);
    
    // Should fail due to time predicate
    assert_eq!(escrow.try_cancel(), Err(Ok(Error::TimePredicateNotMet)));
}

#[test]
fn test_negative_amount() {
    let env = Env::default();
    let escrow = create_escrow_contract(&env);
    
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token, _) = create_token_contract(&env, &token_admin);
    
    let immutables = Immutables {
        hashlock: BytesN::from_array(&env, &[1; 32]),
        maker: maker.clone(),
        taker: taker.clone(),
        token: token.address.clone(),
        amount: -100, // Negative amount
        cancellation_timestamp: 12345,
    };

    // Should fail with negative amount
    assert_eq!(escrow.try_initialize(&immutables), Err(Ok(Error::NegativeAmount)));
}