import { http, createConfig } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { injected } from 'wagmi/connectors'
import type { Abi } from 'viem'
import stakingTokenAbiJson from './abi/StakingToken.json'
import stakingRewardsAbiJson from './abi/StakingRewards.json'

export const STAKING_TOKEN_ADDRESS = '0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5' as const
export const STAKING_REWARDS_ADDRESS = '0x42A3cFFDAE52Ed302Bb78D14071B386F85EFCfCc' as const

export const TOKEN_DECIMALS = 18
export const CHAIN_ID = sepolia.id
export const CHAIN_NAME = sepolia.name
export const ETHERSCAN_BASE_URL = 'https://sepolia.etherscan.io'

export const STAKING_TOKEN_ABI = stakingTokenAbiJson as unknown as Abi
export const STAKING_REWARDS_ABI = stakingRewardsAbiJson as unknown as Abi

export const wagmiConfig = createConfig({
  chains: [sepolia],
  connectors: [injected()],
  transports: {
    [sepolia.id]: http(),
  },
})

export function etherscanAddressUrl(address: string): string {
  return `${ETHERSCAN_BASE_URL}/address/${address}`
}

export function etherscanTxUrl(hash: string): string {
  return `${ETHERSCAN_BASE_URL}/tx/${hash}`
}

export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}
