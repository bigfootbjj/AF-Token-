[AF_Whitepaper.md](https://github.com/user-attachments/files/24145250/AF_Whitepaper.md)
# AF Token – White Paper

## Vision

AF is an experimental ERC-20 token deployed on Polygon. It is not a traditional project with a roadmap, but a live on-chain experiment.

The core idea is simple:

Test whether a widely distributed, low-value token with tiny liquidity can still attract a community of patient holders. Observe how people behave when selling quickly has a visible impact on a fragile market, while holding and coordinating might allow a more meaningful market to emerge over time.

There are no promises, no guaranteed returns, and no complex narrative. AF is a coordination game built on transparent rules: deflationary supply, small liquidity, and an automated on-chain distribution to new Polygon users.


## Tokenomics

AF is an ERC-20 token with a hard-capped initial supply and a built-in burn on every transfer.

- Chain: Polygon
- Standard: ERC-20
- Initial supply: 10,000,000 AF

### Deflationary burn

AF uses a simple deflationary mechanism:

On every transfer of AF, including wallet-to-wallet and DEX trades, 1% of the transferred amount is burned. The burned tokens are permanently removed from supply, making AF structurally deflationary over time.

This design rewards patient holders: as on-chain activity accumulates, the circulating supply gradually decreases and each remaining token represents a slightly larger share of the network.

### Distribution

The initial supply is allocated as follows:

A large portion is reserved for on-chain distribution experiments, primarily through an automated bot that sends small amounts of AF to new Polygon users.

A small portion is provided as liquidity in an AF/USDC pool on a Polygon DEX.

The remaining tokens are held in a transparent treasury for future experiments, all movements trackable on-chain.

Exact allocations and any changes to them can be monitored directly via the AF token contract and associated addresses on PolygonScan.


## Distribution Mechanism

AF distribution is not driven by presales or private rounds. It is primarily an on-chain experiment using automation and tiny incentives.

### Gas refund style distribution

A dedicated automation bot monitors new activity on Polygon and sends a small fixed amount of AF (for example 2 AF) to eligible wallets.

The goal is to welcome new users to Polygon, put AF directly in their wallets, and observe how they behave with a micro-position in an experimental, low-liquidity token.

This mechanism runs fully on-chain, and every distribution can be inspected in real time through PolygonScan.

### Eligibility and rules

To reduce farming and keep the experiment meaningful, distribution follows simple rules:

Only wallets performing their first ever transaction on Polygon are eligible.

Gas cost must stay within a defined range to filter out obvious spam or unrealistic patterns.

Each wallet can only receive AF once: one wallet equals one bonus, with no repeated rewards for the same address.

The objective is to spread AF widely, slowly and transparently, while avoiding airdrop farmers and obvious bots as much as possible. All distributions remain visible and auditable on-chain at any time.


## Market and liquidity

AF is intentionally launched with tiny liquidity. The goal is not to simulate a mature market from day one, but to study how a community behaves around a fragile pool.

A small AF/USDC liquidity pool is created on a Polygon DEX, with limited depth and fully visible parameters. In this configuration, the market is highly sensitive: every buy or sell has a noticeable impact on price, especially in the early days.

Instead of large capital and aggressive market-making, AF relies on transparency and organic participation. Anyone can verify the pool size and liquidity, the main holders, and any treasury movement directly through PolygonScan and other explorers.


## Coordination game

AF is designed as a simple coordination game between holders.

If holders are patient and avoid dumping their small allocations into a tiny pool for negligible amounts, the market can remain relatively stable and slowly grow over time.

If holders rush to sell into shallow liquidity, the price collapses quickly and the experiment highlights how difficult collective coordination can be under real on-chain conditions.

Key aspects of the game:

The 1% burn on every transfer makes panic selling and excessive churning more costly in terms of total supply.

The tiny liquidity ensures that every decision is visible: single trades can move the price significantly, showing the impact of individual behavior.

The wide distribution via automation means many small holders share responsibility for the eventual outcome of the market.

AF does not promise a particular outcome. The result of the experiment depends on the collective behavior of its holders.


## Governance and future experiments

AF does not start with a complex governance system or detailed roadmap. Instead, it follows a "minimal first, emergent later" philosophy.

At launch, there is no DAO, no formal voting, and no binding promises.

Early decisions about distribution parameters, liquidity size, and experimental tweaks are taken off-chain by the initial creator, but with full on-chain transparency for all transactions and contract interactions.

If a critical mass of engaged holders emerges, AF can progressively introduce:

Simple signaling mechanisms such as off-chain votes, forum polls, and on-chain snapshots to guide new experiments.

Additional utilities or experiments that reuse AF as a coordination tool, such as extra rewards for long-term holders, opt-in staking or locking experiments, new distribution rules, and collaborations with other Polygon projects or protocols.

Nothing in this document should be interpreted as financial advice, an investment recommendation, or a guarantee of future value. AF remains an on-chain experiment about behavior, incentives, and coordination under tight liquidity and a deflationary token model.


## Contract and verification

All AF contract interactions and distributions are fully verifiable on PolygonScan. The contract address is publicly auditable, and token holders can inspect the deflationary mechanism, treasury movements, and all historical distributions in real time.

This white paper serves as a description of intent and design philosophy. The actual on-chain behavior of AF is the ground truth, and holders are encouraged to verify everything directly through the blockchain.
