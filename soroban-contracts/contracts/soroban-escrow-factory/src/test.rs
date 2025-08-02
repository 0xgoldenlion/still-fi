#![cfg(test)]
extern crate std;

use soroban_sdk::{
    testutils::{Address as _, Ledger},
    token, Address, Bytes, BytesN, Env,
};

// ---------- Adjust these imports to your paths if needed ----------
mod factory {
    // If factory is another crate/artifact, point to its compiled WASM:
    // e.g. "../../target/wasm32v1-none/release/soroban_escrow_factory_contract.wasm"
    soroban_sdk::contractimport!(file = "../../target/wasm32v1-none/release/soroban_escrow_factory_contract.wasm");
}
mod escrow {
    // If THIS crate is the escrow contract, you can REMOVE this import and
    // instead use the generated in-crate client type (e.g., SorobanEscrowClient).
    // Otherwise, import the escrow wasm like this:
    soroban_sdk::contractimport!(file = "../../target/wasm32v1-none/release/soroban_escrow_contract.wasm");
}

// Mirror the Immutables struct the factory expects (must match your contract)
#[derive(Clone)]
struct Immutables {
    hashlock: BytesN<32>,
    maker: Address,
    taker: Address,
    token: Address,
    amount: i128,
    cancellation_timestamp: u64,
}

// Helpers
fn create_accounts(env: &Env) -> (Address, Address, Address) {
    let admin = Address::generate(env);
    let maker = Address::generate(env);
    let taker = Address::generate(env);
    (admin, maker, taker)
}

fn create_token_contract<'a>(
    env: &Env,
    admin: &Address,
) -> (token::Client<'a>, token::StellarAssetClient<'a>, Address) {
    // Register a Stellar Asset Contract (SAC v2)
    let sac = env.register_stellar_asset_contract_v2(admin.clone());
    let token = token::Client::new(env, &sac.address());
    let admin_client = token::StellarAssetClient::new(env, &sac.address());
    (token, admin_client, sac.address())
}

fn sha256_bytes32(env: &Env, secret_32: &[u8; 32]) -> BytesN<32> {
    let b = Bytes::from_array(env, secret_32);
    env.crypto().sha256(&b).into()
}

fn build_immutables(
    env: &Env,
    token_addr: &Address,
    maker: &Address,
    taker: &Address,
    amount: i128,
    cancel_ts: u64,
    secret: &[u8; 32],
) -> (Immutables, BytesN<32>) {
    let hashlock = sha256_bytes32(env, secret);
    (
        Immutables {
            hashlock: hashlock.clone(),
            maker: maker.clone(),
            taker: taker.clone(),
            token: token_addr.clone(),
            amount,
            cancellation_timestamp: cancel_ts,
        },
        hashlock,
    )
}

fn as_bytesn32(env: &Env, fill: u8) -> BytesN<32> {
    BytesN::from_array(env, &[fill; 32])
}

#[test]
fn deploy_and_initialize_works() {
    let env = Env::default();

    // Time zero
    env.ledger().with_mut(|li| {
        li.timestamp = 10_000;
    });

    // Accounts and token
    let (admin, maker, taker) = create_accounts(&env);
    let (token, _token_admin, token_addr) = create_token_contract(&env, &admin);

    // Register factory
    let factory_id = env.register_contract_wasm(None, factory::WASM);
    let factory = factory::Client::new(&env, &factory_id);

    // Upload escrow WASM and initialize factory
    let escrow_wasm_hash = env.deployer().upload_contract_wasm(escrow::WASM);
    factory.initialize(&admin, &escrow_wasm_hash);

    // Build immutables (secret -> hashlock)
    let secret = [7u8; 32];
    let (immutables, _hashlock) =
        build_immutables(&env, &token_addr, &maker, &taker, 1_000, 15_000, &secret);

    // Salt for deterministic address
    let salt = as_bytesn32(&env, 1);

    // Deploy escrow via factory (new factory returns Address of new escrow)
    let escrow_addr = factory.deploy_escrow(
        &factory::Immutables {
            hashlock: immutables.hashlock.clone(),
            maker: immutables.maker.clone(),
            taker: immutables.taker.clone(),
            token: immutables.token.clone(),
            amount: immutables.amount,
            cancellation_timestamp: immutables.cancellation_timestamp,
        },
        &salt,
    );

    // Escrow client (imported or in-crate)
    let escrow = escrow::Client::new(&env, &escrow_addr);

    // Sanity: escrow was deployed, not equal to factory address
    assert_ne!(escrow_addr, factory_id);

    // (Optional) assert initialized flag/immutables if your escrow exposes getters
    // e.g., let got = escrow.get_immutables(); assert_eq!(got.amount, 1_000);
    // Otherwise, mint and check flows in the next tests.
    // Just verify zero balance initially.
    assert_eq!(token.balance(&escrow_addr), 0);
}

