import { UserRejectedRequestError, type BaseError } from 'viem'

export function getErrorMessage(error: unknown): string {
  if (!error) return 'Something went wrong'

  if (error instanceof UserRejectedRequestError) {
    return 'Transaction cancelled by user'
  }

  const err = error as BaseError & { name?: string }
  if (err.name === 'ContractFunctionExecutionError' || err.name === 'ContractCallError') {
    return err.shortMessage || err.message || 'Transaction reverted'
  }

  return err.shortMessage || err.message || 'Something went wrong'
}

export function asBigInt(value: unknown): bigint | undefined {
  return typeof value === 'bigint' ? value : undefined
}

export function asString(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined
}

export function formatDuration(totalSeconds: number): string {
  if (totalSeconds <= 0) return '0s'

  const days = Math.floor(totalSeconds / 86400)
  const hours = Math.floor((totalSeconds % 86400) / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = Math.floor(totalSeconds % 60)

  if (days > 0) return `${days}d ${hours}h ${minutes}m`
  if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`
  if (minutes > 0) return `${minutes}m ${seconds}s`
  return `${seconds}s`
}

export function formatDateTime(unixSeconds: bigint | undefined): string {
  if (!unixSeconds || unixSeconds === 0n) return '—'
  return new Date(Number(unixSeconds) * 1000).toLocaleString(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}
