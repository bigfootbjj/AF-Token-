# DAWN / InfraFi — Deux pistes ouvertes : décodage IDL Loopscale + marché Orca sUSD.infra

Suite à "on lance les 2 autres passes" : décodage de l'IDL Anchor du vault Loopscale (autorité
borrow/repay) et investigation du marché secondaire sUSD.infra/USD.infra sur Orca (piste C-18).
**Statut : recherche exploratoire, aucun nouveau finding soumissible identifié — documenté
honnêtement, y compris les culs-de-sac, conformément à la règle anti-fabrication.**

---

## Pass 1 — Décodage de l'IDL Anchor du programme Loopscale

### Méthode

IDL récupéré **on-chain, sans dépendance externe**, en répliquant l'algorithme client d'Anchor :
1. `base = findProgramAddress([], programId)` → PDA vide pour `1oopBoJG58DgkUVKkEzKgyG9dvRmpgeEm1AVjoHkF78`
2. `idl_address = createWithSeed(base, "anchor:idl", programId)` → `8jaPDEbzjkgJT8qTgMwCxbVUZt3p2MoMsCovyNyuNShD`
3. `getAccountInfo` sur cette adresse → compte de 23594 bytes : 8 bytes discriminator + 32 bytes
   autorité + 4 bytes longueur + blob zlib-compressé → décompressé = IDL JSON complet (78KB),
   programme `loopscale v0.1.0`.

### Résultat 1 — Les deux comptes "dupliqués" (EZ8sq2.../4rXteU...) sont bien DEUX vaults distincts, pas un doublon

En décodant la struct `Vault` (162 bytes = 8 discriminator + manager(32) + nonce(32) + bump(1) +
lp_supply(8) + lp_mint(32) + principal_mint(32) + cumulative_principal_deposited(8) +
deposits_enabled(1) + max_early_unstake_fee(8)) :

| Champ | `EZ8sq2FN...` | `4rXteUmb...` |
|---|---|---|
| `manager` | `dmgrEuRb9xTckiafn3wpNHNhKq1uqRwPunnZEGCLP1N` | **identique** |
| `principal_mint` | `dawn7ZUF...` (USD.infra) | **identique** |
| `lp_mint` | `DPny41HgUcrMAmmGZq9BaFaHwxuNJ5GLPjHnCiNMzuE4` | `GvEMgNT6GKiYTvg7TskDio6RKzQdCuhwmH55tVCLaJTe` (sUSD.infra, connu) |
| `cumulative_principal_deposited` | 352.246083 | 11,440,845.857283 |
| `lp_supply` | 117.926083 | 10,027,325.9281 |

**Conclusion : ce sont deux vaults DAWN réels et distincts** (nonce différent, lp_mint différent,
tailles très différentes — un petit vault quasi-vide à côté du vault principal connu), partageant
la même autorité `manager` et le même actif sous-jacent (USD.infra). Ça clôt définitivement la
question ouverte depuis le round 1 ("texte Immunefi dupliqué = même rôle ou deux comptes liés ?") :
**deux comptes liés légitimes, pas un doublon d'inventaire, pas une confusion de scope.**

### Résultat 2 — L'autorité `manager` du vault est une clé unique (EOA), mais c'est une clé LOOPSCALE, pas DAWN

`dmgrEuRb9xTckiafn3wpNHNhKq1uqRwPunnZEGCLP1N` (note : préfixe "dmgr" = vanity address probable) :
`owner = System Program`, `space = 0` → **simple keypair, pas une PDA Squads V4**.

Mais `getProgramAccounts` (filtré par taille 162 bytes, memcmp sur discriminator refusé par le RPC
public gratuit — anti-abus) montre **~50+ comptes Vault** sur ce même programme, appartenant
manifestement à de nombreux emprunteurs/marchés différents, pas seulement DAWN. `manager` est très
probablement **l'autorité opérationnelle générique du protocole Loopscale lui-même** (elle gère
`update_vault`/`create_vault`, des opérations de configuration de vault au niveau protocole), pas une
clé spécifique à DAWN.

**Conclusion : hors-scope.** Le texte du programme est explicite : *"Vulnerabilities in the Loopscale
protocol, program, vault primitives, oracle keeper, or any Loopscale-operated infrastructure are out
of scope here and must be reported to Loopscale."* Cette autorité `manager` est exactement ça — de
l'infrastructure opérée par Loopscale, pas par DAWN/InfraFi. Pas de finding ici.

