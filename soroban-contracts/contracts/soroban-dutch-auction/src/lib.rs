#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, Env,
};

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum Error {
    InvalidTimeRange = 1,
    AuctionNotStarted = 2,
    InvalidAmountRange = 3,
    ArithmeticOverflow = 4,
}

#[contract]
pub struct SorobanDutchAuction;

#[contractimpl]
impl SorobanDutchAuction {
    /// Calculate the current taking amount for a Dutch auction
    /// Linear interpolation between start and end amounts based on time
    pub fn calculate_taking_amount(
        env: Env,
        making_amount: i128,
        taking_amount_start: i128,
        taking_amount_end: i128,
        auction_start_time: u64,
        auction_end_time: u64,
    ) -> Result<i128, Error> {
        // Validate time range
        if auction_end_time <= auction_start_time {
            return Err(Error::InvalidTimeRange);
        }

        // Validate amount range (start should be higher than end for Dutch auction)
        if taking_amount_start <= taking_amount_end {
            return Err(Error::InvalidAmountRange);
        }

        let current_time = env.ledger().timestamp();

        // If auction hasn't started, use start price
        if current_time < auction_start_time {
            return Ok(taking_amount_start);
        }

        // If auction has ended, use end price
        if current_time >= auction_end_time {
            return Ok(taking_amount_end);
        }

        // Calculate current price using linear interpolation
        let time_elapsed = current_time - auction_start_time;
        let total_duration = auction_end_time - auction_start_time;
        let price_difference = taking_amount_start - taking_amount_end;

        // Calculate: taking_amount_start - (price_difference * time_elapsed / total_duration)
        let price_reduction = price_difference
            .checked_mul(time_elapsed as i128)
            .ok_or(Error::ArithmeticOverflow)?
            .checked_div(total_duration as i128)
            .ok_or(Error::ArithmeticOverflow)?;

        let current_taking_amount = taking_amount_start
            .checked_sub(price_reduction)
            .ok_or(Error::ArithmeticOverflow)?;

        Ok(current_taking_amount)
    }

    /// Calculate the current making amount for a Dutch auction
    /// This is typically used when the taker specifies how much they want to pay
    pub fn calculate_making_amount(
        env: Env,
        taking_amount: i128,
        making_amount_start: i128,
        making_amount_end: i128,
        auction_start_time: u64,
        auction_end_time: u64,
    ) -> Result<i128, Error> {
        // Validate time range
        if auction_end_time <= auction_start_time {
            return Err(Error::InvalidTimeRange);
        }

        // Validate amount range (start should be lower than end for making amount in Dutch auction)
        if making_amount_start >= making_amount_end {
            return Err(Error::InvalidAmountRange);
        }

        let current_time = env.ledger().timestamp();

        // If auction hasn't started, use start amount
        if current_time < auction_start_time {
            return Ok(making_amount_start);
        }

        // If auction has ended, use end amount
        if current_time >= auction_end_time {
            return Ok(making_amount_end);
        }

        // Calculate current making amount using linear interpolation
        let time_elapsed = current_time - auction_start_time;
        let total_duration = auction_end_time - auction_start_time;
        let amount_difference = making_amount_end - making_amount_start;

        // Calculate: making_amount_start + (amount_difference * time_elapsed / total_duration)
        let amount_increase = amount_difference
            .checked_mul(time_elapsed as i128)
            .ok_or(Error::ArithmeticOverflow)?
            .checked_div(total_duration as i128)
            .ok_or(Error::ArithmeticOverflow)?;

        let current_making_amount = making_amount_start
            .checked_add(amount_increase)
            .ok_or(Error::ArithmeticOverflow)?;

        Ok(current_making_amount)
    }
}

mod test;