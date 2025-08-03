import {z} from 'zod'
import Sdk from '@1inch/cross-chain-sdk'
import * as process from 'node:process'

const bool = z
    .string()
    .transform((v) => v.toLowerCase() === 'true')
    .pipe(z.boolean())

const ConfigSchema = z.object({
    SRC_CHAIN_RPC: z.string().url(),
    DST_CHAIN_RPC: z.string().url(),
    SRC_CHAIN_CREATE_FORK: bool.default('true'),
    DST_CHAIN_CREATE_FORK: bool.default('true'),
    STELLAR_NETWORK: z.string().default('testnet'),
    STELLAR_SOURCE_KEY: z.string().default('lion')
})

const fromEnv = ConfigSchema.parse(process.env)

export const config = {
    chain: {
        source: {
            chainId: Sdk.NetworkEnum.ETHEREUM,
            url: fromEnv.SRC_CHAIN_RPC,
            createFork: fromEnv.SRC_CHAIN_CREATE_FORK,
            limitOrderProtocol: '0x111111125421ca6dc452d289314280a0f8842a65',
            wrappedNative: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
            ownerPrivateKey: '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
            tokens: {
                USDC: {
                    address: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
                    donor: '0xd54F23BE482D9A58676590fCa79c8E43087f92fB'
                }
            }
        },
        destination: {
            chainId: Sdk.NetworkEnum.BINANCE,
            url: fromEnv.DST_CHAIN_RPC,
            createFork: fromEnv.DST_CHAIN_CREATE_FORK,
            limitOrderProtocol: '0x111111125421ca6dc452d289314280a0f8842a65',
            wrappedNative: '0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c',
            ownerPrivateKey: '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
            tokens: {
                USDC: {
                    address: '0x8965349fb649a33a30cbfda057d8ec2c48abe2a2',
                    donor: '0x4188663a85C92EEa35b5AD3AA5cA7CeB237C6fe9'
                }
            }
        }
    },
    stellar: {
        network: fromEnv.STELLAR_NETWORK,
        sourceKey: fromEnv.STELLAR_SOURCE_KEY,
        // Pre-deployed LOP contract address on Stellar testnet
        lopContractAddress: 'CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4',
        escrowFactory: 'CACURHRDVGNUCFSMDWTIF6TABC76LNTAQYSIVDJK34P43OYOGPSGYDSO',
        // Test accounts
        accounts: {
            user: 'GD4XRIZEWF7AI5XT5VOQFCGIZO3IYYJL6AORSUECCXSZTE3OBVWW74LA',
            resolver: 'GD4XRIZEWF7AI5XT5VOQFCGIZO3IYYJL6AORSUECCXSZTE3OBVWW74LA'
        },
        tokens: {
            native: 'CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC', // XLM SAC
            usdc: 'CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA' // USDC on Stellar testnet
        }
    }
} as const

export type ChainConfig = (typeof config.chain)['source' | 'destination']
export type StellarConfig = typeof config.stellar