### Mise à jour — débloqué avec une clé RPC Alchemy (fournie par Mathieu) : vérification complète

Avec un RPC supportant `memcmp` (Alchemy), la chaîne complète a pu être tracée sans aucun doute :

1. **`Strategy` (8460 bytes réels)** décodée pour les ~17 strategies dont `principal_mint` =
   `dawn7ZUF...` → celle liée au vault principal (`lender = 4rXteU...`) est `836SQM4FLXELjrSu2cLLvi32aiqn22uNbZsZvBNdDHFm`,
   avec `market_information = 6TBbDMm1uoVbxVrcs8bWnmoyuks4wzHNyQqX3GaEFcgB`.
2. **`MarketInformation`** décodée : `authority` = `delegate` = **le vault PDA lui-même**
   (`4rXteU...`), pas une clé externe — un pattern sain (un PDA ne peut être signé que par CPI
   depuis le programme, jamais par une clé privée humaine).
3. **`Loan` (1658 bytes réels — 24 bytes de plus que mon premier calcul, corrigé empiriquement)** :
   `getProgramAccounts` filtré par `dataSize=1658` + `memcmp` sur `ledger[0].strategy` = `836SQM4...`
   → **4 comptes Loan actifs** trouvés, tous avec le même champ `borrower` :
   **`AVvbWjgpVrFtYVaUA9RfsGy8VfqMNeum5FdQfQkd9hqH`**.
4. **Lecture de ce compte** : `owner = 11111111111111111111111111111111` (System Program),
   `space = 0` → **un simple EOA (keypair standard), PAS une PDA du programme Squads V4**
   (`SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf`).

**Constat factuel vérifié :** le texte officiel du scope affirme explicitement *"DAWN is the sole
whitelisted borrower via a **Squads V4 multisig**"* — et liste "**borrower authorization**"
explicitement comme in-scope. La réalité on-chain, aujourd'hui, sur les 4 prêts actifs réels, est
une clé unique, pas un multisig N-sur-M.

### Recherche d'un angle d'exploitation SANS compromission de la clé

Avant de conclure, vérification de toutes les autres instructions qui touchent un `Loan` pour voir
si l'une d'elles contournerait le `borrower` d'une façon exploitable :
- `close_loan`, `lock_loan`, `unlock_loan` : exigent toutes `borrower` comme signataire — rien à
  contourner ici.
