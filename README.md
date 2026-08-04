# Staking Protocol — STK

> Un proyecto de portfolio blockchain de ciclo completo: desde la metodología
> de investigación y desarrollo hasta un protocolo de staking en vivo,
> verificado y atacado en pruebas sobre Ethereum Sepolia — construido con un
> flujo de trabajo asistido por IA.

**Hacé stake de STK. Ganá recompensas. Controlá tu yield.** Este repo es un
case study completo de cómo construir, probar, endurecer y publicar un
protocolo DeFi — documentando no solo *qué* se construyó, sino *cómo* se
construyó y *por qué* se puede confiar.

» English version: [README.en.md](README.en.md)

---

## 1. La historia — de la investigación a producción

Este proyecto siguió una metodología estructurada que refleja cómo un equipo
real de producto/ingeniería entregaría un protocolo DeFi:

| Fase | Qué pasó |
|---|---|
| **1. Investigación** | Estudio del dominio de staking: el diseño del acumulador `StakingRewards` de Synthetix, estándares de tokens ERC-20, la matemática de reward-per-share, clases de exploits comunes (reentrancy, flash loans, inflación por donación, griefing). |
| **2. Esquema de desarrollo** | Se definió un formato dirigido por specs: proposal → specs → design → tasks → apply → verify → archive (OpenSpec). Cada fase tiene entradas/salidas explícitas y criterios de aceptación. |
| **3. Build asistido por IA** | El plan se entregó a un agente de IA de codificación (OpenCode) con TDD estricto y el esquema como guía. La IA implementó los contratos Solidity, los tests de Foundry y esta documentación — *yo revisé y dirigí cada paso*. |
| **4. Análisis y hardening** | Se ejecutó la revisión de seguridad completa que aparece abajo (suite de ataques adversariales) y pruebas de invariantes/fuzzing para buscar formas de corromper el protocolo. |
| **5. Skills / tooling** | El proceso se codificó en skills reutilizables (smart-contract-security, foundry-testing, web3-frontend, workflow SDD) — convirtiendo una experiencia puntual en un proceso repetible. |
| **6. Entorno** | Toolchain de Foundry, cadena local anvil para iteración rápida, gates estilo CI (fmt, build, test, coverage). |
| **7. Producción** | Desplegado y verificado en el testnet Ethereum Sepolia con una dApp de frontend funcional y una transacción real on-chain de staking + claim. |

**Por qué importa:** el valor no está solo en el código — está en el *método*:
investigación → esquema → ejecución con IA → verificación → hardening →
publicación. Ese es el loop de ingeniería completo que este proyecto demuestra
de punta a punta.

---

## 2. Qué hace el protocolo

Dos contratos mínimos:

- **StakingToken (STK)** — un ERC-20 de suministro fijo (10,000,000 STK, 18
  decimales, sin mint/burn después del deploy).
- **StakingRewards** — un contrato de staking estilo Synthetix: los usuarios
  hacen stake de STK con un **lockup de 30 días** y ganan **recompensas por
  segundo** pagadas en STK desde un pool de recompensas pre-financiado.

```
StakingToken (ERC-20, fixed supply)
        │ transfers / approvals
        ▼
StakingRewards (Ownable, ReentrancyGuard, SafeERC20)
  stake / withdraw / claimRewards / exit / notifyRewardAmount / recoverERC20
```

### Mecánicas clave

- **Stake** — depositás STK; tu posición queda bloqueada por 30 días. Stakes
  repetidos extienden el lockup de toda la posición (diseño D3).
- **Earn** — las recompensas se acumulan cada segundo vía un acumulador
  reward-per-share mientras estás stakeado; son reclamables en cualquier
  momento, incluso durante el lockup. Solo el principal queda bloqueado.
- **Withdraw / Exit** — después de `lockupEndOf`, retirás el principal;
  `exit()` retira el principal y reclama las recompensas atómicamente en una
  sola transacción.
