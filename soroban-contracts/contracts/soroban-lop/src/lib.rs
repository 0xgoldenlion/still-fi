#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, token, Address, BytesN, Env,
};

// Import the Dutch auction contract
mod dutch_auction {
    soroban_sdk::contractimport!(
        file = "../../target/wasm32v1-none/release/soroban_dutch_auction_contract.wasm"
    );
}

#[contracttype]
pub enum DataKey {
    OrderState(BytesN<32>), // order_hash -> OrderState
    DutchAuctionContract,
    Admin,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Order {
    pub salt: u64,
    pub maker: Address,
    pub receiver: Address,
    pub maker_asset: Address,
    pub taker_asset: Address,
    pub making_amount: i128,
    pub taking_amount: i128,
    pub maker_traits: u64,
    // Dutch auction parameters (only used if IS_DUTCH_AUCTION flag is set)
    pub auction_start_time: u64,
    pub auction_end_time: u64,
    pub taking_amount_start: i128,
    pub taking_amount_end: i128,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum OrderState {
    Active,
    Filled,
    Cancelled,
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum Error {
    NotInitialized = 1,
    AlreadyInitialized = 2,
    NotAuthorized = 3,
    OrderAlreadyFilled = 4,
    OrderCancelled = 5,
    InsufficientBalance = 6,
    InvalidOrder = 7,
    DutchAuctionError = 8,
    TransferFailed = 9,
}

// Maker traits flags
const IS_DUTCH_AUCTION: u64 = 1 << 0;
const UNWRAP_WETH: u64 = 1 << 1;
const ALLOW_PARTIAL_FILLS: u64 = 1 << 2;

#[contract]
pub struct SorobanLOP;

#[contractimpl]
impl SorobanLOP {
    /// Initialize the LOP contract
    pub fn initialize(
        env: Env,
        admin: Address,
        dutch_auction_contract: Address,
    ) -> Result<(), Error> {
        // Check if already initialized
        if env.storage().instance().has(&DataKey::Admin) {
            return Err(Error::AlreadyInitialized);
        }

        // Store admin and Dutch auction contract address
        env.storage().instance().set(&DataKey::Admin, &admin);
        env.storage().instance().set(&DataKey::DutchAuctionContract, &dutch_auction_contract);

        Ok(())
    }

    /// Fill an order
    pub fn fill_order(
        env: Env,
        order: Order,
        taker: Address,
    ) -> Result<(), Error> {
        // Require authorization from taker
        taker.require_auth();

        // Calculate order hash
        let order_hash = Self::calculate_order_hash(&env, &order);

        // Check order state
        let order_state: OrderState = env
            .storage()
            .persistent()
            .get(&DataKey::OrderState(order_hash.clone()))
            .unwrap_or(OrderState::Active);

        match order_state {
            OrderState::Filled => return Err(Error::OrderAlreadyFilled),
            OrderState::Cancelled => return Err(Error::OrderCancelled),
            OrderState::Active => {},
        }

        // Require authorization from maker for their assets
        order.maker.require_auth();

        // Calculate actual amounts
        let (actual_making_amount, actual_taking_amount) = if Self::is_dutch_auction(&order) {
            // Get Dutch auction contract
            let dutch_auction_contract: Address = env
                .storage()
                .instance()
                .get(&DataKey::DutchAuctionContract)
                .ok_or(Error::NotInitialized)?;

            let dutch_auction_client = dutch_auction::Client::new(&env, &dutch_auction_contract);

            // Calculate current taking amount based on time
            let calculated_taking_amount = dutch_auction_client
                .calculate_taking_amount(
                    &order.making_amount,
                    &order.taking_amount_start,
                    &order.taking_amount_end,
                    &order.auction_start_time,
                    &order.auction_end_time,
                );

            (order.making_amount, calculated_taking_amount)
        } else {
            // Regular order - use fixed amounts
            (order.making_amount, order.taking_amount)
        };

        // Validate amounts are positive
        if actual_making_amount <= 0 || actual_taking_amount <= 0 {
            return Err(Error::InvalidOrder);
        }

        // Determine receiver (use order.receiver if specified, otherwise use taker)
        let receiver = if order.receiver == env.current_contract_address() {
            taker.clone()
        } else {
            order.receiver.clone()
        };

        // Execute token transfers
        // Transfer maker asset from maker to receiver
        let maker_token = token::Client::new(&env, &order.maker_asset);
        maker_token.transfer(&order.maker, &receiver, &actual_making_amount);

        // Transfer taker asset from taker to maker
        let taker_token = token::Client::new(&env, &order.taker_asset);
        taker_token.transfer(&taker, &order.maker, &actual_taking_amount);

        // Mark order as filled
        env.storage()
            .persistent()
            .set(&DataKey::OrderState(order_hash.clone()), &OrderState::Filled);

        // Extend TTL for the order state
        env.storage()
            .persistent()
            .extend_ttl(&DataKey::OrderState(order_hash.clone()), 100, 100);

        // Emit event
        env.events().publish(
            ("order_filled",),
            (order_hash, actual_making_amount, actual_taking_amount),
        );

        Ok(())
    }

    /// Cancel an order (only by maker)
    pub fn cancel_order(env: Env, order: Order) -> Result<(), Error> {
        // Require authorization from maker
        order.maker.require_auth();

        // Calculate order hash
        let order_hash = Self::calculate_order_hash(&env, &order);

        // Check current state
        let current_state: OrderState = env
            .storage()
            .persistent()
            .get(&DataKey::OrderState(order_hash.clone()))
            .unwrap_or(OrderState::Active);

        match current_state {
            OrderState::Filled => return Err(Error::OrderAlreadyFilled),
            OrderState::Cancelled => return Err(Error::OrderCancelled),
            OrderState::Active => {},
        }

        // Mark order as cancelled
        env.storage()
            .persistent()
            .set(&DataKey::OrderState(order_hash.clone()), &OrderState::Cancelled);

        // Extend TTL
        env.storage()
            .persistent()
            .extend_ttl(&DataKey::OrderState(order_hash.clone()), 100, 100);

        // Emit event
        env.events().publish(("order_cancelled",), order_hash);

        Ok(())
    }

    /// Get order state
    pub fn get_order_state(env: Env, order: Order) -> OrderState {
        let order_hash = Self::calculate_order_hash(&env, &order);
        env.storage()
            .persistent()
            .get(&DataKey::OrderState(order_hash))
            .unwrap_or(OrderState::Active)
    }

    /// Get current Dutch auction price for an order
    pub fn get_current_price(env: Env, order: Order) -> Result<i128, Error> {
        if !Self::is_dutch_auction(&order) {
            return Ok(order.taking_amount);
        }

        let dutch_auction_contract: Address = env
            .storage()
            .instance()
            .get(&DataKey::DutchAuctionContract)
            .ok_or(Error::NotInitialized)?;

        let dutch_auction_client = dutch_auction::Client::new(&env, &dutch_auction_contract);

        let price = dutch_auction_client
            .calculate_taking_amount(
                &order.making_amount,
                &order.taking_amount_start,
                &order.taking_amount_end,
                &order.auction_start_time,
                &order.auction_end_time,
            );

        Ok(price)
    }

    /// Helper function to check if order is a Dutch auction
    fn is_dutch_auction(order: &Order) -> bool {
        order.maker_traits & IS_DUTCH_AUCTION != 0
    }

    /// Calculate order hash (simplified version)
    fn calculate_order_hash(env: &Env, order: &Order) -> BytesN<32> {
        // Create a simple hash of the order data by concatenating bytes
        let mut data = soroban_sdk::Bytes::new(env);
        
        // Convert each field to bytes and append
        data.extend_from_slice(&order.salt.to_be_bytes());
        data.extend_from_slice(&order.making_amount.to_be_bytes());
        data.extend_from_slice(&order.taking_amount.to_be_bytes());
        data.extend_from_slice(&order.maker_traits.to_be_bytes());
        
        // Simple hash without complex string conversion
        env.crypto().sha256(&data).into()
    }

    /// Get admin address
    pub fn get_admin(env: Env) -> Result<Address, Error> {
        env.storage()
            .instance()
            .get(&DataKey::Admin)
            .ok_or(Error::NotInitialized)
    }

    /// Get Dutch auction contract address
    pub fn get_dutch_auction_contract(env: Env) -> Result<Address, Error> {
        env.storage()
            .instance()
            .get(&DataKey::DutchAuctionContract)
            .ok_or(Error::NotInitialized)
    }
}

mod test;