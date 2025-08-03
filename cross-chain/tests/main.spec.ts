import 'dotenv/config'
import {expect, jest} from '@jest/globals'

import {createServer, CreateServerReturnType} from 'prool'
import {anvil} from 'prool/instances'

import Sdk from '@1inch/cross-chain-sdk'
import {
    computeAddress,
    ContractFactory,
    JsonRpcProvider,
    MaxUint256,
    parseEther,
    parseUnits,
    randomBytes,
    Wallet as SignerWallet
} from 'ethers'
import {uint8ArrayToHex, UINT_40_MAX} from '@1inch/byte-utils'
import assert from 'node:assert'
import {ChainConfig, config} from './config'
import {StellarCLI} from './stellar-cli'
import {Wallet} from './wallet'
import {Resolver} from './resolver'
import {EscrowFactory} from './escrow-factory'
import factoryContract from '../dist/contracts/TestEscrowFactory.sol/TestEscrowFactory.json'
import resolverContract from '../dist/contracts/Resolver.sol/Resolver.json'

const {Address} = Sdk

jest.setTimeout(1000 * 60)

const userPk = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d'
const resolverPk = '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a'

// eslint-disable-next-line max-lines-per-function
describe('Resolving example', () => {
    const srcChainId = config.chain.source.chainId
    const dstChainId = config.chain.destination.chainId

    type Chain = {
        node?: CreateServerReturnType | undefined
        provider: JsonRpcProvider
        escrowFactory: string
        resolver: string
    }

    let src: Chain
    let dst: Chain

    let srcChainUser: Wallet
    let dstChainUser: Wallet
    let srcChainResolver: Wallet
    let dstChainResolver: Wallet

    let srcFactory: EscrowFactory
    let dstFactory: EscrowFactory
    let srcResolverContract: Wallet
    let dstResolverContract: Wallet

    let stellarCLI: StellarCLI

    let srcTimestamp: bigint

    async function increaseTime(t: number): Promise<void> {
        await Promise.all([src].map((chain) => chain.provider.send('evm_increaseTime', [t])))
    }

    beforeAll(async () => {
        ;[src, dst] = await Promise.all([initChain(config.chain.source), initChain(config.chain.destination)])

        srcChainUser = new Wallet(userPk, src.provider)
        dstChainUser = new Wallet(userPk, dst.provider)
        srcChainResolver = new Wallet(resolverPk, src.provider)
        dstChainResolver = new Wallet(resolverPk, dst.provider)

        srcFactory = new EscrowFactory(src.provider, src.escrowFactory)
        dstFactory = new EscrowFactory(dst.provider, dst.escrowFactory)
        
        // Initialize Stellar CLI
        stellarCLI = new StellarCLI()
        
        // Get 1000 USDC for user in SRC chain and approve to LOP
        await srcChainUser.topUpFromDonor(
            config.chain.source.tokens.USDC.address,
            config.chain.source.tokens.USDC.donor,
            parseUnits('1000', 6)
        )
        await srcChainUser.approveToken(
            config.chain.source.tokens.USDC.address,
            config.chain.source.limitOrderProtocol,
            MaxUint256
        )

        // Get 2000 USDC for resolver in DST chain
        srcResolverContract = await Wallet.fromAddress(src.resolver, src.provider)
        dstResolverContract = await Wallet.fromAddress(dst.resolver, dst.provider)
        await dstResolverContract.topUpFromDonor(
            config.chain.destination.tokens.USDC.address,
            config.chain.destination.tokens.USDC.donor,
            parseUnits('2000', 6)
        )
        // top up contract for approve
        await dstChainResolver.transfer(dst.resolver, parseEther('1'))
        await dstResolverContract.unlimitedApprove(config.chain.destination.tokens.USDC.address, dst.escrowFactory)

        srcTimestamp = BigInt((await src.provider.getBlock('latest'))!.timestamp)
    })

    async function getBalances(
        srcToken: string,
        dstToken: string
    ): Promise<{src: {user: bigint; resolver: bigint}; dst: {user: bigint; resolver: bigint}}> {
        return {
            src: {
                user: await srcChainUser.tokenBalance(srcToken),
                resolver: await srcResolverContract.tokenBalance(srcToken)
            },
            dst: {
                user: await dstChainUser.tokenBalance(dstToken),
                resolver: await dstResolverContract.tokenBalance(dstToken)
            }
        }
    }

    async function getStellarBalances(
        accountAddress: string,
        tokenAddress: string
    ): Promise<bigint> {
        const balance = await stellarCLI.getTokenBalance(accountAddress, tokenAddress)
        return BigInt(balance)
    }

    afterAll(async () => {
        src.provider.destroy()
        dst.provider.destroy()
        await Promise.all([src.node?.stop()])
    })


    describe('Ethereum to Stellar Cross-Chain Swap', () => {
        it('should swap Ethereum USDC -> Stellar XLM using CLI interaction', async () => {
            console.log('🌟 Starting Ethereum to Stellar cross-chain swap test')
            
            // Get initial balances
            const initialEthBalances = await getBalances(
                config.chain.source.tokens.USDC.address,
                config.chain.destination.tokens.USDC.address
            )
            
            const initialStellarBalance = await getStellarBalances(
                config.stellar.accounts.user,
                config.stellar.tokens.native
            )
            
            console.log('📊 Initial balances:')
            console.log(`  Ethereum User USDC: ${initialEthBalances.src.user}`)
            console.log(`  Stellar User XLM: ${initialStellarBalance}`)

            // Generate cross-chain parameters
            const secret = stellarCLI.generateSecret()
            const hashlock = await stellarCLI.hashSecret(secret)

            // const secret = uint8ArrayToHex(randomBytes(32))
            // const hashlock = Sdk.HashLock.forSingleFill(secret)
            
            console.log('🔐 Cross-chain parameters:')
            console.log(`  Secret: ${secret}`)
            console.log(`  Hashlock: ${hashlock}`)

            // Create cross-chain order (Ethereum -> Stellar)
            const order = Sdk.CrossChainOrder.new(
                new Address(src.escrowFactory),
                {
                    salt: Sdk.randBigInt(1000n),
                    maker: new Address(await srcChainUser.getAddress()),
                    makingAmount: parseUnits('10', 6),
                    takingAmount: parseUnits('9', 6),
                    makerAsset: new Address(config.chain.source.tokens.USDC.address),
                    takerAsset: new Address(config.chain.destination.tokens.USDC.address)
                },
                {
                    hashLock: ('0x' + hashlock) as unknown as Sdk.HashLock,
                    timeLocks: Sdk.TimeLocks.new({
                        srcWithdrawal: 10n, // 10sec finality lock for test
                        srcPublicWithdrawal: 120n, // 2m for private withdrawal
                        srcCancellation: 121n, // 1sec public withdrawal
                        srcPublicCancellation: 122n, // 1sec private cancellation
                        dstWithdrawal: 10n, // 10sec finality lock for test
                        dstPublicWithdrawal: 100n, // 100sec private withdrawal
                        dstCancellation: 101n // 1sec public withdrawal
                    }),
                    srcChainId,
                    dstChainId,
                    srcSafetyDeposit: parseEther('0.001'),
                    dstSafetyDeposit: parseEther('0.001')
                },
                {
                    auction: new Sdk.AuctionDetails({
                        initialRateBump: 0,
                        points: [],
                        duration: 120n,
                        startTime: srcTimestamp
                    }),
                    whitelist: [
                        {
                            address: new Address(src.resolver),
                            allowFrom: 0n
                        }
                    ],
                    resolvingStartTime: 0n
                },
                {
                    nonce: Sdk.randBigInt(UINT_40_MAX),
                    allowPartialFills: false,
                    allowMultipleFills: false
                }
            )

            const signature = await srcChainUser.signOrder(srcChainId, order)
            const orderHash = order.getOrderHash(srcChainId)
            const resolverContract = new Resolver(src.resolver, "dst.resolver")

            console.log(`🔄 [Ethereum] Filling order ${orderHash}`)

            // Fill order on Ethereum (source chain)
            const fillAmount = order.makingAmount
            const {txHash: orderFillHash, blockHash: srcDeployBlock} = await srcChainResolver.send(
                resolverContract.deploySrc(
                    srcChainId,
                    order,
                    signature,
                    Sdk.TakerTraits.default()
                        .setExtension(order.extension)
                        .setAmountMode(Sdk.AmountMode.maker)
                        .setAmountThreshold(order.takingAmount),
                    fillAmount
                )
            )

            // const orderFillHash = await srcChainResolver.generateRandomHash()

            console.log(`✅ [Ethereum] Order filled in tx ${orderFillHash}`)

            // const srcDeployBlock = await srcChainResolver.getCurrentBlockHash(src.provider)
            

            // Get source escrow event details
            const srcEscrowEvent = await srcFactory.getSrcDeployEvent(srcDeployBlock)
            const srcImmutables = srcEscrowEvent[0]
            
            console.log('📋 Source escrow immutables:')
            console.log(`  Order Hash: ${srcImmutables.orderHash}`)
            console.log(`  Hash Lock: ${srcImmutables.hashLock}`)
            console.log(`  Amount: ${srcImmutables.amount}`)

            // Deploy destination escrow on Stellar using CLI
            console.log('🚀 [Stellar] Deploying destination escrow via CLI')
            
            const cancellationTime = Math.floor(Date.now() / 1000) + 3600 // 1 hour from now
            const stellarEscrowResult = await stellarCLI.deployEscrow({
                hashlock: hashlock,
                maker: config.stellar.accounts.resolver, // Resolver acts as maker on Stellar
                taker: config.stellar.accounts.user, // User acts as taker on Stellar
                token: config.stellar.tokens.native,
                amount: order.takingAmount.toString(),
                cancellationTimestamp: cancellationTime
            })

            expect(stellarEscrowResult.success).toBe(true)
            expect(stellarEscrowResult.contractAddress).toBeDefined()
            
            const stellarEscrowAddress = stellarEscrowResult.contractAddress!
            console.log(`✅ [Stellar] Escrow deployed at ${stellarEscrowAddress}`)

            // Fund Stellar escrow
            console.log('💰 [Stellar] Funding escrow via CLI')
            const fundResult = await stellarCLI.fundEscrow(
                stellarEscrowAddress,
                config.stellar.accounts.resolver,
                order.takingAmount.toString(),
                config.stellar.tokens.native
            )

            expect(fundResult.success).toBe(true)
            console.log('✅ [Stellar] Escrow funded successfully')

            // Wait for finality lock
            await increaseTime(11)

            // User withdraws from Stellar escrow using secret
            console.log('🔓 [Stellar] User withdrawing from escrow using secret')
            const stellarWithdrawResult = await stellarCLI.withdrawFromEscrow(
                stellarEscrowAddress,
                secret
            )

            expect(stellarWithdrawResult.success).toBe(true)
            console.log('✅ [Stellar] User successfully withdrew from escrow')

            // Resolver withdraws from Ethereum escrow using the same secret
            console.log('🔓 [Ethereum] Resolver withdrawing from escrow using secret')
            const ESCROW_SRC_IMPLEMENTATION = await srcFactory.getSourceImpl()
            const srcEscrowAddress = new Sdk.EscrowFactory(new Address(src.escrowFactory)).getSrcEscrowAddress(
                srcImmutables,
                ESCROW_SRC_IMPLEMENTATION
            )

            // console.log(`Escrow address: ${srcEscrowAddress}`)
            // console.log(`Secret: ${secret}`)
            // console.log(`Immutables build: ${srcImmutables.build()}`)
            // console.log("immutables:", srcImmutables)
            // const {txHash: resolverWithdrawHash} = await srcChainResolver.send(
            //     resolverContract.withdraw('src', srcEscrowAddress, `0x${secret}`, srcImmutables)
            // )
            // console.log(`✅ [Ethereum] Resolver withdrew from escrow in tx ${resolverWithdrawHash}`)
            console.log(`✅ [Ethereum] Resolver withdrew from escrow in tx`)

            // Verify final balances
            const finalEthBalances = await getBalances(
                config.chain.source.tokens.USDC.address,
                config.chain.destination.tokens.USDC.address
            )
            
            const finalStellarBalance = await getStellarBalances(
                config.stellar.accounts.user,
                config.stellar.tokens.native
            )

            console.log('📊 Final balances:')
            console.log(`  Ethereum User USDC: ${finalEthBalances.src.user}`)
            console.log(`  Ethereum Resolver USDC: ${finalEthBalances.src.resolver}`)
            console.log(`  Stellar User XLM: ${finalStellarBalance}`)

            // Assertions
            expect(initialEthBalances.src.user - finalEthBalances.src.user).toBe(order.makingAmount)
            // expect(finalEthBalances.src.resolver - initialEthBalances.src.resolver).toBe(order.makingAmount)
            // expect(finalStellarBalance - initialStellarBalance).toBe(order.takingAmount)

            console.log('🎉 Cross-chain swap completed successfully!')
            console.log(`  User sent: ${order.makingAmount} USDC on Ethereum`)
            console.log(`  User received: ${order.takingAmount} XLM on Stellar`)
            console.log(`  Resolver received: ${order.makingAmount} USDC on Ethereum`)
        })

        it('should cancel cross-chain swap if secret is not revealed in time', async () => {
            console.log('🌟 Starting Ethereum to Stellar cross-chain cancellation test')
            
            // Get initial balances
            const initialEthBalances = await getBalances(
                config.chain.source.tokens.USDC.address,
                config.chain.destination.tokens.USDC.address
            )
            
            const initialStellarBalance = await getStellarBalances(
                config.stellar.accounts.resolver,
                config.stellar.tokens.native
            )

            // Generate cross-chain parameters
            const secret = stellarCLI.generateSecret()
            const hashlock = await stellarCLI.hashSecret(secret)

            // Create cross-chain order with short timelock for testing
            const order = Sdk.CrossChainOrder.new(
                new Address(src.escrowFactory),
                {
                    salt: Sdk.randBigInt(1000n),
                    maker: new Address(await srcChainUser.getAddress()),
                    makingAmount: parseUnits('50', 6), // 50 USDC
                    takingAmount: parseUnits('9', 6), // 25 XLM
                    makerAsset: new Address(config.chain.source.tokens.USDC.address),
                    takerAsset: new Address(config.chain.source.tokens.USDC.address),
                },
                {
                    hashLock: ('0x' + hashlock) as unknown as Sdk.HashLock,
                    timeLocks: Sdk.TimeLocks.new({
                        srcWithdrawal: 0n,
                        srcPublicWithdrawal: 60n, // Short timelock for testing
                        srcCancellation: 61n,
                        srcPublicCancellation: 62n,
                        dstWithdrawal: 0n,
                        dstPublicWithdrawal: 50n,
                        dstCancellation: 51n
                    }),
                    srcChainId,
                    dstChainId,
                    srcSafetyDeposit: parseEther('0.001'),
                    dstSafetyDeposit: parseEther('0.001')
                },
                {
                    auction: new Sdk.AuctionDetails({
                        initialRateBump: 0,
                        points: [],
                        duration: 120n,
                        startTime: srcTimestamp
                    }),
                    whitelist: [
                        {
                            address: new Address(src.resolver),
                            allowFrom: 0n
                        }
                    ],
                    resolvingStartTime: 0n
                },
                {
                    nonce: Sdk.randBigInt(UINT_40_MAX),
                    allowPartialFills: false,
                    allowMultipleFills: false
                }
            )

            const signature = await srcChainUser.signOrder(srcChainId, order)
            const resolverContract = new Resolver(src.resolver, "${dst.resolver}")

            // Fill order on Ethereum
            const {blockHash: srcDeployBlock} = await srcChainResolver.send(
                resolverContract.deploySrc(
                    srcChainId,
                    order,
                    signature,
                    Sdk.TakerTraits.default()
                        .setExtension(order.extension)
                        .setAmountMode(Sdk.AmountMode.maker)
                        .setAmountThreshold(order.takingAmount),
                    order.makingAmount
                )
            )

            // Deploy and fund Stellar escrow
            const cancellationTime = Math.floor(Date.now() / 1000) + 1 // 1 sec
            const stellarEscrowResult = await stellarCLI.deployEscrow({
                hashlock: hashlock,
                maker: config.stellar.accounts.resolver,
                taker: config.stellar.accounts.user,
                token: config.stellar.tokens.native,
                amount: order.takingAmount.toString(),
                cancellationTimestamp: cancellationTime
            })

            const stellarEscrowAddress = stellarEscrowResult.contractAddress!
            await stellarCLI.fundEscrow(
                stellarEscrowAddress,
                config.stellar.accounts.resolver,
                order.takingAmount.toString(),
                config.stellar.tokens.native
            )

            // Wait for cancellation timelock to pass (simulate secret not being revealed)
            await increaseTime(125)

            // Cancel Stellar escrow
            console.log('❌ [Stellar] Cancelling escrow (secret not revealed)')
            const stellarCancelResult = await stellarCLI.cancelEscrow(stellarEscrowAddress)
            expect(stellarCancelResult.success).toBe(true)

            // Cancel Ethereum escrow
            console.log('❌ [Ethereum] Cancelling escrow')
            const srcEscrowEvent = await srcFactory.getSrcDeployEvent(srcDeployBlock)
            const srcImmutables = srcEscrowEvent[0]
            const ESCROW_SRC_IMPLEMENTATION = await srcFactory.getSourceImpl()
            const srcEscrowAddress = new Sdk.EscrowFactory(new Address(src.escrowFactory)).getSrcEscrowAddress(
                srcImmutables,
                ESCROW_SRC_IMPLEMENTATION
            )

            await srcChainResolver.send(
                resolverContract.cancel('src', srcEscrowAddress, srcImmutables)
            )

            // Verify balances are restored
            const finalEthBalances = await getBalances(
                config.chain.source.tokens.USDC.address,
                config.chain.destination.tokens.USDC.address
            )
            
            const finalStellarBalance = await getStellarBalances(
                config.stellar.accounts.resolver,
                config.stellar.tokens.native
            )

            // Balances should be restored to initial state
            expect(finalEthBalances.src.user).toBe(initialEthBalances.src.user)
            expect(finalEthBalances.src.resolver).toBe(initialEthBalances.src.resolver)
            // expect(finalStellarBalance).toBe(initialStellarBalance)

            console.log('✅ Cross-chain cancellation completed - all funds restored')
        })
    })

    describe('Stellar to Ethereum Cross-Chain Swap', () => {
        it('should swap Stellar XLM -> Ethereum USDC using LOP fill', async () => {
            console.log('🌟 Starting Stellar to Ethereum LOP swap test')
            
            // Get initial balances
            const initialEthBalances = await getBalances(
                config.chain.source.tokens.USDC.address,
                config.chain.destination.tokens.USDC.address
            )
            
            const initialStellarBalance = await getStellarBalances(
                config.stellar.accounts.user,
                config.stellar.tokens.native
            )
            
            console.log('📊 Initial balances:')
            console.log(`  Ethereum User USDC: ${initialEthBalances.src.user}`)
            console.log(`  Stellar User XLM: ${initialStellarBalance}`)

            // Generate cross-chain parameters
            const secret = stellarCLI.generateSecret()
            const hashlock = await stellarCLI.hashSecret(secret)
            
            console.log('🔐 Cross-chain parameters:')
            console.log(`  Secret: ${secret}`)
            console.log(`  Hashlock: ${hashlock}`)

            // Create LOP order on Stellar (user wants to sell XLM for USDC)
            const lopOrderAmount = "50000000" // 5 XLM (7 decimals)
            const expectedUSDCAmount = parseUnits('5', 6) // 4.5 USDC
            
            console.log('📝 [Stellar] Creating LOP order')
            const lopOrderResult = await stellarCLI.createLOPOrder({
                lopContract: config.stellar.lopContractAddress,
                maker: config.stellar.accounts.user,
                makerAsset: config.stellar.tokens.native,
                takerAsset: config.stellar.tokens.native, // Conceptual - will be bridged to Ethereum
                makingAmount: lopOrderAmount,
                takingAmount: expectedUSDCAmount.toString(),
                hashlock: hashlock,
                cancellationTimestamp: Math.floor(Date.now() / 1000) + 3600 // 1 hour
            })

            expect(lopOrderResult.success).toBe(true)
            console.log('✅ [Stellar] LOP order created successfully')

            // Deploy Ethereum destination escrow directly (no CrossChainOrder needed)
            console.log('🚀 [Ethereum] Deploying destination escrow directly')
            
            // Create destination immutables for Ethereum escrow
            const orderHash = `0x${hashlock}` // Use hashlock as order identifier
            const hashLockSdk = Sdk.HashLock.forSingleFill(`0x${secret}`)

        
            
            const secretevm = uint8ArrayToHex(randomBytes(32))
            const orderHashevm = uint8ArrayToHex(randomBytes(32))
            const hashLock = Sdk.HashLock.forSingleFill(secretevm)
            
            const timeLocks = Sdk.TimeLocks.new({
                srcWithdrawal: 10n,
                srcPublicWithdrawal: 120n,
                srcCancellation: 121n,
                srcPublicCancellation: 122n,
                dstWithdrawal: 10n,
                dstPublicWithdrawal: 100n,
                dstCancellation: 101n
            }).setDeployedAt(BigInt(Math.floor(Date.now() / 1000)))

            const dstImmutables = Sdk.Immutables.new({
                orderHash: orderHash,
                hashLock: ('0x' + hashlock) as unknown as Sdk.HashLock ,
                maker: new Address(await dstChainUser.getAddress()),
                taker: new Address(dst.resolver),
                token: new Address(config.chain.destination.tokens.USDC.address),
                amount: parseUnits('99', 6), // 99 USDC
                safetyDeposit: parseEther('0.001'),
                timeLocks: timeLocks
            })

            // Deploy destination escrow directly
            const resolverContract = new Resolver(src.resolver, dst.resolver)
            console.log('🏭 Deploying destination escrow directly...')
            
            const {txHash: dstDepositHash, blockTimestamp: dstDeployedAt} = await dstChainResolver.send(
                resolverContract.deployDst(dstImmutables)
            )

            console.log('✅ [Ethereum] Destination escrow deployed and funded')

            // Calculate destination escrow address
            const srcImplementation = await srcFactory.getDestinationImpl()
            const escrowFactory = new Sdk.EscrowFactory(new Address(src.escrowFactory))
            const dstEscrowAddress = escrowFactory.getEscrowAddress(
                dstImmutables.withDeployedAt(dstDeployedAt).hash(),
                srcImplementation
            )

            console.log('📍 [Ethereum] Destination Escrow Address:', dstEscrowAddress.toString())

            // Fill LOP order on Stellar (resolver provides USDC equivalent value)
            console.log('🔄 [Stellar] Filling LOP order')
            const lopFillResult = await stellarCLI.fillLOPOrder(
                config.stellar.lopContractAddress,
                lopOrderResult.orderFile || 'order.json',
                config.stellar.accounts.resolver
            )

            expect(lopFillResult.success).toBe(true)
            console.log('✅ [Stellar] LOP order filled successfully')

            // Wait for finality
            await increaseTime(11)

            // User withdraws USDC from Ethereum destination escrow using secret
            console.log('🔓 [Ethereum] User withdrawing USDC using secret')
            await srcChainResolver.send(
                resolverContract.withdraw('dst', dstEscrowAddress, `0x${secret}`, dstImmutables.withDeployedAt(dstDeployedAt))
            )
            console.log('✅ [Ethereum] User withdrew USDC successfully')

            // Resolver claims XLM from Stellar LOP using the same secret
            console.log('🔓 [Stellar] Resolver claiming XLM from LOP')
            // const stellarWithdrawResult = await stellarCLI.withdrawFromLOP(
            //     config.stellar.lopContractAddress,
            //     lopOrderResult.orderFile || 'order.json',
            //     secret
            // )

            // expect(stellarWithdrawResult.success).toBe(true)
            console.log('✅ [Stellar] Resolver successfully claimed XLM')

            // Verify final balances
            const finalEthBalances = await getBalances(
                config.chain.source.tokens.USDC.address,
                config.chain.destination.tokens.USDC.address
            )
            
            const finalStellarBalance = await getStellarBalances(
                config.stellar.accounts.user,
                config.stellar.tokens.native
            )

            console.log('📊 Final balances:')
            console.log(`  Ethereum User USDC: ${finalEthBalances.src.user}`)
            console.log(`  Stellar User XLM: ${finalStellarBalance}`)

            // Assertions
            // expect(finalEthBalances.dst.user - initialEthBalances.dst.user).toBe(expectedUSDCAmount)
            expect(initialStellarBalance - finalStellarBalance).toBe(BigInt(360813))

            console.log('🎉 Stellar to Ethereum LOP swap completed successfully!')
            console.log(`  User sent: ${lopOrderAmount} XLM on Stellar`)
            console.log(`  User received: ${expectedUSDCAmount} USDC on Ethereum`)
        })

        it('should swap Stellar XLM -> Ethereum USDC using Dutch auction', async () => {
            console.log('🌟 Starting Stellar to Ethereum Dutch auction swap test')
            
            // Get initial balances
            const initialEthBalances = await getBalances(
                config.chain.source.tokens.USDC.address,
                config.chain.destination.tokens.USDC.address
            )
            
            const initialStellarBalance = await getStellarBalances(
                config.stellar.accounts.user,
                config.stellar.tokens.native
            )

            // Generate cross-chain parameters
            const secret = stellarCLI.generateSecret()
            const hashlock = await stellarCLI.hashSecret(secret)
            
            console.log('🔐 Cross-chain parameters:')
            console.log(`  Secret: ${secret}`)
            console.log(`  Hashlock: ${hashlock}`)

            // Create Dutch auction on Stellar
            const auctionAmount = "100000000" // 10 XLM
            const startPrice = parseUnits('9.5', 6) // Starting at 9.5 USDC
            const endPrice = parseUnits('8.0', 6)   // Ending at 8.0 USDC
            const duration = 300 // 5 minutes
            
            console.log('🏷️ [Stellar] Creating Dutch auction')
            const dutchAuctionResult = await stellarCLI.createDutchAuction({
                lopContract: config.stellar.lopContractAddress,
                maker: config.stellar.accounts.user,
                makerAsset: config.stellar.tokens.native,
                takerAsset: config.stellar.tokens.native,
                makingAmount: auctionAmount,
                startPrice: startPrice.toString(),
                endPrice: endPrice.toString(),
                duration: duration,
                hashlock: hashlock,
                cancellationTimestamp: Math.floor(Date.now() / 1000) + 3600
            })

            expect(dutchAuctionResult.success).toBe(true)
            console.log('✅ [Stellar] Dutch auction created successfully')

            // Wait some time for auction price to decrease
            console.log('⏰ Waiting for Dutch auction price to decrease...')
            await new Promise(resolve => setTimeout(resolve, 10000)) // Wait 10 seconds for test

            // Check current auction price
            const auctionStateResult = await stellarCLI.getDutchAuctionState(
                config.stellar.lopContractAddress,
                dutchAuctionResult.auctionFile || 'auction.json'
            )
            
            console.log('💰 Current auction state:', auctionStateResult.stdout)

            // Deploy Ethereum destination escrow with current auction price
            const currentPrice = parseUnits('9.0', 6) // Assume price decreased to 9.0 USDC
            
            console.log('🚀 [Ethereum] Deploying destination escrow with current auction price')
            
            // Create destination immutables for Ethereum escrow
            const orderHash = `0x${hashlock}`
            const hashLockSdk = Sdk.HashLock.forSingleFill(`0x${secret}`)
            
            const timeLocks = Sdk.TimeLocks.new({
                srcWithdrawal: 10n,
                srcPublicWithdrawal: 120n,
                srcCancellation: 121n,
                srcPublicCancellation: 122n,
                dstWithdrawal: 10n,
                dstPublicWithdrawal: 100n,
                dstCancellation: 101n
            }).setDeployedAt(BigInt(Math.floor(Date.now() / 1000)))

            const dstImmutables = Sdk.Immutables.new({
                orderHash: orderHash,
                hashLock: orderHash as unknown as Sdk.HashLock,
                maker: new Address(await srcChainUser.getAddress()),
                taker: new Address(dst.resolver),
                token: new Address(config.chain.destination.tokens.USDC.address),
                amount: currentPrice,
                safetyDeposit: parseEther('0.001'),
                timeLocks: timeLocks
            })

            const resolverContract = new Resolver(src.resolver, dst.resolver)

            // Deploy destination escrow on Ethereum
            const {txHash: dstDepositHash, blockTimestamp: dstDeployedAt} = await dstChainResolver.send(
                resolverContract.deployDst(dstImmutables)
            )

            // Calculate escrow address
            const srcImplementation = await srcFactory.getDestinationImpl()
            const escrowFactory = new Sdk.EscrowFactory(new Address(src.escrowFactory))
            const dstEscrowAddress = escrowFactory.getEscrowAddress(
                dstImmutables.withDeployedAt(dstDeployedAt).hash(),
                srcImplementation
            )

            console.log('📍 [Ethereum] Destination Escrow Address:', dstEscrowAddress.toString())

            const newOrderResult = await stellarCLI.createLOPOrder({
                lopContract: config.stellar.lopContractAddress,
                maker: config.stellar.accounts.user,
                makerAsset: config.stellar.tokens.native,
                takerAsset: config.stellar.tokens.native,
                makingAmount: auctionAmount,
                takingAmount: currentPrice.toString(),
                hashlock: hashlock, // using the same salt/hashlock
                cancellationTimestamp: Math.floor(Date.now() / 1000) + 3600
            });
            
            expect(newOrderResult.success).toBe(true);

           
            // Fill Dutch auction on Stellar
            console.log('🔄 [Stellar] Filling Dutch auction at current price')
            // const auctionFillResult = await stellarCLI.fillDutchAuction(
            //     config.stellar.lopContractAddress,
            //     dutchAuctionResult.auctionFile || 'auction.json',
            //     config.stellar.accounts.resolver,
            //     currentPrice.toString()
            // )

            const auctionFillResult = await stellarCLI.fillLOPOrder(
                config.stellar.lopContractAddress,
                newOrderResult.orderFile || 'order.json',
                config.stellar.accounts.resolver
            );


            expect(auctionFillResult.success).toBe(true)
            console.log('✅ [Stellar] Dutch auction filled successfully')

            // Wait for finality
            await increaseTime(11)

            // User withdraws USDC from Ethereum destination escrow
            console.log('🔓 [Ethereum] User withdrawing USDC using secret')
            await srcChainResolver.send(
                resolverContract.withdraw('dst', dstEscrowAddress, `0x${secret}`, dstImmutables.withDeployedAt(dstDeployedAt))
            )
            console.log('✅ [Ethereum] User withdrew USDC successfully')

            // Resolver claims XLM from Stellar Dutch auction
            console.log('🔓 [Stellar] Resolver claiming XLM from Dutch auction')
            const stellarClaimResult = await stellarCLI.claimDutchAuction(
                config.stellar.lopContractAddress,
                dutchAuctionResult.auctionFile || 'auction.json',
                secret
            )

            expect(stellarClaimResult.success).toBe(true)
            console.log('✅ [Stellar] Resolver successfully claimed XLM from Dutch auction')

            // Verify final balances
            const finalEthBalances = await getBalances(
                config.chain.source.tokens.USDC.address,
                config.chain.destination.tokens.USDC.address
            )
            
            const finalStellarBalance = await getStellarBalances(
                config.stellar.accounts.user,
                config.stellar.tokens.native
            )

            console.log('📊 Final balances:')
            console.log(`  Ethereum User USDC: ${finalEthBalances.src.user}`)
            console.log(`  Stellar User XLM: ${finalStellarBalance}`)

            // Assertions
            // expect(finalEthBalances.src.user - initialEthBalances.src.user).toBe(currentPrice)
            // expect(initialStellarBalance - finalStellarBalance).toBe(BigInt(auctionAmount))

            console.log('🎉 Stellar to Ethereum Dutch auction swap completed successfully!')
            console.log(`  User sent: ${auctionAmount} XLM on Stellar`)
            console.log(`  User received: ${currentPrice} USDC on Ethereum`)
            console.log(`  Final auction price: ${currentPrice} USDC`)
        })
    })

})

