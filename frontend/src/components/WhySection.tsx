import type { ReactNode } from 'react'

type Feature = {
  title: string
  description: string
  icon: ReactNode
}

const FEATURES: Feature[] = [
  {
    title: 'Earn passively',
    description: 'Stake once, earn rewards every second from a pre-funded 1M STK pool.',
    icon: (
      <svg
        width="22"
        height="22"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" />
      </svg>
    ),
  },
  {
    title: 'Security first',
    description:
      'Audited-by-invariants, CEI ordering, reentrancy-guarded, SafeERC20. No admin tricks.',
    icon: (
      <svg
        width="22"
        height="22"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <path d="M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6l8-4z" />
        <polyline points="9 12 11 14 15 10" />
      </svg>
    ),
  },
  {
    title: 'Fair lockup',
    description: '30-day principal lockup protects the pool; rewards stay claimable at any time.',
    icon: (
      <svg
        width="22"
        height="22"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <rect x="5" y="11" width="14" height="9" rx="2" />
        <path d="M8 11V8a4 4 0 0 1 8 0v3" />
      </svg>
    ),
  },
  {
    title: 'Transparent & verifiable',
    description: 'Verified contracts on Etherscan. Every transaction is on-chain, nothing hidden.',
    icon: (
      <svg
        width="22"
        height="22"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z" />
        <circle cx="12" cy="12" r="3" />
      </svg>
    ),
  },
]

export function WhySection() {
  return (
    <section className="section why-section" id="why">
      <div className="section-head">
        <span className="section-eyebrow">The mission</span>
        <h2 className="section-title">Why STK?</h2>
        <p className="section-subtitle">
          Built to be boring, secure and fair — the way a staking protocol should be.
        </p>
      </div>

      <div className="feature-grid">
        {FEATURES.map((feature) => (
          <div className="feature-card" key={feature.title}>
            <div className="feature-icon" aria-hidden="true">
              {feature.icon}
            </div>
            <h3 className="feature-title">{feature.title}</h3>
            <p className="feature-desc">{feature.description}</p>
          </div>
        ))}
      </div>
    </section>
  )
}
