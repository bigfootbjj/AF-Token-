# DAWN / InfraFi — 3 passes "12 lentilles" : vault Loopscale #1, vault #2, mint USD.infra

Suite à "on lance les 3 passes des 12 agents ailleurs" : application des 12 lentilles du scan formel
`solidity-auditor v4` sur les 3 assets restants du scope non encore passés en revue formelle :
- Asset #100745 — vault Loopscale `EZ8sq2FNnmqQo254irAMGNp7c6B7DPuKh22SyXAwuXSn` (petit vault)
- Asset #101014 — vault Loopscale `4rXteUmbxiXvgLqP14eQwtqkLyVNXVCBHnXyLQ9vZkSh` (vault principal)
- Asset #100376 — mint USD.infra `dawn7ZUF7h7anFuEsDdAU1Y3HYwikwqNMAENZsQJdNL` (Token-2022)

## Méthode — pourquoi "manuel" et pas les 12 agents littéraux

Le scan formel `solidity-auditor v4` original (sur `USDTelExchangeRate`) a pu lancer 12 agents
Claude indépendants car on disposait du **code source Solidity vérifié**. Ici :
- Le programme Loopscale est **closed-source** — on a son IDL public (interface), pas son
  implémentation Rust. Impossible de faire relire du code qui n'existe pas publiquement.
- Le mint USD.infra n'a **aucun code propre** — c'est une configuration Token-2022 standard avec
  extensions, pas un programme.