#[test]
fn withdraw_before_deadline_works() {
    let env = Env::default();
    env.mock_all_auths();
    
    env.ledger().with_mut(|li| {
        li.timestamp = 12_000; // before cancel window
    });

    let (admin, maker, taker) = create_accounts(&env);
    let (token, token_admin, token_addr) = create_token_contract(&env, &admin);

    let factory_id = env.register_contract_wasm(None, factory::WASM);
    let factory = factory::Client::new(&env, &factory_id);

    // Upload escrow WASM and initialize factory
    let escrow_wasm_hash = env.deployer().upload_contract_wasm(escrow::WASM);
    factory.initialize(&admin, &escrow_wasm_hash);

    let secret = [9u8; 32];
    let (immutables, _hashlock) =
        build_immutables(&env, &token_addr, &maker, &taker, 1_000, 20_000, &secret);

    let salt = as_bytesn32(&env, 2);
    let escrow_addr = factory.deploy_escrow(
        &factory::Immutables {
            hashlock: immutables.hashlock.clone(),
            maker: immutables.maker.clone(),
            taker: immutables.taker.clone(),
            token: immutables.token.clone(),
            amount: immutables.amount,
            cancellation_timestamp: immutables.cancellation_timestamp,
        },
        &salt,
    );

    // fund escrow with tokens
    token_admin.mint(&escrow_addr, &immutables.amount);
    assert_eq!(token.balance(&escrow_addr), 1_000);

    // taker withdraws by providing secret (must be authorized as taker)
    let escrow = escrow::Client::new(&env, &escrow_addr);
    let secret_bn = BytesN::from_array(&env, &secret);

    escrow.withdraw(&secret_bn);

    assert_eq!(token.balance(&escrow_addr), 0);
    assert_eq!(token.balance(&taker), 1_000);
}

#[test]
fn cancel_after_deadline_refunds_maker() {
    let env = Env::default();
    env.mock_all_auths();
    
    env.ledger().with_mut(|li| {
        li.timestamp = 14_000;
    });

    let (admin, maker, taker) = create_accounts(&env);
    let (token, token_admin, token_addr) = create_token_contract(&env, &admin);

    let factory_id = env.register_contract_wasm(None, factory::WASM);
    let factory = factory::Client::new(&env, &factory_id);

    // Upload escrow WASM and initialize factory
    let escrow_wasm_hash = env.deployer().upload_contract_wasm(escrow::WASM);
    factory.initialize(&admin, &escrow_wasm_hash);

    let secret = [5u8; 32];
    let (immutables, _hashlock) =
        build_immutables(&env, &token_addr, &maker, &taker, 1_000, 15_000, &secret);

    let salt = as_bytesn32(&env, 3);
    let escrow_addr = factory.deploy_escrow(
        &factory::Immutables {
            hashlock: immutables.hashlock.clone(),
            maker: immutables.maker.clone(),
            taker: immutables.taker.clone(),
            token: immutables.token.clone(),
            amount: immutables.amount,
            cancellation_timestamp: immutables.cancellation_timestamp,
        },
        &salt,
    );

    // fund escrow
    token_admin.mint(&escrow_addr, &immutables.amount);
    assert_eq!(token.balance(&escrow_addr), 1_000);

    // advance time beyond cancellation timestamp
    env.ledger().with_mut(|li| {
        li.timestamp = 16_000;
    });

    // maker cancels -> refund to maker
    let escrow = escrow::Client::new(&env, &escrow_addr);

    // If your escrow method is named `refund()`, replace `.cancel()` with `.refund()`.
    escrow.cancel();

    assert_eq!(token.balance(&maker), 1_000);
    assert_eq!(token.balance(&escrow_addr), 0);
}
