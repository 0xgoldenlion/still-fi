import {exec, spawn} from 'child_process'
import {promisify} from 'util'
import * as path from 'path'
import {config} from './config'
import { fileURLToPath } from 'url'

const execAsync = promisify(exec)

export interface StellarExecutionResult {
    success: boolean
    stdout: string
    stderr: string
    contractAddress?: string
    transactionHash?: string
    balance?: string
}

export class StellarCLI {
    private readonly scriptsPath: string
    private readonly network: string
    private readonly sourceKey: string

    constructor() {
        const __filename = fileURLToPath(import.meta.url)
        const __dirname = path.dirname(__filename)
        this.scriptsPath = path.join(__dirname, '../scripts')
        this.network = config.stellar.network
        this.sourceKey = config.stellar.sourceKey
    }

    /**
     * Execute a shell script with environment variables
     */
    private async executeScript(
        scriptName: string,
        args: string[] = [],
        env: Record<string, string> = {}
    ): Promise<StellarExecutionResult> {
        const scriptPath = path.join(this.scriptsPath, scriptName)
        const command = `${scriptPath} ${args.join(' ')}`

        const environment = {
            ...process.env,
            SOURCE_KEY: this.sourceKey,
            NETWORK: this.network,
            ...env
        }

        try {
            console.log(`[Stellar CLI] Executing: ${command}`)
            const {stdout, stderr} = await execAsync(command, {
                env: environment,
                cwd: this.scriptsPath,
                timeout: 60000 // 60 second timeout
            })

            console.log(`[Stellar CLI] stdout: ${stdout}`)
            if (stderr) {
                console.log(`[Stellar CLI] stderr: ${stderr}`)
            }

            return {
                success: true,
                stdout,
                stderr,
                contractAddress: this.parseContractAddress(stdout),
                transactionHash: this.parseTransactionHash(stdout),
                balance: this.parseBalance(stdout)
            }
        } catch (error: any) {
            console.error(`[Stellar CLI] Error executing ${scriptName}:`, error.message)
            return {
                success: false,
                stdout: error.stdout || '',
                stderr: error.stderr || error.message,
            }
        }
    }

    /**
     * Parse contract address from script output
     */
    private parseContractAddress(output: string): string | undefined {
        // Look for contract addresses in various formats
        const patterns = [
            /"(C[0-9A-Z]{55,60})"/,  // Quoted contract ID
            /Contract.*?(C[0-9A-Z]{55,60})/,  // Contract ... C...
            /Address:\s*(C[0-9A-Z]{55,60})/,  // Address: C...
            /deployed:\s*(C[0-9A-Z]{55,60})/i,  // deployed: C...
        ]

        for (const pattern of patterns) {
            const match = output.match(pattern)
            if (match && match[1]) {
                return match[1]
            }
        }

        // Fallback: find any contract ID that's not a known factory
        const contractIds = output.match(/C[0-9A-Z]{55,60}/g)
        if (contractIds) {
            const knownFactories = [ config.stellar.escrowFactory]
            const newContract = contractIds.find(id => !knownFactories.includes(id))
            if (newContract) {
                return newContract
            }
        }

        return undefined
    }

    /**
     * Parse transaction hash from script output
     */
    private parseTransactionHash(output: string): string | undefined {
        const match = output.match(/transaction:\s*([a-f0-9]{64})/i) ||
                     output.match(/tx\s*([a-f0-9]{64})/i) ||
                     output.match(/hash:\s*([a-f0-9]{64})/i)
        return match ? match[1] : undefined
    }

    /**
     * Parse balance from script output
     */
    private parseBalance(output: string): string | undefined {
        const match = output.match(/balance[:\s]+([0-9]+)/i) ||
                     output.match(/amount[:\s]+([0-9]+)/i)
        return match ? match[1] : undefined
    }

