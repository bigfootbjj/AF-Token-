# DAWN / InfraFi — Immunefi — Ingestion & Pistes (v7.2 + solidity-auditor v4)

Statut : session 1, ingestion. Aucune attaque tentée (pas de source/réseau). Toute cellule ci-dessous est **NON ATTAQUÉE**.

## 0. Ce qui bloque une vraie attaque (à lever avant tout PoC)

- Réseau sortant de cet environnement : seul `github.com` passe. `immunefi.com`, `bscscan.com`, `solscan.io`, les RPC Solana/BSC sont rejetés (`EGRESS_BLOCKED`/403). Impossible de lire le code vérifié du contrat BNB, l'état on-chain du vault Solana, ou la page scope Immunefi elle-même depuis ici.
- `LoopscaleLabs/loopscale-program-library` est **privé** (confirmé : `git clone` demande des identifiants). On n'a donc le code Loopscale qu'au travers des PDF d'audit (voir §2) — jamais le source complet, et de toute façon le programme Loopscale lui-même est hors-scope pour ce bounty.
- Aucun repo public trouvé pour `infrafi-api`, `infrafi-web`, l'indexer ou le contrat BNB publisher (recherche web négative). Sans ces sources, aucune des lentilles PoC-tracé (L1,L2,L5,L6,L7,L10,L12,L13,L15,L16,L18...) n'est attaquable — seule une analyse de confiance/architecture est possible.

**Pour débloquer** (au choix, non exclusif) :
1. Élargir l'accès réseau de l'environnement (bscscan.com, api.bscscan.com, solscan.io, api.mainnet-beta.solana.com, immunefi.com) via Settings → Network access.
2. Si Mathieu a un accès (chercheur enregistré au programme) aux repos privés InfraFi (infrafi-api/infrafi-web/indexer/contrats), les attacher avec `add_repo` — c'est le déblocage le plus utile, bien plus que le simple accès explorer.
3. À défaut, coller/uploader : code vérifié du contrat BNB (ou son implémentation si proxy), dump JSON du compte/IDL Solana du vault, liste exacte des 6 assets de la page scope Immunefi.

## 1. Cadrage (Étape 1-3, RÈGLE 3)

**Assets confirmés (4/6)** — adresses on-chain extraites de tes fichiers :
| # | Type | Identifiant |
|---|---|---|
| 1 | Solana account (Loopscale DAWN vault) | `4rXteUmbxiXvgLqP14eQwtqkLyVNXVCBHnXyLQ9vZkSh` |
| 2 | Solana account (non identifié — probablement mint config / pause authority / strategy PDA) | `EZ8sq2FNnmqQo254irAMGNp7c6B7DPuKh22SyXAwuXSn` |
| 3 | BNB Chain contract (exchange-rate publisher) | `0x15a6f1f2705b3916b5b1d2b19b10f320778744c1` |
| 4 | SPL Token-2022 mint (USD.infra) | `dawn7ZUF7h7anFuEsDdAU1Y3HYwikwqNMAENZsQJdNL` |

**2 assets manquants** (la page annonce 6 au total) — très probablement `infrafi-api` et `infrafi-web` comme assets "Websites and Applications". **Ne pas déclarer la cible "épuisée" sans ces 2 assets** (leçon Intuition, RÈGLE 9 dernier point).

**Primacy of Rules.** PoC obligatoire à toute sévérité. Repeatable Attack Limitation : seule l'attaque initiale compte si le contrat est pausable/upgradable (100% puis -50%/72h). Disclosure catégorie 2 (notice requise). Pas de KYC.

