const STEPS = [
  {
    number: '01',
    title: 'Connect wallet',
    description: 'Link your wallet on the Ethereum Sepolia network.',
  },
  {
    number: '02',
    title: 'Approve & stake',
    description: 'Approve STK spend, then lock your tokens for a 30-day period.',
  },
  {
    number: '03',
    title: 'Claim rewards',
    description: 'Rewards accrue every second — claim them anytime while the period is active.',
  },
]

export function HowItWorks() {
  return (
    <section className="section how-section" id="how">
      <div className="section-head">
        <span className="section-eyebrow">How it works</span>
        <h2 className="section-title">Start earning in three steps</h2>
        <p className="section-subtitle">
          No complex setup. Just connect, stake and let the protocol work for you.
        </p>
      </div>

      <div className="steps">
        {STEPS.map((step) => (
          <div className="step-card" key={step.number}>
            <span className="step-num">{step.number}</span>
            <h3 className="step-title">{step.title}</h3>
            <p className="step-desc">{step.description}</p>
          </div>
        ))}
      </div>
    </section>
  )
}