    /**
     * Deploy escrow contract using parameterized script
     */
    async deployEscrow(params: {
        hashlock: string
        maker: string
        taker: string
        token: string
        amount: string
        cancellationTimestamp: number
        salt?: string
    }): Promise<StellarExecutionResult> {
        const args = [
            params.hashlock,
            params.maker,
            params.taker,
            params.token,
            params.amount,
            params.cancellationTimestamp.toString()
        ]
        
        // Add salt if provided
        if (params.salt) {
            args.push(params.salt)
        }

        return this.executeScript('deploy_escrow_parameterized.sh', args)
    }

    /**
     * Fund escrow contract
     */
    async fundEscrow(escrowAddress: string, makerAddress: string, amount: string, tokenAddress: string): Promise<StellarExecutionResult> {
        return this.executeScript('interact_escrow.sh', [
            'fund',
            escrowAddress,
            makerAddress,
            amount,
            tokenAddress
        ])
    }

    /**
     * Withdraw from escrow
     */
    async withdrawFromEscrow(escrowAddress: string, secret: string): Promise<StellarExecutionResult> {
        return this.executeScript('interact_escrow.sh', [
            'withdraw',
            escrowAddress,
            secret
        ])
    }

    /**
     * Cancel escrow
     */
    async cancelEscrow(escrowAddress: string): Promise<StellarExecutionResult> {
        return this.executeScript('interact_escrow.sh', [
            'cancel',
            escrowAddress
        ])
    }

    /**
     * Get escrow info
     */
    async getEscrowInfo(escrowAddress: string): Promise<StellarExecutionResult> {
        return this.executeScript('interact_escrow.sh', [
            'info',
            escrowAddress
        ])
    }

    /**
     * Get token balance for an account
     */
    async getTokenBalance(accountAddress: string, tokenAddress: string): Promise<string> {
        try {
            const command = `stellar contract invoke --id ${tokenAddress} --source ${this.sourceKey} --network ${this.network} -- balance --id ${accountAddress}`
            const {stdout} = await execAsync(command)
            
            // Parse balance from output
            const match = stdout.match(/([0-9]+)/)
            return match ? match[1] : '0'
        } catch (error) {
            console.error(`[Stellar CLI] Error getting balance:`, error)
            return '0'
        }
    }

    /**
     * Create LOP order JSON file on Stellar
     */
    async createLOPOrder(params: {
        lopContract: string
        maker: string
        makerAsset: string
        takerAsset: string
        makingAmount: string
        takingAmount: string
        hashlock?: string
        cancellationTimestamp?: number
        isDutchAuction?: boolean
        auctionStartTime?: number
        auctionEndTime?: number
        takingAmountStart?: string
        takingAmountEnd?: string
    }): Promise<StellarExecutionResult & { orderFile?: string }> {
        // Generate unique order file name
        const timestamp = Date.now()
        const orderFile = `order_${timestamp}.json`
        const orderPath = path.join(this.scriptsPath, orderFile)

        // Create order JSON
        const orderData = {
            salt: Math.floor(Math.random() * 1000000),
            maker: params.maker,
            receiver: params.maker, // Same as maker for simplicity
            maker_asset: params.makerAsset,
            taker_asset: params.takerAsset,
            making_amount: params.makingAmount,
            taking_amount: params.isDutchAuction ? "0" : params.takingAmount,
            maker_traits: params.isDutchAuction ? 1 : 0,
            auction_start_time: params.auctionStartTime || 0,
            auction_end_time: params.auctionEndTime || 0,
            taking_amount_start: params.takingAmountStart || "0",
            taking_amount_end: params.takingAmountEnd || "0"
        }

        try {
            // Write order file
            const fs = await import('fs')
            await fs.promises.writeFile(orderPath, JSON.stringify(orderData, null, 2))
            
            console.log(`[Stellar CLI] Created order file: ${orderFile}`)
            console.log(`[Stellar CLI] Order data:`, JSON.stringify(orderData, null, 2))
            
            return {
                success: true,
                stdout: `Order saved to: ${orderFile}`,
                stderr: '',
                orderFile: orderFile
            }
        } catch (error: any) {
            console.error(`[Stellar CLI] Error creating order file:`, error.message)
            return {
                success: false,
                stdout: '',
                stderr: error.message
            }
        }
    }