**Known issues (donc hors scope, ne jamais les re-soumettre)** :
1. JWT en localStorage côté manager (XSS trade-off derrière le VPN).
2. `ripcord` = signal de coordination, PAS un coupe-circuit — l'API ne bloque rien quand il est `true`.
3. Pas de fenêtre anti-rejeu/timestamp sur la signature du webhook Slack interactif (mitigé par un garde d'idempotence qui rend le replay neutre côté état).
4. Admin par défaut `admin@usd.tel` seedé au premier boot (rotation par process, pas par code).
5. Rôle admin plat dans infrafi-manager — la séparation des pouvoirs vient du flux Slack, pas d'un RBAC.

**Hors-scope structurel** : programme/oracle Loopscale, Token-2022 core, Squads V4, Pyth/Chainlink, libs tierces ; infrafi-manager et l'indexer tant qu'ils restent derrière le VPN ; tout ce qui exige la compromission d'un opérateur/Slack/clé multisig/co-signataire Loopscale.

**En scope explicite malgré le VPN** (texte du programme, à retenir comme angle n°1) :
> "Any bug that bypasses the four-eyes approval or the post-time delta bounds. Any path that lets deal valuations (or borrow/repay / mutations) be executed or manipulated without the trusted-operator role."

C'est la phrase la plus importante du dossier : le programme nous dit lui-même où chercher.

## 2. Audits publics ingérés (anti-doublon, RÈGLE 3 Étape 0)

Dépôt `LoopscaleLabs/audits` (public, cloné). 10 rapports PDF Adevar Labs / Offside / Highland sur le programme Loopscale (pas InfraFi). Lus :

- **Exponent LP Pricing Audit (Offside, Oct 2025)** — 1 Medium, *Fixed* : mauvais taux de change SY→underlying dans `get_exponent_lp_token_price_with_quantity` (oracle.rs/exponent_lp.rs). Corrigé avant le hack Loopscale d'avril 2025 (RateX PT mispricing, $5.8M) — mécanisme voisin mais pas identique ; les deux confirment que la pricing logic des LP tokens tiers est un point chaud historique chez Loopscale.
- **Tokenized Vault LPs (Adevar, Dec 2025)** — 0 finding. Diff vault/oracle : `Strategy::fetch_pda` dérive désormais la PDA depuis le vault, `get_net_asset_amount` lie lender+nonce au vault. Pertinent : confirme que le NAV du vault DAWN dépend d'un couple (vault, strategy, oracle_account) lié par PDA — à vérifier côté InfraFi que l'intégration ne contourne pas ce lien.
- **Oracle Integrations / "Admin Security" (Adevar, May 2026)** — 1 Low *Fixed* : `MarketInformation.authority` incohérent cassait le flux de timelock sur collatéral externe après rotation de `operations_admin` ; + 1 enhancement sur `CreateMarketInformation` vs pattern `protocol_admin`. **Pattern à retenir** : Loopscale a déjà eu des bugs de rôle-admin incohérent entre instructions migrées — si InfraFi réplique un pattern similaire (ex. `operations_admin` côté infrafi-manager vs une autorité on-chain différente), c'est un angle L7/P6 direct.
- **Token2022 Transfer Hook Support (Adevar, Nov 2025)** — 2 Low *Fixed* : (L01) fee différée non vérifiée à l'intégration du marché ; (L02) `withheld_amount > 0` pouvait bloquer liquidation/retrait. Sans impact direct sur USD.infra (qui utilise l'extension Pausable, pas TransferHook/TransferFee a priori — **à confirmer**, cf. piste P-04).

Non lus en détail (hors sujet DAWN : BEAM est un produit distinct, Highland = asset integration générique) : BEAM Adevar ×3, Loopscale Periphery (Asset Integrations/Collateral Rollover/Borrow Caps), Highland (Asset Integration). Skimés par le titre seulement — à rouvrir seulement si une piste y renvoie explicitement.

**Aucun audit public ne couvre infrafi-api/infrafi-web/indexer/le publisher BNB** — c'est la zone non auditée, donc la plus dense en attente (cf. table de rendement du prompt : "Fee/reward/incentive math" et "Consensus/cross-layer" sont les deux familles au meilleur taux de conversion H/C, et c'est exactement le off-chain path de DAWN).

## 3. Carte des frontières de confiance (Principe A — invariant-first)

```
[infrafi-manager] --(Slack four-eyes, hors-bande)--> [change-request appliqué]
        |                                                      |
        v                                                      v
[infrafi-api] --lit état vault Loopscale (Solana)--> calcule NAV = TVL/LP supply
        |                                                      |
        |--reporte valorisations deal--> [Loopscale vault] (DAWN = seul emprunteur, via Squads V4)
        |
        '--publie exchange rate + ripcord--> [BNB exchange-rate publisher contract]
                                                      |
                                                      v
                                        sanity check "growth bound" --> stocké pour oracle/partenaires
```

