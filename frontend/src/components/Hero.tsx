const CONTRACTS_URL = 'https://sepolia.etherscan.io/address/0x5dd9d0B3189f0477392f0bA4B164823d5d030A65'

export function Hero() {
  return (
    <section className="hero">
      <div className="hero-orb hero-orb-1" aria-hidden="true" />
      <div className="hero-orb hero-orb-2" aria-hidden="true" />
      <div className="hero-orb hero-orb-3" aria-hidden="true" />

      <div className="hero-badge">
        <span className="hero-live-dot" aria-hidden="true" />
        Live on Sepolia
      </div>

      <h1 className="hero-title">
        Stake STK. Earn rewards. <span className="gradient-text">Own your yield.</span>
      </h1>

      <p className="hero-subtitle">
        A community staking protocol on Ethereum Sepolia. Lock your STK for 30 days and earn
        per-second rewards from a pre-funded pool.
      </p>

      <div className="hero-actions">
        <a className="btn btn-primary btn-lg" href="#app">
          Connect Wallet
        </a>
        <a className="btn btn-outline btn-lg" href={CONTRACTS_URL} target="_blank" rel="noreferrer">
          View Contracts
          <svg
            className="btn-arrow"
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <line x1="7" y1="17" x2="17" y2="7" />
            <polyline points="7 7 17 7 17 17" />
          </svg>
        </a>
      </div>

      <div className="hero-meta">
        <span>Sepolia testnet</span>
        <span className="hero-meta-dot" aria-hidden="true" />
        <span>Verified contracts</span>
        <span className="hero-meta-dot" aria-hidden="true" />
        <span>1M STK reward pool</span>
      </div>
    </section>
  )
}
