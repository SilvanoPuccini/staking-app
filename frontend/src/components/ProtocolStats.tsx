import { useState } from 'react'
import { useReadContract } from 'wagmi'
import { formatUnits } from 'viem'
import { useNow } from '../hooks/useNow'
import { asBigInt, asString, formatDuration } from '../lib/utils'
import {
  STAKING_REWARDS_ABI,
  STAKING_REWARDS_ADDRESS,
  STAKING_TOKEN_ABI,
  STAKING_TOKEN_ADDRESS,
  TOKEN_DECIMALS,
  etherscanAddressUrl,
} from '../config'

function CopyAddress({ label, address }: { label: string; address: string }) {
  const [copied, setCopied] = useState(false)

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(address)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch {
      setCopied(false)
    }
  }

  return (
    <div className="address-row">
      <span className="address-label">{label}</span>
      <code className="address-value">{address}</code>
      <div className="address-actions">
        <button className="btn btn-mini" onClick={handleCopy}>
          {copied ? 'Copied!' : 'Copy'}
        </button>
        <a className="btn btn-mini" href={etherscanAddressUrl(address)} target="_blank" rel="noreferrer">
          Etherscan ↗
        </a>
      </div>
    </div>
  )
}

export function ProtocolStats() {
  const now = useNow()

  const tokenName = useReadContract({
    abi: STAKING_TOKEN_ABI,
    address: STAKING_TOKEN_ADDRESS,
    functionName: 'name',
  })
  const tokenSymbol = useReadContract({
    abi: STAKING_TOKEN_ABI,
    address: STAKING_TOKEN_ADDRESS,
    functionName: 'symbol',
  })
  const tokenSupply = useReadContract({
    abi: STAKING_TOKEN_ABI,
    address: STAKING_TOKEN_ADDRESS,
    functionName: 'totalSupply',
  })

  const totalStaked = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'totalStaked',
  })
  const rewardRate = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'rewardRate',
  })
  const periodFinish = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'periodFinish',
  })
  const rewardPerToken = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'rewardPerToken',
  })
  const lockupDuration = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'LOCKUP_DURATION',
  })

  const name = asString(tokenName.data) ?? '—'
  const symbol = asString(tokenSymbol.data) ?? 'STK'
  const supplyValue = asBigInt(tokenSupply.data)
  const totalStakedValue = asBigInt(totalStaked.data)
  const rateValue = asBigInt(rewardRate.data)
  const finishValue = asBigInt(periodFinish.data)
  const rptValue = asBigInt(rewardPerToken.data)
  const lockupValue = asBigInt(lockupDuration.data)

  const totalStakedFormatted = totalStakedValue !== undefined ? formatUnits(totalStakedValue, TOKEN_DECIMALS) : '0'
  const supplyFormatted = supplyValue !== undefined ? formatUnits(supplyValue, TOKEN_DECIMALS) : '0'

  const rateFormatted = rateValue !== undefined ? formatUnits(rateValue, TOKEN_DECIMALS) : '0'
  const ratePerDay = rateValue !== undefined ? formatUnits(rateValue * 86400n, TOKEN_DECIMALS) : '0'
  const rewardPerTokenFormatted = rptValue !== undefined ? formatUnits(rptValue, TOKEN_DECIMALS) : '0'

  const periodEndsAtMs = finishValue !== undefined ? Number(finishValue) * 1000 : null
  const remainingSeconds = periodEndsAtMs ? Math.floor((periodEndsAtMs - now) / 1000) : 0
  const periodActive = periodEndsAtMs !== null && remainingSeconds > 0

  const lockupDays = lockupValue !== undefined ? Math.floor(Number(lockupValue) / 86400) : null

  return (
    <section className="card">
      <h2 className="card-title">Protocol Overview</h2>

      <div className="stat-grid">
        <div className="stat">
          <span className="stat-label">Token</span>
          <span className="stat-value">
            {name} ({symbol})
          </span>
        </div>
        <div className="stat">
          <span className="stat-label">Total Supply</span>
          <span className="stat-value">{supplyFormatted} {symbol}</span>
        </div>
        <div className="stat">
          <span className="stat-label">Total Staked</span>
          <span className="stat-value">{totalStakedFormatted} {symbol}</span>
        </div>
        <div className="stat">
          <span className="stat-label">Reward Rate</span>
          <span className="stat-value">
            {rateFormatted} {symbol}/s
          </span>
          <span className="stat-hint">{ratePerDay} {symbol}/day</span>
        </div>
        <div className="stat">
          <span className="stat-label">Rewards Period</span>
          <span className="stat-value">
            {periodActive ? `${formatDuration(remainingSeconds)} left` : 'Rewards ended'}
          </span>
          <span className="stat-hint">Next reward top-up resets the timer</span>
        </div>
        <div className="stat">
          <span className="stat-label">Reward Per Token</span>
          <span className="stat-value">{rewardPerTokenFormatted}</span>
        </div>
        <div className="stat">
          <span className="stat-label">Lockup</span>
          <span className="stat-value">{lockupDays !== null ? `${lockupDays}-day lockup` : '—'}</span>
          <span className="stat-hint">Staked tokens are locked for the full period</span>
        </div>
      </div>

      <div className="address-list">
        <CopyAddress label="Staking Token (STK)" address={STAKING_TOKEN_ADDRESS} />
        <CopyAddress label="Staking Rewards" address={STAKING_REWARDS_ADDRESS} />
      </div>
    </section>
  )
}
