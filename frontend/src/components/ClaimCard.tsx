import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import {
  useAccount,
  useReadContract,
  useSimulateContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from 'wagmi'
import { formatUnits, type Hex } from 'viem'
import { asBigInt, getErrorMessage } from '../lib/utils'
import { TxStatus } from './TxStatus'
import {
  STAKING_REWARDS_ABI,
  STAKING_REWARDS_ADDRESS,
  TOKEN_DECIMALS,
} from '../config'

export function ClaimCard() {
  const { address, isConnected } = useAccount()
  const queryClient = useQueryClient()
  const { writeContractAsync } = useWriteContract()

  const [txHash, setTxHash] = useState<Hex>()
  const [error, setError] = useState<string>()

  const earned = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'earned',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address), refetchInterval: 5000 },
  })

  const earnedAmount = asBigInt(earned.data) ?? 0n
  const hasRewards = earnedAmount > 0n

  const simulate = useSimulateContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'claimRewards',
    query: { enabled: isConnected && hasRewards },
  })

  const txReceipt = useWaitForTransactionReceipt({ hash: txHash })

  useEffect(() => {
    if (txReceipt.status === 'success') {
      queryClient.invalidateQueries()
      const id = setTimeout(() => setTxHash(undefined), 8000)
      return () => clearTimeout(id)
    }
  }, [txReceipt.status, queryClient])

  async function handleClaim() {
    setError(undefined)
    try {
      const hash = await writeContractAsync({
        abi: STAKING_REWARDS_ABI,
        address: STAKING_REWARDS_ADDRESS,
        functionName: 'claimRewards',
      })
      setTxHash(hash)
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }

  return (
    <section className="card">
      <h2 className="card-title">Claim Rewards</h2>
      <p className="claim-amount">
        {formatUnits(earnedAmount, TOKEN_DECIMALS)} STK available to claim
      </p>

      <button
        className="btn btn-primary btn-block"
        onClick={handleClaim}
        disabled={!isConnected || !hasRewards || Boolean(txHash)}
      >
        {!isConnected ? 'Connect Wallet' : 'Claim Rewards'}
      </button>

      {simulate.error && <p className="form-error">{getErrorMessage(simulate.error)}</p>}
      {error && <p className="form-error">{error}</p>}
      <TxStatus hash={txHash} receipt={txReceipt.isSuccess ? txReceipt.data : undefined} />
    </section>
  )
}