- **Owner** — financia ventanas de emisión de 90 días vía
  `notifyRewardAmount()` y puede rescatar tokens externos atascados vía
  `recoverERC20()` (STK mismo queda excluido).

### Parámetros

| Parámetro | Valor |
|---|---|
| `INITIAL_SUPPLY` | 10,000,000 STK |
| `REWARDS_DURATION` | 90 días (7,776,000 s) |
| `LOCKUP_DURATION` | 30 días (2,592,000 s) |
| Pool inicial de recompensas | 1,000,000 STK (10% del suministro) |
| Reward rate | `min(reward + leftover, balance - totalStaked) / REWARDS_DURATION` |

---

## 3. Cómo se probó — 58 tests, 5 capas

| Capa | Cantidad | Qué demuestra |
|---|---|---|
| Unit (token) | 8 | metadatos, suministro fijo, sin mint, transfers/allowances + reverts |
| Unit (staking) | 27 | stake/lockup, acumulación lineal, claim, límite de withdraw, exit atómico, notify rate/cap/owner, exclusiones de recoverERC20, reentrancy, extensión de lockup + casos estilo fuzz de round-trip y claim idempotente |
| Gobernanza | 8 | owner = timelock, acciones de owner bloqueadas directas, flujo schedule/wait/execute, atacante no puede schedule/execute, recoverERC20 timelockeado, fix endurecido sobrevive al timelock |
| Invariant | 5 | solvencia, conservación contable, principal monótono, integridad del lockup, recompensas acotadas |
| **Security attacks** | **10** | **PoCs adversariales que intentan corromper el protocolo (ver §4)** |

```shell
forge build                 # compilar
forge test                  # suite completa: 58 tests
forge fmt --check           # gate de formato
forge coverage              # ~99% de líneas en src/
```

La suite de invariantes conduce el contrato por 256 secuencias aleatorias ×
128 llamadas (basada en handlers, montos acotados, saltos de tiempo aleatorios
de 0–45d) y verifica reglas de verdad financiera después de cada secuencia —
solvencia, conservación contable, principal monótono, integridad del lockup,
recompensas acotadas.

---

## 4. Revisión de seguridad — intentamos romperlo

El protocolo fue atacado deliberadamente con una **suite de tests
adversariales** (`test/SecurityAttack.t.sol`). Cada test es un
proof-of-concept de un vector de ataque conocido. **Los 10 ataques fallaron en
corromper el protocolo** (8 bloqueados por diseño, 2 cerrados por hardening
del contrato).

| # | Vector de ataque | Intento | Resultado |
|---|---|---|---|
| 1 | **Inflación por donación** | Donar 500k STK directamente al contrato para inflar `earned()` | ❌ Bloqueado — contabilidad interna (`totalStaked`), nunca confía en `balanceOf(this)` |
| 2 | **Flash-loan stake** | Stake de 1M, claim instantáneo, withdraw en el mismo bloque para repagar el préstamo | ❌ Bloqueado — el lockup de 30 días impide retirar el principal |
| 3 | **Reentrancy** | Re-entrar a `claimRewards` durante un transfer | ❌ Bloqueado — ReentrancyGuard + orden CEI |
| 4 | **Griefing de lockup** | Stake de 1 wei para resetear el lockup de una víctima | ❌ Bloqueado — el lockup es por usuario (`lockupEndOf[msg.sender]`) |
| 5 | **Silent reward kill** | El owner notifica por debajo de `REWARDS_DURATION` → `rewardRate = 0` | ❌ Fixed — `notifyRewardAmount` revierte con `RewardPeriodTooSmall` cuando el monto fundado (reward + leftover) queda por debajo de `REWARDS_DURATION`; un período nunca puede fondear cero recompensas en silencio |
| 6 | **Canibalización del principal** | El owner notifica un monto que excede el superávit de recompensas | ❌ Fixed — el cap usa `balanceOf(this) - totalStaked` (superávit sobre el principal stakeado); el principal nunca puede comprometerse como recompensas |
| 7 | **Rescatar STK** | `recoverERC20(STK)` | ❌ Revierte — STK siempre está excluido (diseño D5) |
| 8 | **Control de acceso** | Un no-owner llama a `notify`/`recover` | ❌ Revierte — `onlyOwner` |
| 9 | **Stake desproporcionado** | Stake de 1 wei captura valor excedente | ❌ Bloqueado — el acumulador global reward-per-token es justo |
| 10 | **Robo de recompensas** | Un atacante reclama las recompensas de una víctima | ❌ Bloqueado — las recompensas están aisladas por usuario |