**Invariants de valeur (3-6 lignes, à casser) :**
1. `exchange_rate publié on-chain == f(TVL_Loopscale, LP_supply)` au moment de la lecture, sans dérive de staleness au-delà de la fenêtre documentée.
2. Toute valorisation de deal qui modifie le NAV a été approuvée four-eyes **et** respecte les post-time delta bounds — aucun chemin ne doit pouvoir faire l'un sans l'autre.
3. `ripcord=true` est un signal, pas un verrou — donc aucun invariant de sécurité ne doit *dépendre* de son enforcement (sinon c'est un faux sentiment de sécurité, cf. known issue #2).
4. Les deux leviers d'urgence (pause vault Loopscale, pause globale USD.infra Token-2022) sont indépendants — rien ne garantit leur atomicité.
5. Le compte Solana `EZ8sq2...` (rôle à confirmer) doit être lié par PDA/seeds au vault DAWN, pas substituable par un autre compte de structure identique (P9/L2 Solana).

## 4. Pistes (format RÈGLE 7) — à attaquer dès que source/réseau disponible

### PISTE P-01 — Bypass du four-eyes / post-time delta bounds sur le reporting de valorisation
Lentille : **L7** (param privilégié / self-dealing) + **L2** (donnée off-chain non cross-checkée on-chain).
Modalité : PoC-tracé. Forme min : 2 acteurs (operator proposant, signataire Slack) + 1 séquence où la valorisation effectivement poussée à Loopscale diverge de celle approuvée, ou où plusieurs deltas "acceptables" individuellement s'enchaînent pour dépasser la borne cumulative voulue.
Statut : NON ATTAQUÉE (besoin du source infrafi-api / infrafi-manager pour localiser la fonction de reporting et la vérif de delta).
Pourquoi prioritaire : **explicitement désigné in-scope par le programme lui-même**, derrière le VPN ou non. C'est l'angle EV le plus élevé du dossier.

### PISTE P-02 — Lecture non-finalisée de l'état Solana avant publication BNB (staleness/reorg cross-layer)
Lentille : **L13** (chemin repair/reconcile acceptant des données périmées) + **L10** (donnée de relayer non authentifiée traitée comme vérité) + **L11** (cross-archi).
Hypothèse : si `infrafi-api` lit le vault Loopscale à un commitment `processed`/`confirmed` plutôt que `finalized`, un reorg/fork Solana pourrait faire publier sur BNB Chain (immuable une fois publié) un NAV issu d'un état invalidé, et le "growth sanity check" ne le détecterait pas s'il reste dans la fourchette plausible.
Modalité : PoC-tracé différentiel (2 lectures du même slot avant/après confirmation).
Statut : NON ATTAQUÉE — nécessite le source infrafi-api (quel commitment level ?) et idéalement accès RPC pour observer un cas réel de fork.
Angle Track A (cross-layer) — ton edge déclaré, exempté du filtre de saturation.

### PISTE P-03 — Non-atomicité des deux leviers d'urgence
Lentille : **L18** (effet persiste malgré l'absence de synchronisation) + **L4** (dépendance externe fait revert/diverger un flux légitime).
Hypothèse : pause du vault Loopscale sans pause simultanée d'USD.infra (ou l'inverse) laisse une fenêtre où un flux (dépôt/retrait/transfert) se règle sur un taux de change gelé ou incohérent.
Statut : NON ATTAQUÉE — besoin de voir qui détient l'autorité de pause de chaque côté et l'ordre d'opérations réel.

### PISTE P-04 — Extension Token-2022 réellement active sur USD.infra
Lentille : **L1** (respect des préconditions du code tiers).
Hypothèse à vérifier en premier (gratuite, dès que Solscan/RPC accessible) : USD.infra utilise Pausable — confirmer qu'aucune autre extension (TransferFee, TransferHook, dont les audits Loopscale montrent des bugs passés côté Loopscale lui-même) n'est activée, ce qui changerait toute la surface.
Statut : NON ATTAQUÉE (lecture simple du mint, bloquée par le réseau).

### PISTE P-05 — Rôle du second compte Solana `EZ8sq2FNnmqQo254irAMGNp7c6B7DPuKh22SyXAwuXSn`
On ne sait pas encore ce que c'est (mint config ? pause authority ? strategy PDA ?). Tant qu'il n'est pas identifié, l'inventaire des 6 assets n'est pas complet (règle Intuition).
Statut : NON ATTAQUÉE / NON IDENTIFIÉ.

## 5. Matrice lentilles × composants (état actuel)

| | infrafi-api (reporting/NAV) | publisher BNB | vault Loopscale (intégration) | USD.infra mint | infrafi-web/API publique |
|---|---|---|---|---|---|
| L1 | NON ATTAQUÉE | NON ATTAQUÉE | NON ATTAQUÉE | P-04 ouverte | NON ATTAQUÉE |
| L2 | P-01 | — | P-05 | — | NON ATTAQUÉE |
| L7 | P-01 | — | — | — | — |
| L9 | — | à ouvrir (domaine du growth-bound) | — | — | — |
| L10 | P-02 | — | — | — | — |
| L13 | P-02 | — | — | — | — |
| L18 | — | — | P-03 | P-03 | — |
| Reste (L3,L5,L6,L8,L12,L14-L17) | jamais structurée | jamais structurée | jamais structurée | jamais structurée | jamais structurée |

Matrice **très loin d'être pleine** — normal, aucune source lue. Prochaine action dès déblocage : ouvrir une passe dédiée par lentille non utilisée, pas suivre uniquement P-01/P-02.

## 6. solidity-auditor v4

Cloné (`/home/user/pashov/skills`, VERSION=4), prêt à tourner dès qu'on a un fichier `.sol` réel à scanner — concrètement le contrat BNB publisher (seul composant EVM/Solidity du scope). Dès que son code est disponible (verified source BscScan ou fourni par Mathieu), on le dépose dans `audits/dawn-infrafi/sources/` et on lance le skill dessus en complément du passage manuel v7.2 (le skill ne couvre que le Solidity — Rust/Solana reste entièrement sur la grille L1-L18 manuelle).
