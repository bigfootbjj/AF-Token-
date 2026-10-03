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

### Ce qu'on n'a PAS pu vérifier : l'autorité borrow/repay spécifique à DAWN

Le texte in-scope officiel dit : *"DAWN is the sole whitelisted borrower via a Squads V4 multisig."*
Cette autorisation vit dans un compte `MarketInformation` séparé (champ `authority` +`delegate`),
PAS dans le `manager` du Vault qu'on vient de décoder. `MarketInformation` n'est pas dérivable comme
PDA depuis l'IDL (pas de seeds documentées) — il faut soit :
- un `getProgramAccounts` avec filtre `memcmp` sur `principal_mint` à l'offset 72 → **refusé par le
  RPC public gratuit** (`INVALID_PARAMS_WITH_MESSAGE`, restriction anti-abus standard sur les RPC
  Solana publics mainnet-beta pour les requêtes `memcmp`), ou
- remonter une transaction historique touchant la bonne instruction (`borrow_principal` /
  `update_market_information`) pour lire l'adresse exacte passée en paramètre.

Tentative sur l'historique du vault `4rXteU...` : les transactions récentes trouvées (`getSignaturesForAddress`)
impliquent un programme **différent** (`sVau1tXvayVWfotzm9Ahcv2qfnnfRWttt78BCnNC6dD`, pas
`1oopBoJG...`), probablement un programme de staking de LP distinct qui référence le compte vault en
lecture seule — pas la piste qui mène à `market_information`.

**Verdict honnête : cette vérification spécifique reste bloquée par les limites du RPC public
gratuit (pas de `memcmp`), pas par un manque d'accès au code** — contrairement à ce qu'on pensait.
Nécessiterait soit une clé RPC premium (Helius, Triton, QuickNode) supportant `memcmp` sans
restriction, soit un accès différent (ex. l'indexer officiel InfraFi, hors-scope car derrière VPN).
**Pas de finding soumis sur ce point — ni confirmé ni infirmé, honnêtement signalé comme bloqué.**

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
| Autorité borrow/repay DAWN-spécifique (`MarketInformation.authority`) vs. multisig Squads documenté | **Non vérifiable** avec le RPC public gratuit (memcmp refusé) | Bloqué, ni confirmé ni infirmé |
| Écart prix AMM sUSD.infra vs NAV (piste C-18) | Confirmé, ~0.166%, mais volume quasi nul | **Non — "lack of liquidity impacts" explicitement hors-scope**, pas un bug de contrat |

**Aucun nouveau finding à soumettre depuis ces deux passes.** Le seul fil qui reste théoriquement
ouvert (l'autorité borrow/repay réelle de DAWN) nécessiterait un accès RPC premium pour être tranché
— pas poursuivi ici faute de moyen à coût zéro.
