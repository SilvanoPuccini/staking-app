import { useAccount, useChainId } from 'wagmi'
import { CHAIN_ID, CHAIN_NAME } from './config'
import { WalletConnect } from './components/WalletConnect'
import { ProtocolStats } from './components/ProtocolStats'
import { UserPanel } from './components/UserPanel'
import { StakeCard } from './components/StakeCard'
import { ClaimCard } from './components/ClaimCard'
import { WithdrawCard } from './components/WithdrawCard'
import { Hero } from './components/Hero'
import { WhySection } from './components/WhySection'
import { HowItWorks } from './components/HowItWorks'

function App() {
  const { isConnected } = useAccount()
  const chainId = useChainId()
  const onRightChain = chainId === CHAIN_ID

  return (
    <div className="app">
      <header className="header">
        <div className="brand">
          <span className="brand-mark">STK</span>
          <span className="brand-name">Staking Rewards</span>
        </div>
        <WalletConnect />
      </header>

      <main className="container">
        <Hero />
        <WhySection />
        <HowItWorks />

        <section className="section app-section" id="app">
          <div className="section-head">
            <span className="section-eyebrow">Dashboard</span>
            <h2 className="section-title">The App</h2>
            <p className="section-subtitle">
              Connect your wallet to stake STK, claim rewards and manage your position.
            </p>
          </div>

          <ProtocolStats />

          {isConnected && !onRightChain && (
            <div className="banner banner-warn">
              <span>
                You're on the wrong network. Switch to {CHAIN_NAME} to stake, claim and withdraw.
              </span>
            </div>
          )}

          {isConnected && onRightChain && (
            <>
              <UserPanel />

              <div className="card-grid">
                <StakeCard />
                <div className="card-stack">
                  <ClaimCard />
                  <WithdrawCard />
                </div>
              </div>
            </>
          )}

          {!isConnected && (
            <p className="hint">
              Connect your wallet to stake STK, claim rewards and manage your position.
            </p>
          )}
        </section>
      </main>

      <footer className="footer">
        <span>Sepolia testnet · Portfolio project</span>
        <span className="footer-muted">Contracts verified · No private keys stored</span>
      </footer>
    </div>
  )
}

export default App
