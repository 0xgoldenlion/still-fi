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

fn create_lop_contract(e: &Env) -> SorobanLOPClient {
    SorobanLOPClient::new(e, &e.register(SorobanLOP, ()))
}

fn create_dutch_auction_contract(e: &Env) -> dutch_auction::Client {
    dutch_auction::Client::new(e, &e.register(dutch_auction::WASM, ()))
}

#[test]
fn test_initialize() {
    let env = Env::default();
    let lop = create_lop_contract(&env);
    let dutch_auction = create_dutch_auction_contract(&env);
    let admin = Address::generate(&env);

    // Should initialize successfully
    lop.initialize(&admin, &dutch_auction.address);
    
    // Should fail to initialize again
    assert_eq!(
        lop.try_initialize(&admin, &dutch_auction.address),
        Err(Ok(Error::AlreadyInitialized))
    );

    // Check stored values
    assert_eq!(lop.get_admin(), admin.clone());
    assert_eq!(lop.get_dutch_auction_contract(), dutch_auction.address.clone());
}

#[test]
fn test_fill_regular_order() {
    let env = Env::default();
    env.mock_all_auths();
    
    let lop = create_lop_contract(&env);
    let dutch_auction = create_dutch_auction_contract(&env);
    let admin = Address::generate(&env);
    
    // Initialize LOP
    lop.initialize(&admin, &dutch_auction.address);

    // Set up participants and tokens
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    
    let (token_a, token_a_admin) = create_token_contract(&env, &token_admin);
    let (token_b, token_b_admin) = create_token_contract(&env, &token_admin);

    // Mint tokens
    token_a_admin.mint(&maker, &1000);
    token_b_admin.mint(&taker, &2000);

    // Create regular order (not Dutch auction)
    let order = Order {
        salt: 1,
        maker: maker.clone(),
        receiver: taker.clone(),
        maker_asset: token_a.address.clone(),
        taker_asset: token_b.address.clone(),
        making_amount: 1000,
        taking_amount: 2000,
        maker_traits: 0, // No flags set - regular order
        auction_start_time: 0,
        auction_end_time: 0,
        taking_amount_start: 0,
        taking_amount_end: 0,
    };

    // Fill the order
    lop.fill_order(&order, &taker);

    // Check balances
    assert_eq!(token_a.balance(&maker), 0);
    assert_eq!(token_a.balance(&taker), 1000);
    assert_eq!(token_b.balance(&maker), 2000);
    assert_eq!(token_b.balance(&taker), 0);

    // Check order state
    assert_eq!(lop.get_order_state(&order), OrderState::Filled);
}

#[test]
fn test_fill_dutch_auction_order() {
    let env = Env::default();
    env.mock_all_auths();
    
    // Set initial timestamp
    env.ledger().with_mut(|li| {
        li.timestamp = 1500; // Midway through auction
    });

    let lop = create_lop_contract(&env);
    let dutch_auction = create_dutch_auction_contract(&env);
    let admin = Address::generate(&env);
    
    // Initialize LOP
    lop.initialize(&admin, &dutch_auction.address);

    // Set up participants and tokens
    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    
    let (token_a, token_a_admin) = create_token_contract(&env, &token_admin);
    let (token_b, token_b_admin) = create_token_contract(&env, &token_admin);

    // Mint tokens
    token_a_admin.mint(&maker, &1000);
    token_b_admin.mint(&taker, &3000); // Extra to cover Dutch auction price

    // Create Dutch auction order
    let order = Order {
        salt: 2,
        maker: maker.clone(),
        receiver: taker.clone(),
        maker_asset: token_a.address.clone(),
        taker_asset: token_b.address.clone(),
        making_amount: 1000,
        taking_amount: 0, // Not used for Dutch auction
        maker_traits: IS_DUTCH_AUCTION, // Dutch auction flag
        auction_start_time: 1000,
        auction_end_time: 2000,
        taking_amount_start: 3000, // High starting price
        taking_amount_end: 1500,   // Lower ending price
    };

    // Get current price (should be 2250 at timestamp 1500)
    let current_price = lop.get_current_price(&order);
    assert_eq!(current_price, 2250); // Midway: 3000 - (1500 * 0.5) = 2250

    // Fill the order
    lop.fill_order(&order, &taker);

    // Check balances - taker should pay the calculated Dutch auction price
    assert_eq!(token_a.balance(&maker), 0);
    assert_eq!(token_a.balance(&taker), 1000);
    assert_eq!(token_b.balance(&maker), 2250); // Dutch auction price
    assert_eq!(token_b.balance(&taker), 750);  // Remaining: 3000 - 2250

    // Check order state
    assert_eq!(lop.get_order_state(&order), OrderState::Filled);
}

