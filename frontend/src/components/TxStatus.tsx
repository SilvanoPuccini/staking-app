import type { Hex } from 'viem'
import { etherscanTxUrl } from '../config'

interface TxStatusProps {
  hash?: Hex
  receipt?: {
    status: 'success' | 'reverted'
  }
}

export function TxStatus({ hash, receipt }: TxStatusProps) {
  if (!hash) return null

  let statusText = 'Pending...'
  let statusClass = 'tx-pending'
  let statusDotClass = 'dot-pending'

  if (receipt) {
    if (receipt.status === 'success') {
      statusText = 'Mined successfully'
      statusClass = 'tx-success'
      statusDotClass = 'dot-success'
    } else {
      statusText = 'Reverted'
      statusClass = 'tx-error'
      statusDotClass = 'dot-error'
    }
  }

  return (
    <div className={`tx-status ${statusClass}`}>
      <span className={`status-dot ${statusDotClass}`} />
      <span>
        {statusText}{' '}
        <a href={etherscanTxUrl(hash)} target="_blank" rel="noreferrer">
          view on Etherscan ↗
        </a>
      </span>
    </div>
  )
}
