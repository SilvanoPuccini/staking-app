import { useEffect, useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import {
  useAccount,
  useReadContract,
  useSimulateContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from 'wagmi'
import { formatUnits, parseUnits, type Hex } from 'viem'
import { useNow } from '../hooks/useNow'
import { asBigInt, formatDateTime, formatDuration, getErrorMessage } from '../lib/utils'
import { TxStatus } from './TxStatus'
import {
  STAKING_REWARDS_ABI,
  STAKING_REWARDS_ADDRESS,
  TOKEN_DECIMALS,
} from '../config'

const AMOUNT_REGEX = /^\d*\.?\d*$/

function parseAmount(input: string): bigint {
  if (!AMOUNT_REGEX.test(input)) return 0n
  try {
    return parseUnits(input, TOKEN_DECIMALS)
  } catch {
    return 0n
  }
}

export function WithdrawCard() {
  const { address, isConnected } = useAccount()
  const queryClient = useQueryClient()
  const { writeContractAsync } = useWriteContract()
  const now = useNow()

  const [amount, setAmount] = useState('')
  const [withdrawHash, setWithdrawHash] = useState<Hex>()
  const [exitHash, setExitHash] = useState<Hex>()
  const [error, setError] = useState<string>()

  const amountWei = useMemo(() => parseAmount(amount), [amount])
  const isValidAmount = amountWei > 0n

  const staked = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'balances',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  })

  const lockupEnd = useReadContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'lockupEndOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  })

  const stakedValue = asBigInt(staked.data)
  const lockupEndValue = asBigInt(lockupEnd.data)

  const stakedAmount = stakedValue ?? 0n
  const inLockup = lockupEndValue !== undefined && lockupEndValue > 0n && Number(lockupEndValue) * 1000 > now
  const lockupEndsAtMs = lockupEndValue !== undefined ? Number(lockupEndValue) * 1000 : null
  const lockedReason = lockupEndsAtMs ? `Locked until ${formatDateTime(lockupEndValue)}` : undefined

  const canWithdraw = isValidAmount && amountWei <= stakedAmount && !inLockup
  const hasStake = stakedAmount > 0n

  const withdrawSimulate = useSimulateContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'withdraw',
    args: [amountWei],
    query: { enabled: isConnected && canWithdraw },
  })

  const exitSimulate = useSimulateContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'exit',
    query: { enabled: isConnected && hasStake && !inLockup },
  })

  const withdrawReceipt = useWaitForTransactionReceipt({ hash: withdrawHash })
  const exitReceipt = useWaitForTransactionReceipt({ hash: exitHash })

  useEffect(() => {
    if (withdrawReceipt.status === 'success' || exitReceipt.status === 'success') {
      queryClient.invalidateQueries()
      const id = setTimeout(() => {
        setWithdrawHash(undefined)
        setExitHash(undefined)
      }, 8000)
      return () => clearTimeout(id)
    }
  }, [withdrawReceipt.status, exitReceipt.status, queryClient])

  function handleMax() {
    if (stakedValue !== undefined) setAmount(formatUnits(stakedValue, TOKEN_DECIMALS))
  }

  async function handleWithdraw() {
    if (!address) return
    setError(undefined)
    try {
      const hash = await writeContractAsync({
        abi: STAKING_REWARDS_ABI,
        address: STAKING_REWARDS_ADDRESS,
        functionName: 'withdraw',
        args: [amountWei],
      })
      setWithdrawHash(hash)
      setAmount('')
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }

  async function handleExit() {
    if (!address) return
    setError(undefined)
    try {
      const hash = await writeContractAsync({
        abi: STAKING_REWARDS_ABI,
        address: STAKING_REWARDS_ADDRESS,
        functionName: 'exit',
      })
      setExitHash(hash)
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }

  const pending = Boolean(withdrawHash) || Boolean(exitHash)

  return (
    <section className="card">
      <h2 className="card-title">Withdraw</h2>

      <div className="input-group">
        <label className="input-label" htmlFor="withdraw-amount">
          Amount to withdraw
        </label>
        <div className="input-row">
          <input
            id="withdraw-amount"
            className="amount-input"
            type="text"
            inputMode="decimal"
            placeholder="0.0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            disabled={!isConnected || inLockup}
          />
          <button className="btn btn-mini" onClick={handleMax} disabled={!hasStake || inLockup}>
            MAX
          </button>
        </div>
        <span className="input-hint">
          Staked: {formatUnits(stakedAmount, TOKEN_DECIMALS)} STK
        </span>
        {inLockup && lockedReason && (
          <span className="input-hint input-lock">
            🔒 {lockedReason} · {lockupEndsAtMs !== null && formatDuration(Math.floor((lockupEndsAtMs - now) / 1000))} remaining
          </span>
        )}
      </div>

      <button
        className="btn btn-primary btn-block"
        onClick={handleWithdraw}
        disabled={!isConnected || !canWithdraw || pending}
      >
        {!isConnected ? 'Connect Wallet' : inLockup ? 'Locked' : 'Withdraw'}
      </button>

      {withdrawSimulate.error && <p className="form-error">{getErrorMessage(withdrawSimulate.error)}</p>}

      <div className="divider" />

      <h3 className="card-subtitle">Close Position</h3>
      <p className="claim-amount">Withdraw everything and claim rewards in one transaction.</p>
      <button
        className="btn btn-danger btn-block"
        onClick={handleExit}
        disabled={!isConnected || !hasStake || inLockup || pending}
      >
        {!isConnected ? 'Connect Wallet' : inLockup ? 'Locked' : 'Exit (Withdraw + Claim)'}
      </button>
      {exitSimulate.error && <p className="form-error">{getErrorMessage(exitSimulate.error)}</p>}
      {error && <p className="form-error">{error}</p>}
      <TxStatus hash={withdrawHash} receipt={withdrawReceipt.isSuccess ? withdrawReceipt.data : undefined} />
      <TxStatus hash={exitHash} receipt={exitReceipt.isSuccess ? exitReceipt.data : undefined} />
    </section>
  )
}