Donc, comme pour le round 1 (avant d'avoir le code BNB), application **manuelle** des 12 lentilles
contre les données réelles qu'on a pu extraire on-chain (IDL décodé, structs réels, valeurs live) —
pas contre du code qu'on ne peut pas lire. Chaque lentille est notée : FACT (vérifié on-chain), LEAD
(plausible mais non confirmable sans le code Rust), ou RAS (rien trouvé).

---

## Target A+B — Vaults Loopscale (#100745 petit vault, #101014 vault principal)

### 1. access-control-agent — FACT, déjà réglé (notes 07)
`MarketInformation.authority`/`.delegate` = le vault PDA lui-même (sain). `Loan.borrower` des 4
prêts actifs = EOA simple, pas Squads V4 (écart factuel documenté, hors-scope car nécessite
compromission — voir notes/07).

### 2. boundary-agent — FACT nouvelle : plafonds on-chain désactivés

Décodage de `MarketInformation` (`6TBbDMm1uoVbxVrcs8bWnmoyuks4wzHNyQqX3GaEFcgB`, vault principal) :

```
borrow_caps   : max_1hr=u64::MAX  max_24hr=u64::MAX  max_outstanding=u64::MAX
withdraw_caps : max_1hr=u64::MAX  max_24hr=u64::MAX  max_outstanding=u64::MAX
supply_caps   : max_1hr=u64::MAX  max_24hr=u64::MAX  max_outstanding=u64::MAX
```

**Aucun plafond on-chain actif** sur le marché de DAWN — ni par heure, ni par 24h, ni global. Pas
forcément un bug : cohérent avec l'architecture documentée où le vrai contrôle ("four-eyes approval
flow + post-time delta bounds") est **off-chain**, côté `infrafi-api`/`infrafi-manager`, pas on-chain.
**LEAD, pas FINDING** : sans le code de `infrafi-api` (hors-scope, VPN), impossible de vérifier que ce
contrôle off-chain compense réellement l'absence de plafond on-chain. Risque théorique : si jamais
l'app off-chain est bypassée (scope explicite : "Any bug that bypasses the four-eyes approval or the
post-time delta bounds" EST in-scope), rien côté contrat Loopscale n'empêche un emprunt/retrait de
taille arbitraire. **Ne pas soumettre seul** (pas une faute de code, une absence de garde-fou
on-chain dont on ne sait pas si elle est compensée ailleurs) — mais à garder en tête si jamais un bug
côté API/manager est trouvé plus tard : ce vault n'offrirait aucune seconde ligne de défense.

### 3. periphery-agent — FACT nouvelle : collatéral = NFT de position Orca Whirlpool

Décodage d'un des 4 prêts réels (`kT74jQiPF3q9AawM1YsyMg91okjiGgHigbYWQCo6Yp2`) :
- `ledger[0]` : `strategy = 836SQM4...` (vault principal), `principal_due = 180 000 000 000` (raw,
  6 décimales) = **$180 000**, `principal_repaid = 0`.
- `collateral[0]` : `asset_mint = Fu4KXG5crLV4JE977fqFVzJnXf1pp4CfT2TujUadBd3n`, `amount = 1`.

Vérifié : ce mint a `decimals=0, supply=1` — signature classique d'un **NFT de position Orca
Whirlpool** (chaque position LP = un NFT unique). Ça confirme concrètement l'usage des instructions
`manage_collateral_*_orca_liquidity` de l'IDL : le prêt de $180k est garanti par une position LP
Orca, pas par un token fongible classique.

**LEAD ouvert, pas vérifié plus loin (hors budget de cette passe)** : la vraie valeur de cette
position (liquidité sous-jacente, range de prix, risque d'impermanent loss) n'a pas été calculée —
nécessiterait de dériver le compte Whirlpool Position associé au NFT et faire le calcul
tick-to-price. **Je n'affirme ni ne infirme que le collatéral couvre bien les $180k** — à creuser si
tu veux pousser ce fil (nouvelle sous-tâche, pas incluse dans les "3 passes" demandées).

### 4. invariant-agent — LEAD (non vérifiable) : 27 actifs collatéraux partagent le même oracle

`MarketInformation.asset_data[1..27]` (27 entrées non-nulles) pointent **toutes vers le même compte
oracle** `H84M3es89eLfGRDhUFxo7xgTQmhzAx4h2oBexU7WNiGN`. Si c'est un agrégateur multi-actifs qui
résout correctement par actif, aucun souci. Si c'est un flux de prix unique appliqué uniformément à
27 actifs différents, ce serait une erreur de configuration sérieuse. **Impossible de trancher sans
lire le programme de cet oracle** (hors-scope de toute façon : c'est la configuration du marché
Loopscale, pas celle de DAWN — "Loopscale... its oracle keeper... out of scope"). Noté pour mémoire,
pas creusé davantage (budget).

### 5-12. economic-security / execution-trace / flow-gap / trust-gap / first-principles / asymmetry / math-precision / numerical-gap

**Aucun verdict possible sans le bytecode/source Rust du programme Loopscale.** Ces lentilles
nécessitent de lire la LOGIQUE des instructions (calculs d'intérêts, vérifications d'invariants,
séquences d'appels) — l'IDL ne donne que les noms de comptes/paramètres, pas le code. Honnêtement :
**RAS, pas par manque d'effort mais par absence totale d'accès au code source** (programme
closed-source, seul l'IDL est public). Precedent déjà établi : le programme Loopscale et son
intégration ont un bug bounty séparé chez Loopscale lui-même pour cette raison précise.

---

## Target C — Mint USD.infra (Token-2022)

### Extensions re-vérifiées en direct (aucun changement depuis notes/03)

```
mintAuthority   : Am4facCvkQkHjwSArPX8Jqxs1ss14XMoC8JkTV3BDG95 (PDA M0, hors-scope)
freezeAuthority : 4X9oEExyxYVzWzXWame931CCAF7XbgCbp9ZKg4ECW4Hi (EOA simple, déjà documenté)
Extensions      : metadataPointer, transferHook (programId: null — inactif), pausableConfig
                  (paused: false), tokenMetadata. AUCUNE extension supplémentaire.
```

**Vérification spécifique de cette passe (nouveau) : pas de `permanentDelegate`, pas de
`interestBearingConfig`, pas de `defaultAccountState`, pas de `nonTransferable`.** C'est le point le
plus important à vérifier pour un mint Token-2022 (un `permanentDelegate` actif serait critique —
transfert/burn arbitraire de n'importe quel solde par l'autorité). **Confirmé absent.** Rien de
nouveau par rapport à notes/03 : le seul écart déjà connu (autorité unique vs "Squads V4 multisig"
documenté) reste la même conclusion — hors-scope (centralization risk / leaked keys).

---

## Résumé des 3 passes

| Target | Nouveau FACT | Nouveau LEAD (non tranché) | Soumissible ? |
|---|---|---|---|
| Vault principal (#101014) | Caps borrow/withdraw/supply = u64::MAX (aucun plafond on-chain) | Compensé par le contrôle off-chain ou pas ? Inconnu (code infrafi-api hors-scope) | Non seul — à surveiller si un bug API est trouvé ailleurs |
| Vault principal (#101014) | Collatéral réel = NFT de position Orca Whirlpool (confirmé, $180k de principal sur ce prêt) | Valeur réelle de la position non calculée | Non — pas assez pour conclure, piste ouverte si tu veux pousser |
| Vault principal (#101014) | 27 actifs collatéraux partagent un seul compte oracle | Agrégateur correct ou mauvaise config ? Non vérifiable (code Loopscale fermé) | Non — hors-scope Loopscale de toute façon |
| Petit vault (#100745) | Même architecture, pas de différence notable trouvée | — | — |
| Mint USD.infra (#100376) | Confirmé : pas de `permanentDelegate`/`interestBearing`/autres extensions dangereuses | — | Rien de nouveau, RAS |

**Aucun nouveau finding soumissible issu de ces 3 passes.** Le programme Loopscale étant
closed-source, la majorité des lentilles (économique, exécution, mathématique) ne peuvent tout
simplement pas être évaluées sans son code — ce n'est pas une limite de cette session, c'est une
limite structurelle du scope (code non public, bug bounty séparé chez Loopscale pour son propre
programme). Deux pistes restent ouvertes si tu veux aller plus loin : (1) calculer la vraie valeur de
la position Orca Whirlpool collatéralisant le prêt de $180k, (2) vérifier la nature exacte de
l'oracle partagé par 27 actifs — aucune des deux n'est à coût zéro garanti (calculs Whirlpool
non-triviaux pour la première, programme oracle potentiellement fermé pour la seconde).