    /**
     * Fill LOP order
     */
    async fillLOPOrder(lopContract: string, orderFile: string, takerAddress: string): Promise<StellarExecutionResult> {
        return this.executeScript('interact_lop.sh', [
            'fill-order',
            lopContract,
            orderFile,
            takerAddress
        ])
    }

    /**
     * Get LOP order state
     */
    async getLOPOrderState(lopContract: string, orderFile: string): Promise<StellarExecutionResult> {
        return this.executeScript('interact_lop.sh', [
            'get-order-state',
            lopContract,
            orderFile
        ])
    }

    /**
     * Cancel LOP order
     */
    async cancelLOPOrder(lopContract: string, orderFile: string): Promise<StellarExecutionResult> {
        return this.executeScript('interact_lop.sh', [
            'cancel-order',
            lopContract,
            orderFile
        ])
    }

    /**
     * Withdraw from LOP order using secret (use cancel-order for now)
     */
    async withdrawFromLOP(lopContract: string, orderFile: string, secret: string): Promise<StellarExecutionResult> {
        // For now, use cancel-order since there's no specific withdraw command
        return this.cancelLOPOrder(lopContract, orderFile)
    }

    /**
     * Create Dutch auction on Stellar
     */
    async createDutchAuction(params: {
        lopContract: string
        maker: string
        makerAsset: string
        takerAsset: string
        makingAmount: string
        startPrice: string
        endPrice: string
        duration: number
        hashlock: string
        cancellationTimestamp: number
    }): Promise<StellarExecutionResult & { auctionFile?: string }> {
        const startTime = Math.floor(Date.now() / 1000)
        const endTime = startTime + params.duration

        const result = await this.createLOPOrder({
            lopContract: params.lopContract,
            maker: params.maker,
            makerAsset: params.makerAsset,
            takerAsset: params.takerAsset,
            makingAmount: params.makingAmount,
            takingAmount: "0", // Not used in Dutch auction
            isDutchAuction: true,
            auctionStartTime: startTime,
            auctionEndTime: endTime,
            takingAmountStart: params.startPrice,
            takingAmountEnd: params.endPrice
        })

        // Return with auctionFile instead of orderFile for consistency
        return {
            ...result,
            auctionFile: result.orderFile // Dutch auction file is same as order file
        }
    }

    /**
     * Fill Dutch auction
     */
    async fillDutchAuction(lopContract: string, auctionFile: string, takerAddress: string, price: string): Promise<StellarExecutionResult> {
        // Dutch auction fill is same as LOP order fill
        return this.fillLOPOrder(lopContract, auctionFile, takerAddress)
    }

    /**
     * Get Dutch auction state
     */
    async getDutchAuctionState(lopContract: string, auctionFile: string): Promise<StellarExecutionResult> {
        return this.executeScript('interact_lop.sh', [
            'get-current-price',
            lopContract,
            auctionFile
        ])
    }

    /**
     * Claim from Dutch auction using secret
     */
    async claimDutchAuction(lopContract: string, auctionFile: string, secret: string): Promise<StellarExecutionResult> {
        // Dutch auction claim is same as cancel order
        return this.cancelLOPOrder(lopContract, auctionFile)
    }

    /**
     * Generate random salt
     */
    private generateSalt(): string {
        return Array.from({length: 32}, () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join('')
    }

    /**
     * Generate random secret
     */
    generateSecret(): string {
        // Generate 32 bytes (64 hex characters) to match SDK requirements and shell scripts
        return Array.from({length: 32}, () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join('')
    }

    /**
     * Hash a secret (using the same method as scripts)
     */
    async hashSecret(secret: string): Promise<string> {
        try {
            const command = `printf %s "${secret}" | xxd -r -p | sha256sum | awk '{print $1}'`
            const {stdout} = await execAsync(command)
            return stdout.trim()
        } catch (error) {
            console.error('[Stellar CLI] Error hashing secret:', error)
            throw error
        }
    }
}