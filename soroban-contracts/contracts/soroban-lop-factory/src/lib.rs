#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, Address, BytesN, Env,
};

// Import the LOP and Dutch auction contracts
mod lop {
    soroban_sdk::contractimport!(
        file = "../../target/wasm32v1-none/release/soroban_lop_contract.wasm"
    );
}

mod dutch_auction {
    soroban_sdk::contractimport!(
        file = "../../target/wasm32v1-none/release/soroban_dutch_auction_contract.wasm"
    );
}

#[contracttype]
pub enum DataKey {
    LOPWasmHash,
    DutchAuctionWasmHash,
    Admin,
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum Error {
    NotInitialized = 1,
    AlreadyInitialized = 2,
    NotAuthorized = 3,
    DeploymentFailed = 4,
}

#[contract]
pub struct SorobanLOPFactory;

#[contractimpl]
impl SorobanLOPFactory {
    /// Initialize the factory with WASM hashes
    pub fn initialize(
        env: Env,
        admin: Address,
        lop_wasm_hash: BytesN<32>,
        dutch_auction_wasm_hash: BytesN<32>,
    ) -> Result<(), Error> {
        // Check if already initialized
        if env.storage().instance().has(&DataKey::Admin) {
            return Err(Error::AlreadyInitialized);
        }

        // Store the WASM hashes and admin
        env.storage().instance().set(&DataKey::LOPWasmHash, &lop_wasm_hash);
        env.storage().instance().set(&DataKey::DutchAuctionWasmHash, &dutch_auction_wasm_hash);
        env.storage().instance().set(&DataKey::Admin, &admin);

        Ok(())
    }

    /// Deploy a new LOP contract with deterministic address
    pub fn deploy_lop(
        env: Env,
        salt: BytesN<32>,
        admin: Address,
    ) -> Result<Address, Error> {
        // Get the stored WASM hash
        let lop_wasm_hash: BytesN<32> = env
            .storage()
            .instance()
            .get(&DataKey::LOPWasmHash)
            .ok_or(Error::NotInitialized)?;

        // First deploy Dutch auction contract for this LOP instance
        let dutch_auction_salt = env.crypto().sha256(&salt.clone().into()).into();
        let dutch_auction_address = deploy_dutch_auction_internal(&env, dutch_auction_salt)?;

        // Deploy the LOP contract deterministically
        let lop_address = env
            .deployer()
            .with_address(env.current_contract_address(), salt)
            .deploy_v2(lop_wasm_hash, ());

        // Create client and initialize the deployed LOP
        let lop_client = lop::Client::new(&env, &lop_address);

        // Initialize the LOP contract
        match lop_client.try_initialize(&admin, &dutch_auction_address) {
            Ok(_) => {},
            Err(_) => return Err(Error::DeploymentFailed),
        }

        // Emit deployment event
        env.events().publish(("deploy_lop",), &lop_address);

        Ok(lop_address)
    }

    /// Deploy a new Dutch auction contract with deterministic address
    pub fn deploy_dutch_auction(
        env: Env,
        salt: BytesN<32>,
    ) -> Result<Address, Error> {
        deploy_dutch_auction_internal(&env, salt)
    }

    /// Get the deterministic address of a LOP contract without deploying it
    pub fn get_lop_address(
        env: Env,
        salt: BytesN<32>,
    ) -> Result<Address, Error> {
        // Check if initialized
        let _: BytesN<32> = env
            .storage()
            .instance()
            .get(&DataKey::LOPWasmHash)
            .ok_or(Error::NotInitialized)?;

        // Compute the deterministic address
        let lop_address = env
            .deployer()
            .with_address(env.current_contract_address(), salt)
            .deployed_address();

        Ok(lop_address)
    }

    /// Get the deterministic address of a Dutch auction contract without deploying it
    pub fn get_dutch_auction_address(
        env: Env,
        salt: BytesN<32>,
    ) -> Result<Address, Error> {
        // Check if initialized
        let _: BytesN<32> = env
            .storage()
            .instance()
            .get(&DataKey::DutchAuctionWasmHash)
            .ok_or(Error::NotInitialized)?;

        // Compute the deterministic address
        let dutch_auction_address = env
            .deployer()
            .with_address(env.current_contract_address(), salt)
            .deployed_address();

        Ok(dutch_auction_address)
    }

    /// Update the LOP WASM hash (admin only)
    pub fn update_lop_wasm_hash(env: Env, new_wasm_hash: BytesN<32>) -> Result<(), Error> {
        // Check authorization
        let admin: Address = env
            .storage()
            .instance()
            .get(&DataKey::Admin)
            .ok_or(Error::NotInitialized)?;
        
        admin.require_auth();

        // Update the WASM hash
        env.storage().instance().set(&DataKey::LOPWasmHash, &new_wasm_hash);

        Ok(())
    }

    /// Update the Dutch auction WASM hash (admin only)
    pub fn update_dutch_auction_wasm_hash(env: Env, new_wasm_hash: BytesN<32>) -> Result<(), Error> {
        // Check authorization
        let admin: Address = env
            .storage()
            .instance()
            .get(&DataKey::Admin)
            .ok_or(Error::NotInitialized)?;
        
        admin.require_auth();

        // Update the WASM hash
        env.storage().instance().set(&DataKey::DutchAuctionWasmHash, &new_wasm_hash);

        Ok(())
    }

    /// Get the current LOP WASM hash
    pub fn get_lop_wasm_hash(env: Env) -> Result<BytesN<32>, Error> {
        env.storage()
            .instance()
            .get(&DataKey::LOPWasmHash)
            .ok_or(Error::NotInitialized)
    }

    /// Get the current Dutch auction WASM hash
    pub fn get_dutch_auction_wasm_hash(env: Env) -> Result<BytesN<32>, Error> {
        env.storage()
            .instance()
            .get(&DataKey::DutchAuctionWasmHash)
            .ok_or(Error::NotInitialized)
    }

    /// Get the admin address
    pub fn get_admin(env: Env) -> Result<Address, Error> {
        env.storage()
            .instance()
            .get(&DataKey::Admin)
            .ok_or(Error::NotInitialized)
    }
}

/// Internal helper function to deploy Dutch auction contract
fn deploy_dutch_auction_internal(env: &Env, salt: BytesN<32>) -> Result<Address, Error> {
    // Get the stored WASM hash
    let dutch_auction_wasm_hash: BytesN<32> = env
        .storage()
        .instance()
        .get(&DataKey::DutchAuctionWasmHash)
        .ok_or(Error::NotInitialized)?;

    // Deploy the contract deterministically
    let dutch_auction_address = env
        .deployer()
        .with_address(env.current_contract_address(), salt)
        .deploy_v2(dutch_auction_wasm_hash, ());

    // Emit deployment event
    env.events().publish(("deploy_dutch_auction",), &dutch_auction_address);

    Ok(dutch_auction_address)
}

mod test;