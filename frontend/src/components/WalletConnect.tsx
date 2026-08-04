import { useEffect, useState } from 'react'
import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from 'wagmi'
import { CHAIN_ID, CHAIN_NAME, shortenAddress } from '../config'

export function WalletConnect() {
  const { address, isConnected, status } = useAccount()
  const { connect, connectors, isPending: isConnecting } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()
  const { switchChain, isPending: isSwitching } = useSwitchChain()

  // If the connection popup is slow (or blocked), show a hint and
  // re-enable the button so the user can retry instead of being stuck.
  const [showSlowHint, setShowSlowHint] = useState(false)
  useEffect(() => {
    if (!isConnecting) {
      setShowSlowHint(false)
      return
    }
    const id = setTimeout(() => setShowSlowHint(true), 8000)
    return () => clearTimeout(id)
  }, [isConnecting])

  const connecting = isConnecting || status === 'connecting'

  if (!isConnected || !address) {
    return (
      <div className="wallet-connect">
        <div className="wallet-stack">
          <button
            className="btn btn-primary"
            onClick={() => connect({ connector: connectors[0] })}
            disabled={connecting || !connectors[0]}
          >
            {connecting ? 'Connecting...' : 'Connect Wallet'}
          </button>
          {showSlowHint && (
            <span className="wallet-hint">No MetaMask popup? Check for a blocked popup and try again.</span>
          )}
        </div>
      </div>
    )
  }

  const onWrongChain = chainId !== CHAIN_ID

  return (
    <div className="wallet-connect">
      <div className="wallet-meta">
        <span className={`chain-badge ${onWrongChain ? 'chain-wrong' : ''}`}>
          {onWrongChain ? 'Wrong network' : CHAIN_NAME}
        </span>
        <span className="address-chip" title={address}>
          {shortenAddress(address)}
        </span>
      </div>
      {onWrongChain && (
        <button
          className="btn btn-warning"
          onClick={() => switchChain({ chainId: CHAIN_ID })}
          disabled={isSwitching}
        >
          {isSwitching ? 'Switching...' : 'Switch to Sepolia'}
        </button>
      )}
      <button className="btn btn-ghost" onClick={() => disconnect()}>
        Disconnect
      </button>
    </div>
  )
}
