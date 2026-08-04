import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from 'wagmi'
import { CHAIN_ID, CHAIN_NAME, shortenAddress } from '../config'

export function WalletConnect() {
  const { address, isConnected } = useAccount()
  const { connect, connectors, isPending: isConnecting } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()
  const { switchChain, isPending: isSwitching } = useSwitchChain()

  if (!isConnected || !address) {
    return (
      <div className="wallet-connect">
        <button
          className="btn btn-primary"
          onClick={() => connect({ connector: connectors[0] })}
          disabled={isConnecting || !connectors[0]}
        >
          {isConnecting ? 'Connecting...' : 'Connect Wallet'}
        </button>
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