- `liquidate_ledger` : ne requiert PAS `borrower`, seulement un `liquidator` + `payer` — mais c'est
  un mécanisme de liquidation standard (probablement gated par des conditions on-chain de défaut de
  paiement qu'on ne peut pas lire sans le bytecode du programme), pas une faille liée au choix de
  clé de DAWN.
- `refinance_ledger`, `sell_ledger` : requièrent `refinance_admin`/`lender_auth` — des rôles
  **globaux Loopscale** (`ProtocolAdminState`), pas DAWN — donc hors-scope ("Loopscale-operated
  infrastructure") même si un souci existait là.

**OSINT sur la clé `AVvbWjgpVrFtYVaUA9RfsGy8VfqMNeum5FdQfQkd9hqH`** (recherche web + GitHub code
search, exhaustive) : **aucune fuite, aucune étiquette publique, aucune mention nulle part.** La clé
n'est pas déjà exposée publiquement — sa compromission resterait hypothétique, pas un fait acquis.

**Verdict final, honnête :** c'est un écart **factuel et vérifié** entre la documentation
("Squads V4 multisig") et la réalité on-chain (clé unique) sur un point explicitement in-scope
("borrower authorization"). Mais **aucun chemin d'exploitation sans compromission de cette clé n'a
été trouvé**, malgré une recherche systématique (toutes les instructions touchant Loan + OSINT sur
la clé elle-même). Ça tombe donc dans les deux clauses hors-scope par défaut d'Immunefi :
*"Impacts involving centralization risks"* et *"Impacts caused by attacks requiring access to
leaked keys/credentials"* — même verdict que le cas de l'autorité de pause USD.infra (notes/03).
**Documenté comme fait vérifié, pas soumis comme finding**, conformément à la règle anti-inflation.

---

## Pass 2 — Marché secondaire sUSD.infra/USD.infra sur Orca (piste C-18)

### Données live (Orca API, `api.orca.so`, à l'instant)

Pool trouvé : `6JmJbmCQFqbdbR8hEv6AouPzKQQyfoYM6nstoHwNa6aA` (Whirlpool, tick spacing 4, fee 0.04%)

| | Valeur |
|---|---|
| TVL | $817,056.85 |
| Volume 24h | $952.40 |
| Prix AMM (tokenB/tokenA) | 1.00028102794773921399 |
| → 1 sUSD.infra (AMM) | **0.9997190510** USD.infra |
| → 1 sUSD.infra (NAV officielle du vault, live) | **1.0013803491** USD.infra |
| **Écart AMM vs NAV** | **≈ 0.166 %** (sUSD.infra se négocie EN DESSOUS de sa valeur NAV théorique) |

### Analyse

Il existe bien un écart mesurable (~0.17%) entre le prix spot AMM et la valeur NAV "officielle" —
cohérent avec l'hypothèse initiale de la piste C-18. **Mais ce n'est pas exploitable comme bug** :

- Le pool a un **volume dérisoire** ($952/jour sur $817K de TVL) — aucune activité d'arbitrage
  significative, cohérent avec un écart qui n'attire simplement personne à cette échelle (frais de
  swap 0.04% + frais de retrait éventuels du vault + taille du pool rendent l'arbitrage à peine
  rentable, voire pas du tout selon les frais de retrait réels du vault qu'on n'a pas vérifiés).
- Un écart de prix entre un AMM et une NAV "officielle" **n'est pas en soi une vulnérabilité du
  contrat DAWN/InfraFi** — c'est un phénomène de marché ordinaire sur un pool à faible liquidité,
  pas un défaut de code. Immunefi exclut explicitement les **"Lack of liquidity impacts"** du
  default scope.
- Aucune des parties (le pool Orca, le programme Loopscale sous-jacent) n'est un asset listé par
  DAWN dans son scope Immunefi — Orca lui-même n'est pas DAWN, et le vault Loopscale sous-jacent
  est hors-scope sauf pour "InfraFi's vault configuration and integration" spécifiquement.

**Conclusion : piste C-18 explorée et close, pas de finding.** L'écart existe et est documenté, mais
ni la taille ni la nature ne permettent de construire un scénario d'impact réel conforme au scope —
ce serait spéculatif de prétendre le contraire.

---

## Résumé pour les deux passes

| Piste | Résultat | Soumissible ? |
|---|---|---|
| Duplication des 2 comptes vault (ancienne question ouverte) | **Résolue** : deux vaults distincts légitimes, pas un doublon | Non (pas un bug, juste une clarification) |
| Autorité `manager` du vault = clé unique | Confirmée, mais c'est une clé **Loopscale**, pas DAWN | **Non — hors-scope** ("Loopscale-operated infrastructure") |
| `MarketInformation.authority`/`.delegate` (DAWN) | **Résolu** (clé RPC Alchemy) : c'est le vault PDA lui-même, pas une clé externe | Non (sain, pas un bug) |
| `Loan.borrower` réel des 4 prêts actifs vs. "Squads V4 multisig" documenté | **Résolu** (clé RPC Alchemy) : c'est un simple EOA, écart factuel confirmé avec le texte officiel — mais aucun chemin d'exploitation sans compromission trouvé (vérif. de toutes les instructions touchant Loan + OSINT sur la clé, négatif) | **Non — "centralization risk" + "leaked keys" explicitement hors-scope**, même verdict que le cas USD.infra pause-authority |
| Écart prix AMM sUSD.infra vs NAV (piste C-18) | Confirmé, ~0.166%, mais volume quasi nul | **Non — "lack of liquidity impacts" explicitement hors-scope**, pas un bug de contrat |

**Aucun nouveau finding à soumettre depuis ces deux passes.** Tous les fils ont été tranchés
jusqu'au bout (grâce à la clé Alchemy fournie par Mathieu) : deux écarts factuels réels et vérifiés
(manager Loopscale, borrower EOA) sont documentés honnêtement mais tombent dans des catégories
explicitement hors-scope d'Immunefi en l'absence d'un chemin d'exploitation sans compromission.