#[test]
fn test_cancel_order() {
    let env = Env::default();
    env.mock_all_auths();
    
    let lop = create_lop_contract(&env);
    let dutch_auction = create_dutch_auction_contract(&env);
    let admin = Address::generate(&env);
    
    // Initialize LOP
    lop.initialize(&admin, &dutch_auction.address);

    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token_a, _) = create_token_contract(&env, &token_admin);
    let (token_b, _) = create_token_contract(&env, &token_admin);

    let order = Order {
        salt: 3,
        maker: maker.clone(),
        receiver: taker.clone(),
        maker_asset: token_a.address.clone(),
        taker_asset: token_b.address.clone(),
        making_amount: 1000,
        taking_amount: 2000,
        maker_traits: 0,
        auction_start_time: 0,
        auction_end_time: 0,
        taking_amount_start: 0,
        taking_amount_end: 0,
    };

    // Cancel the order
    lop.cancel_order(&order);

    // Check order state
    assert_eq!(lop.get_order_state(&order), OrderState::Cancelled);

    // Try to fill cancelled order should fail
    assert_eq!(
        lop.try_fill_order(&order, &taker),
        Err(Ok(Error::OrderCancelled))
    );
}

#[test]
fn test_fill_already_filled_order() {
    let env = Env::default();
    env.mock_all_auths();
    
    let lop = create_lop_contract(&env);
    let dutch_auction = create_dutch_auction_contract(&env);
    let admin = Address::generate(&env);
    
    // Initialize LOP
    lop.initialize(&admin, &dutch_auction.address);

    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    
    let (token_a, token_a_admin) = create_token_contract(&env, &token_admin);
    let (token_b, token_b_admin) = create_token_contract(&env, &token_admin);

    // Mint tokens
    token_a_admin.mint(&maker, &2000); // Double amount for potential double fill
    token_b_admin.mint(&taker, &4000);

    let order = Order {
        salt: 4,
        maker: maker.clone(),
        receiver: taker.clone(),
        maker_asset: token_a.address.clone(),
        taker_asset: token_b.address.clone(),
        making_amount: 1000,
        taking_amount: 2000,
        maker_traits: 0,
        auction_start_time: 0,
        auction_end_time: 0,
        taking_amount_start: 0,
        taking_amount_end: 0,
    };

    // Fill the order first time
    lop.fill_order(&order, &taker);

    // Try to fill again should fail
    assert_eq!(
        lop.try_fill_order(&order, &taker),
        Err(Ok(Error::OrderAlreadyFilled))
    );
}

#[test]
fn test_dutch_auction_price_progression() {
    let env = Env::default();
    env.mock_all_auths();
    
    let lop = create_lop_contract(&env);
    let dutch_auction = create_dutch_auction_contract(&env);
    let admin = Address::generate(&env);
    
    // Initialize LOP
    lop.initialize(&admin, &dutch_auction.address);

    let maker = Address::generate(&env);
    let taker = Address::generate(&env);
    let token_admin = Address::generate(&env);
    let (token_a, _) = create_token_contract(&env, &token_admin);
    let (token_b, _) = create_token_contract(&env, &token_admin);

    let order = Order {
        salt: 5,
        maker: maker.clone(),
        receiver: taker.clone(),
        maker_asset: token_a.address.clone(),
        taker_asset: token_b.address.clone(),
        making_amount: 1000,
        taking_amount: 0,
        maker_traits: IS_DUTCH_AUCTION,
        auction_start_time: 1000,
        auction_end_time: 2000,
        taking_amount_start: 2000, // High starting price
        taking_amount_end: 1000,   // Lower ending price
    };

    // Test at start
    env.ledger().with_mut(|li| { li.timestamp = 1000; });
    assert_eq!(lop.get_current_price(&order), 2000);

    // Test at 25% through
    env.ledger().with_mut(|li| { li.timestamp = 1250; });
    assert_eq!(lop.get_current_price(&order), 1750);

    // Test at 50% through
    env.ledger().with_mut(|li| { li.timestamp = 1500; });
    assert_eq!(lop.get_current_price(&order), 1500);

    // Test at 75% through
    env.ledger().with_mut(|li| { li.timestamp = 1750; });
    assert_eq!(lop.get_current_price(&order), 1250);

    // Test at end
    env.ledger().with_mut(|li| { li.timestamp = 2000; });
    assert_eq!(lop.get_current_price(&order), 1000);

    // Test after end
    env.ledger().with_mut(|li| { li.timestamp = 2500; });
    assert_eq!(lop.get_current_price(&order), 1000);
}