import { useAccount, useReadContract } from 'wagmi'
import { formatUnits } from 'viem'
import { useNow } from '../hooks/useNow'
import { asBigInt, formatDateTime, formatDuration } from '../lib/utils'
import {
  STAKING_REWARDS_ABI,
  STAKING_REWARDS_ADDRESS,
  STAKING_TOKEN_ABI,
  STAKING_TOKEN_ADDRESS,
  TOKEN_DECIMALS,
} from '../config'

export function UserPanel() {
  const { address } = useAccount()
  const now = useNow()

  const balance = useReadContract({
    abi: STAKING_TOKEN_ABI,
    address: STAKING_TOKEN_ADDRESS,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  })

  const staked = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'balances',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  })

  const earned = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'earned',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address), refetchInterval: 5000 },
  })

  const lockupEnd = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'lockupEndOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  })

  const balanceValue = asBigInt(balance.data)
  const stakedValue = asBigInt(staked.data)
  const earnedValue = asBigInt(earned.data)
  const lockupEndValue = asBigInt(lockupEnd.data)

  const balanceFormatted = balanceValue !== undefined ? formatUnits(balanceValue, TOKEN_DECIMALS) : '0'
  const stakedFormatted = stakedValue !== undefined ? formatUnits(stakedValue, TOKEN_DECIMALS) : '0'
  const earnedFormatted = earnedValue !== undefined ? formatUnits(earnedValue, TOKEN_DECIMALS) : '0'

  const lockupEndMs = lockupEndValue !== undefined && lockupEndValue > 0n ? Number(lockupEndValue) * 1000 : null
  const lockupActive = lockupEndMs !== null && lockupEndMs > now

  let lockupLabel = '—'
  let lockupHint: string | undefined

  if (lockupEndMs !== null) {
    if (lockupActive) {
      const remaining = Math.floor((lockupEndMs - now) / 1000)
      lockupLabel = `Locked until ${formatDateTime(lockupEndValue)}`
      lockupHint = `${formatDuration(remaining)} remaining`
    } else {
      lockupLabel = 'Lockup ended'
    }
  }

  return (
    <section className="card">
      <h2 className="card-title">Your Position</h2>
      <div className="stat-grid">
        <div className="stat">
          <span className="stat-label">Wallet Balance</span>
          <span className="stat-value">{balanceFormatted} STK</span>
        </div>
        <div className="stat">
          <span className="stat-label">Staked</span>
          <span className="stat-value">{stakedFormatted} STK</span>
        </div>
        <div className="stat">
          <span className="stat-label">Earned Rewards</span>
          <span className="stat-value stat-accent">{earnedFormatted} STK</span>
          <span className="stat-hint">Auto-refreshing every 5s</span>
        </div>
        <div className={`stat ${lockupActive ? 'stat-locked' : ''}`}>
          <span className="stat-label">
            {lockupActive && <span className="lock-icon" title="Locked">🔒</span>}
            Lockup Status
          </span>
          <span className="stat-value">{lockupLabel}</span>
          {lockupHint && <span className="stat-hint">{lockupHint}</span>}
        </div>
      </div>
    </section>
  )
}