**Hallazgos:** no se encontró ninguna vulnerabilidad explotable para un
atacante externo. Los dos riesgos de owner documentados en la revisión
anterior (notify sub-financiado que hundía la tasa a cero; el cap de notify
que incluía el principal stakeado) también quedaron cerrados por lógica de
contrato en el commit `ad1203f` — ambos requerían que el *propio owner*
actuara mal y ninguno permitía que un tercero robara fondos.

### Principios de diseño de seguridad

- **Orden CEI** en cada función mutativa (estado antes de llamadas externas).
- **ReentrancyGuard** en `stake`, `withdraw`, `claimRewards`, `exit`.
- **SafeERC20** para transfers; aritmética chequeada (Solidity 0.8.36).
- **Contabilidad interna** — nunca confía en `balanceOf(this)` para pasivos
  (safe frente a donaciones).
- **`recoverERC20` excluye STK** — el principal stakeado y el pool de
  recompensas son intocables.
- **Lockup por diseño** — revierte `LockupNotEnded` hasta `lockupEndOf`.
- **Notify hardening** — revert con `RewardPeriodTooSmall` por debajo de
  `REWARDS_DURATION`; el cap de recompensas excluye el principal stakeado
  (`balance - totalStaked`).

---

## 5. Desplegado en Sepolia — en vivo y verificado

### v2 (actual) — endurecido + gobernanza con timelock

La **v2** es el contrato activo: código endurecido (fix de `notifyRewardAmount`,
commit `ad1203f`) gobernado por un `TimelockController` — toda acción de owner
(notify/recover) requiere schedule → esperar 2 días → execute. El owner ya no
puede actuar al instante.

