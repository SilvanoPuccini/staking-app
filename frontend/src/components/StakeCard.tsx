import { useEffect, useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useSimulateContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from 'wagmi'
import { parseUnits, formatUnits, type Hex } from 'viem'
import { asBigInt, getErrorMessage } from '../lib/utils'
import { TxStatus } from './TxStatus'
import {
  STAKING_REWARDS_ABI,
  STAKING_REWARDS_ADDRESS,
  STAKING_TOKEN_ABI,
  STAKING_TOKEN_ADDRESS,
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

export function StakeCard() {
  const { address, isConnected } = useAccount()
  const publicClient = usePublicClient()
  const queryClient = useQueryClient()
  const { writeContractAsync } = useWriteContract()

  const [amount, setAmount] = useState('')
  const [approveHash, setApproveHash] = useState<Hex>()
  const [stakeHash, setStakeHash] = useState<Hex>()
  const [error, setError] = useState<string>()

  const amountWei = useMemo(() => parseAmount(amount), [amount])
  const isValidAmount = amountWei > 0n

  const balance = useReadContract({
    abi: STAKING_TOKEN_ABI,
    address: STAKING_TOKEN_ADDRESS,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  })

  const allowance = useReadContract({
    abi: STAKING_TOKEN_ABI,
    address: STAKING_TOKEN_ADDRESS,
    functionName: 'allowance',
    args: address ? [address, STAKING_REWARDS_ADDRESS] : undefined,
    query: { enabled: Boolean(address) },
  })

  const balanceValue = asBigInt(balance.data)
  const allowanceValue = asBigInt(allowance.data)

  const needsApproval = amountWei > 0n && (allowanceValue ?? 0n) < amountWei

  const approveSimulate = useSimulateContract({
    abi: STAKING_TOKEN_ABI,
    address: STAKING_TOKEN_ADDRESS,
    functionName: 'approve',
    args: [STAKING_REWARDS_ADDRESS, amountWei],
    query: { enabled: isConnected && isValidAmount && needsApproval },
  })

  const stakeSimulate = useSimulateContract({
    abi: STAKING_REWARDS_ABI,
    address: STAKING_REWARDS_ADDRESS,
    functionName: 'stake',
    args: [amountWei],
    query: { enabled: isConnected && isValidAmount && !needsApproval },
  })

  const approveReceipt = useWaitForTransactionReceipt({ hash: approveHash })
  const stakeReceipt = useWaitForTransactionReceipt({ hash: stakeHash })

  useEffect(() => {
    if (stakeReceipt.status === 'success') {
      queryClient.invalidateQueries()
      const id = setTimeout(() => setStakeHash(undefined), 8000)
      return () => clearTimeout(id)
    }
  }, [stakeReceipt.status, queryClient])

  useEffect(() => {
    if (approveReceipt.status === 'success') {
      queryClient.invalidateQueries()
    }
  }, [approveReceipt.status, queryClient])

  function handleMax() {
    if (balanceValue !== undefined) setAmount(formatUnits(balanceValue, TOKEN_DECIMALS))
  }

  async function handleAction() {
    if (!address || !publicClient) return
    setError(undefined)

    try {
      if (needsApproval) {
        const approveHashRes = await writeContractAsync({
          abi: STAKING_TOKEN_ABI,
          address: STAKING_TOKEN_ADDRESS,
          functionName: 'approve',
          args: [STAKING_REWARDS_ADDRESS, amountWei],
        })
        setApproveHash(approveHashRes)

        const approveTx = await publicClient.waitForTransactionReceipt({ hash: approveHashRes })
        if (approveTx.status !== 'success') {
          setError('Approve transaction reverted')
          return
        }
        setApproveHash(undefined)
      }

      const stakeHashRes = await writeContractAsync({
        abi: STAKING_REWARDS_ABI,
        address: STAKING_REWARDS_ADDRESS,
        functionName: 'stake',
        args: [amountWei],
      })
      setStakeHash(stakeHashRes)
      setAmount('')
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }

  const simulateError = needsApproval ? approveSimulate.error : stakeSimulate.error
  const pending = Boolean(approveHash) || Boolean(stakeHash)
  const buttonLabel = needsApproval ? 'Approve & Stake' : 'Stake'

  return (
    <section className="card">
      <h2 className="card-title">Stake</h2>

      <div className="input-group">
        <label className="input-label" htmlFor="stake-amount">
          Amount to stake
        </label>
        <div className="input-row">
          <input
            id="stake-amount"
            className="amount-input"
            type="text"
            inputMode="decimal"
            placeholder="0.0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            disabled={!isConnected}
          />
          <button className="btn btn-mini" onClick={handleMax} disabled={!isConnected || balanceValue === undefined}>
            MAX
          </button>
        </div>
        <span className="input-hint">
          Balance:{' '}
          {balanceValue !== undefined ? formatUnits(balanceValue, TOKEN_DECIMALS) : '0'} STK
        </span>
      </div>

      <button
        className="btn btn-primary btn-block"
        onClick={handleAction}
        disabled={!isConnected || !isValidAmount || pending}
      >
        {!isConnected ? 'Connect Wallet' : buttonLabel}
      </button>

      {simulateError && <p className="form-error">{getErrorMessage(simulateError)}</p>}
      {error && <p className="form-error">{error}</p>}
      <TxStatus hash={approveHash} receipt={approveReceipt.isSuccess ? approveReceipt.data : undefined} />
      <TxStatus hash={stakeHash} receipt={stakeReceipt.isSuccess ? stakeReceipt.data : undefined} />
    </section>
  )
}
