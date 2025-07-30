#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, token, Address, BytesN, Env,
};

#[contracttype]
pub enum DataKey {
    Immutables,
    Initialized,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Immutables {
    pub hashlock: BytesN<32>,
    pub maker: Address,
    pub taker: Address,
    pub token: Address,
    pub amount: i128,
    pub cancellation_timestamp: u64,
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum Error {
    AlreadyInitialized = 1,
    NotInitialized = 2,
    InvalidSecret = 3,
    NotAuthorized = 4,
    TimePredicateNotMet = 5,
    NegativeAmount = 6,
}

#[contract]
pub struct SorobanEscrow;

#[contractimpl]
impl SorobanEscrow {
    /// Initialize the escrow with immutable parameters
    /// Can only be called once after deployment
    pub fn initialize(env: Env, immutables: Immutables) -> Result<(), Error> {
        // Check if already initialized
        if env.storage().instance().has(&DataKey::Initialized) {
            return Err(Error::AlreadyInitialized);
        }

        // Validate amount is non-negative
        if immutables.amount < 0 {
            return Err(Error::NegativeAmount);
        }

        // Store immutables and mark as initialized
        env.storage().instance().set(&DataKey::Immutables, &immutables);
        env.storage().instance().set(&DataKey::Initialized, &true);

        Ok(())
    }

    /// Withdraw funds by providing the correct secret
    /// Can only be called by the taker before cancellation timestamp
    pub fn withdraw(env: Env, secret: BytesN<32>) -> Result<(), Error> {
        let immutables = Self::get_immutables(&env)?;
        
        // Check authorization - only taker can withdraw
        immutables.taker.require_auth();

        // Check time predicate - must be before cancellation timestamp
        let current_timestamp = env.ledger().timestamp();
        if current_timestamp >= immutables.cancellation_timestamp {
            return Err(Error::TimePredicateNotMet);
        }

        // Verify secret matches hashlock
        let secret_hash = env.crypto().sha256(&secret.into());
        if BytesN::from_array(&env, &secret_hash.into()) != immutables.hashlock {
            return Err(Error::InvalidSecret);
        }

        // Transfer tokens to taker
        Self::transfer_tokens(&env, &immutables.token, &immutables.taker, immutables.amount);

        // Emit event
        env.events().publish(("withdraw",), &immutables.taker);

        Ok(())
    }

    /// Cancel the escrow and return funds to maker
    /// Can only be called by the maker after cancellation timestamp
    pub fn cancel(env: Env) -> Result<(), Error> {
        let immutables = Self::get_immutables(&env)?;
        
        // Check authorization - only maker can cancel
        immutables.maker.require_auth();

        // Check time predicate - must be after cancellation timestamp
        let current_timestamp = env.ledger().timestamp();
        if current_timestamp < immutables.cancellation_timestamp {
            return Err(Error::TimePredicateNotMet);
        }

        // Transfer tokens back to maker
        Self::transfer_tokens(&env, &immutables.token, &immutables.maker, immutables.amount);

        // Emit event
        env.events().publish(("cancel",), &immutables.maker);

        Ok(())
    }

    /// Get the immutable parameters of this escrow
    pub fn get_immutables(env: &Env) -> Result<Immutables, Error> {
        if !env.storage().instance().has(&DataKey::Initialized) {
            return Err(Error::NotInitialized);
        }
        
        let immutables: Immutables = env.storage().instance().get(&DataKey::Immutables).unwrap();
        Ok(immutables)
    }

    /// Helper function to transfer tokens
    fn transfer_tokens(env: &Env, token: &Address, to: &Address, amount: i128) {
        let token_client = token::Client::new(env, token);
        token_client.transfer(&env.current_contract_address(), to, &amount);
    }
}

mod test;