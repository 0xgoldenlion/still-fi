#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, Address, BytesN, Env, IntoVal, Symbol, Vec,
};

// Define the Immutables struct locally to match the escrow contract exactly
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

#[contracttype]
pub enum DataKey {
    EscrowWasmHash,
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
pub struct SorobanEscrowFactory;

#[contractimpl]
impl SorobanEscrowFactory {
    /// Initialize the factory with the escrow contract WASM hash
    pub fn initialize(env: Env, admin: Address, escrow_wasm_hash: BytesN<32>) -> Result<(), Error> {
        // Check if already initialized
        if env.storage().instance().has(&DataKey::EscrowWasmHash) {
            return Err(Error::AlreadyInitialized);
        }

        // Store the WASM hash and admin
        env.storage().instance().set(&DataKey::EscrowWasmHash, &escrow_wasm_hash);
        env.storage().instance().set(&DataKey::Admin, &admin);

        Ok(())
    }

    /// Deploy a new escrow contract with deterministic address
    pub fn deploy_escrow(
        env: Env,
        immutables: Immutables,
        salt: BytesN<32>,
    ) -> Result<Address, Error> {
        // Get the stored WASM hash
        let escrow_wasm_hash: BytesN<32> = env
            .storage()
            .instance()
            .get(&DataKey::EscrowWasmHash)
            .ok_or(Error::NotInitialized)?;

        // Deploy the contract deterministically WITHOUT constructor parameters
        let escrow_address = env
            .deployer()
            .with_address(env.current_contract_address(), salt)
            .deploy_v2(escrow_wasm_hash, ());

        // Initialize the escrow contract by calling its initialize function directly
        let initialize_args = Vec::from_array(&env, [immutables.into_val(&env)]);
        let result: Result<(), soroban_sdk::Error> = env.invoke_contract(&escrow_address, &Symbol::new(&env, "initialize"), initialize_args);
        
        match result {
            Ok(_) => {},
            Err(_) => return Err(Error::DeploymentFailed),
        }

        // Emit deployment event
        env.events().publish(("deploy_escrow",), &escrow_address);

        Ok(escrow_address)
    }

    /// Get the deterministic address of an escrow contract without deploying it
    pub fn get_escrow_address(
        env: Env,
        salt: BytesN<32>,
    ) -> Result<Address, Error> {
        // Get the stored WASM hash (we don't use it but need to check if initialized)
        let _escrow_wasm_hash: BytesN<32> = env
            .storage()
            .instance()
            .get(&DataKey::EscrowWasmHash)
            .ok_or(Error::NotInitialized)?;

        // Compute the deterministic address
        let escrow_address = env
            .deployer()
            .with_address(env.current_contract_address(), salt)
            .deployed_address();

        Ok(escrow_address)
    }

    /// Update the escrow WASM hash (admin only)
    pub fn update_escrow_wasm_hash(env: Env, new_wasm_hash: BytesN<32>) -> Result<(), Error> {
        // Check authorization
        let admin: Address = env
            .storage()
            .instance()
            .get(&DataKey::Admin)
            .ok_or(Error::NotInitialized)?;
        
        admin.require_auth();

        // Update the WASM hash
        env.storage().instance().set(&DataKey::EscrowWasmHash, &new_wasm_hash);

        Ok(())
    }

    /// Get the current escrow WASM hash
    pub fn get_escrow_wasm_hash(env: Env) -> Result<BytesN<32>, Error> {
        env.storage()
            .instance()
            .get(&DataKey::EscrowWasmHash)
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

mod test;