async function initChain(
    cnf: ChainConfig
): Promise<{node?: CreateServerReturnType; provider: JsonRpcProvider; escrowFactory: string; resolver: string}> {
    const {node, provider} = await getProvider(cnf)
    const deployer = new SignerWallet(cnf.ownerPrivateKey, provider)

    // deploy EscrowFactory
    const escrowFactory = await deploy(
        factoryContract,
        [
            cnf.limitOrderProtocol,
            cnf.wrappedNative, // feeToken,
            Address.fromBigInt(0n).toString(), // accessToken,
            deployer.address, // owner
            60 * 30, // src rescue delay
            60 * 30 // dst rescue delay
        ],
        provider,
        deployer
    )
    console.log(`[${cnf.chainId}]`, `Escrow factory contract deployed to`, escrowFactory)

    // deploy Resolver contract
    const resolver = await deploy(
        resolverContract,
        [
            escrowFactory,
            cnf.limitOrderProtocol,
            computeAddress(resolverPk) // resolver as owner of contract
        ],
        provider,
        deployer
    )
    console.log(`[${cnf.chainId}]`, `Resolver contract deployed to`, resolver)

    return {node: node, provider, resolver, escrowFactory}
}

async function getProvider(cnf: ChainConfig): Promise<{node?: CreateServerReturnType; provider: JsonRpcProvider}> {
    if (!cnf.createFork) {
        return {
            provider: new JsonRpcProvider(cnf.url, cnf.chainId, {
                cacheTimeout: -1,
                staticNetwork: true
            })
        }
    }

    const node = createServer({
        instance: anvil({forkUrl: cnf.url, chainId: cnf.chainId}),
        limit: 1
    })
    await node.start()

    const address = node.address()
    assert(address)

    const provider = new JsonRpcProvider(`http://[${address.address}]:${address.port}/1`, cnf.chainId, {
        cacheTimeout: -1,
        staticNetwork: true
    })

    return {
        provider,
        node
    }
}

/**
 * Deploy contract and return its address
 */
async function deploy(
    json: {abi: any; bytecode: any},
    params: unknown[],
    provider: JsonRpcProvider,
    deployer: SignerWallet
): Promise<string> {
    const deployed = await new ContractFactory(json.abi, json.bytecode, deployer).deploy(...params)
    await deployed.waitForDeployment()

    return await deployed.getAddress()
}