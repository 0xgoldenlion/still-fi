#![cfg(test)]
extern crate std;

use super::*;
use soroban_sdk::{
    testutils::Ledger,
    Env,
};

fn create_dutch_auction_contract(e: &Env) -> SorobanDutchAuctionClient {
    SorobanDutchAuctionClient::new(e, &e.register(SorobanDutchAuction, ()))
}

#[test]
fn test_calculate_taking_amount_at_start() {
    let env = Env::default();
    let contract = create_dutch_auction_contract(&env);
    
    // Set time to auction start
    env.ledger().with_mut(|li| {
        li.timestamp = 1000;
    });

    let result = contract.calculate_taking_amount(
        &100,      // making_amount
        &1000,     // taking_amount_start (higher price)
        &500,      // taking_amount_end (lower price)
        &1000,     // auction_start_time
        &2000,     // auction_end_time
    );

    assert_eq!(result, 1000); // Should return start price
}

#[test]
fn test_calculate_taking_amount_at_end() {
    let env = Env::default();
    let contract = create_dutch_auction_contract(&env);
    
    // Set time to after auction end
    env.ledger().with_mut(|li| {
        li.timestamp = 2500;
    });

    let result = contract.calculate_taking_amount(
        &100,      // making_amount
        &1000,     // taking_amount_start
        &500,      // taking_amount_end
        &1000,     // auction_start_time
        &2000,     // auction_end_time
    );

    assert_eq!(result, 500); // Should return end price
}

#[test]
fn test_calculate_taking_amount_midway() {
    let env = Env::default();
    let contract = create_dutch_auction_contract(&env);
    
    // Set time to middle of auction (50% through)
    env.ledger().with_mut(|li| {
        li.timestamp = 1500;
    });

    let result = contract.calculate_taking_amount(
        &100,      // making_amount
        &1000,     // taking_amount_start
        &500,      // taking_amount_end
        &1000,     // auction_start_time
        &2000,     // auction_end_time
    );

    assert_eq!(result, 750); // Should be halfway: 1000 - (500 * 0.5) = 750
}

#[test]
fn test_calculate_taking_amount_before_start() {
    let env = Env::default();
    let contract = create_dutch_auction_contract(&env);
    
    // Set time before auction start
    env.ledger().with_mut(|li| {
        li.timestamp = 500;
    });

    let result = contract.calculate_taking_amount(
        &100,      // making_amount
        &1000,     // taking_amount_start
        &500,      // taking_amount_end
        &1000,     // auction_start_time
        &2000,     // auction_end_time
    );

    assert_eq!(result, 1000); // Should return start price
}

#[test]
fn test_invalid_time_range() {
    let env = Env::default();
    let contract = create_dutch_auction_contract(&env);

    let result = contract.try_calculate_taking_amount(
        &100,      // making_amount
        &1000,     // taking_amount_start
        &500,      // taking_amount_end
        &2000,     // auction_start_time (after end time)
        &1000,     // auction_end_time
    );

    assert_eq!(result, Err(Ok(Error::InvalidTimeRange)));
}

#[test]
fn test_invalid_amount_range() {
    let env = Env::default();
    let contract = create_dutch_auction_contract(&env);

    let result = contract.try_calculate_taking_amount(
        &100,      // making_amount
        &500,      // taking_amount_start (lower than end)
        &1000,     // taking_amount_end
        &1000,     // auction_start_time
        &2000,     // auction_end_time
    );

    assert_eq!(result, Err(Ok(Error::InvalidAmountRange)));
}

#[test]
fn test_calculate_making_amount_midway() {
    let env = Env::default();
    let contract = create_dutch_auction_contract(&env);
    
    // Set time to middle of auction (50% through)
    env.ledger().with_mut(|li| {
        li.timestamp = 1500;
    });

    let result = contract.calculate_making_amount(
        &750,      // taking_amount
        &100,      // making_amount_start (lower)
        &200,      // making_amount_end (higher)
        &1000,     // auction_start_time
        &2000,     // auction_end_time
    );

    assert_eq!(result, 150); // Should be halfway: 100 + (100 * 0.5) = 150
}