| Contrato | Dirección (Sepolia) | Explorer |
|---|---|---|
| `StakingRewards` v2 | `0x1190ae86140b92118f9cb84061a8bfc19bbca781` | [etherscan](https://sepolia.etherscan.io/address/0x1190ae86140b92118f9cb84061a8bfc19bbca781) |
| `TimelockController` | `0x018efb5099505113625dabc5dc6f5513ad252c6b` | [etherscan](https://sepolia.etherscan.io/address/0x018efb5099505113625dabc5dc6f5513ad252c6b) |
| `StakingToken` (reusado) | `0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5` | [etherscan](https://sepolia.etherscan.io/address/0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5) |

Run de deploy v2 (2026-08-04, `forge script script/DeployV2.s.sol --broadcast --verify`):

- **Deployer:** `0x6f81b75EDc0C7060aa5F1bA14B7fd45bD663A5bD`
- **Staking v2 deploy tx:** `0x43112aa4a41fff3ab9ba15ac22e6abdfc8be4892f42d8c1ff508c579535ff833`
- **Timelock deploy tx:** `0x0cfde46c9e58129d7677cc95b31bce5766f9abf9bc6f560819e5c9c78ba6b00b`
- **Pool financiado + período 1 iniciado + ownership transferido al timelock**
- **minDelay:** 172,800 s (2 días)

### v1 (legacy) — original desplegado y verificado

La **v1** fue la primera versión en producción (código pre-hardening). Sigue
pagando rewards hasta su `periodFinish`; el stake existente se migra cuando
vence su lockup (2026-09-03).

| Contrato | Dirección (Sepolia) | Explorer |
|---|---|---|
| `StakingRewards` v1 | `0x42A3cFFDAE52Ed302Bb78D14071B386F85EFCfCc` | [etherscan](https://sepolia.etherscan.io/address/0x42A3cFFDAE52Ed302Bb78D14071B386F85EFCfCc) |
| `StakingToken` | `0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5` | [etherscan](https://sepolia.etherscan.io/address/0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5) |

Deploy original (2026-08-04, `forge script --broadcast --verify`):

- **Token deploy tx:** `0x78ecc3e6707138264f5d41a8a1feff8280e6652c90d242b075852e1be5f67f0d`
- **Staking deploy tx:** `0x553f1e444c6c307091258ca7812a33bf14592ea1ddacc7d803d7dfe6e0f7585f`

### Estado on-chain en vivo (v2)

- `totalSupply` 10,000,000 STK → 9,000,000 deployer / 1,000,000 reward pool
- `rewardRate` 128,600,823,045,267,488 ≈ 1e24 / 7,776,000 s
- `periodFinish` = deploy v2 + 90 días (2026-11-02)
- `owner` = TimelockController (2 días de delay en toda acción de owner)

### Prueba on-chain real (v1)

El protocolo se ejercitó con una **transacción real en Sepolia**:

- ✅ Stake de 1,000 STK (tx `0xfd1b9b19f2578fbfe0f86e3a08cf254c47290bb6e44106ba7a383973078f53e3` — evento `Staked`)
- ✅ Recompensas acumuladas en vivo (`earned()` creció por segundo)
- ✅ Claim de **467.59 STK** vía la dApp de frontend — verificado on-chain (balance del deployer +467.59 STK, pool −467.59 STK)

---

## 6. dApp de frontend

Una app estilo landing en React + Vite + TypeScript en [`frontend/`](frontend/)
conectada a los contratos en vivo de Sepolia con **wagmi + viem** (wallet
inyectada de MetaMask). Las secciones hero + mission explican *por qué* existe
el protocolo; el panel de la app ofrece conexión de wallet, stats del
protocolo, tu posición (auto-refresh), stake (approve + stake), claim de
recompensas, withdraw y exit atómico — con links a Etherscan en cada
transacción y manejo amigable de errores.

```shell
cd frontend
npm install
npm run dev        # http://localhost:5173
```

No hay private keys en el frontend — todo el signing ocurre en MetaMask.

---

## 7. Ejecutalo localmente

```shell
# Contratos + tests (Foundry)
forge build
forge test                    # 58 tests
forge fmt --check

# Cadena local
anvil &
PRIVATE_KEY=0xac09...f2ff80 \   # anvil account #0
  forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast

# v2 (hardened + timelock): reusa el token si ya existe, o deploya uno nuevo
TOKEN_ADDRESS=0x... \
PRIVATE_KEY=0xac09...f2ff80 \
  forge script script/DeployV2.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast

# dApp (frontend/)
cd frontend && npm install && npm run dev
```

---

## 8. Artefactos del proceso

- **Registro de cambios dirigido por specs** — `openspec/changes/archive/2026-08-03-staking-protocol/`
  (proposal → specs → design → tasks → verify), mostrando el rastro completo
  de requerimientos a verificación.
- **Suite de ataques** — `test/SecurityAttack.t.sol` (10 PoCs adversariales).
- **Gobernanza** — `test/Timelock.t.sol` (8 tests de integración con el timelock).
- **Invariantes** — `test/invariants/` (5 reglas de verdad financiera).
- **Registro de deploy** — `broadcast/Deploy.s.sol/11155111/` (v1) y `broadcast/DeployV2.s.sol/11155111/` (v2).

## Fuera de alcance (v1)

Vesting/penalties, emisiones mintables, recompensas multi-token, shares
ERC-4626, permit, upgradeability, timelock, deploy en mainnet, indexación con
subgraph.
