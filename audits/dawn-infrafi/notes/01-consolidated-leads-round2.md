# DAWN / InfraFi — Consolidation des 12 lentilles (solidity-auditor v4, adapté no-source)

Source : 12 agents parallèles (Access Control, Economic Security, Execution Trace, First Principles,
Invariant, Math Precision, Periphery, Asymmetry, Boundary, Flow Gap, Numerical Gap, Trust Gap),
chacun appliqué à l'architecture DAWN documentée (aucun code source disponible). ~95 LEAD bruts produits.
Ci-dessous : dédupliqué par mécanisme, classé par convergence (nombre de lentilles indépendantes qui
retombent sur le même angle — signal de robustesse, pas une preuve) et par alignement avec le texte
de scope explicite du programme. Tout reste **NON ATTAQUÉ** : zéro FINDING, zéro PoC — on n'a pas de
code. Chaque piste porte ses `needs_source` consolidés.

## Tableau de convergence (tri par nombre de lentilles)

| Piste | Mécanisme | Lentilles convergentes | Scope explicite ? |
|---|---|---|---|
| **C-01** | Les 2 comptes Solana "vault" (#100745 `EZ8sq2...` / #101014 `4rXteU...`) ont une description officielle identique — rôle réel non tranché | Access Control, Asymmetry, Trust Gap, Execution Trace, First Principles, Boundary, Economic Security | Indirect (asset en scope) |
| **C-02** | Growth-sanity-check BNB probablement vérifié pas-à-pas (dernier taux publié), jamais sur fenêtre cumulée → petits pas répétés contournent la borne | Math Precision, Invariant, Numerical Gap, Access Control (P-01), Trust Gap, Economic Security | **Oui** — "any path to posting a manipulated ... rate" |
| **C-03** | `exchange_rate = TVL/LP_supply` lu en 2 appels RPC non-atomiques (comptes séparés) → ratio "torn" jamais réel à aucun slot | First Principles, Execution Trace, Numerical Gap, Flow Gap | Non direct, mais sous-tend tout le NAV publié |
| **C-04** | Pause vault Loopscale et pause globale USD.infra Token-2022 : autorités et couverture non garanties identiques/synchrones | Invariant, Execution Trace, Economic Security, Asymmetry, Trust Gap, Flow Gap | Oui (P-03 déjà ouverte, très affinée) |
| **C-05** | Delta bound sur la valorisation de deal vérifié par-mutation, pas cumulé/fenêtré → N petites valorisations four-eyes-approuvées composent un déplacement non borné | Access Control, Invariant, Asymmetry, Trust Gap, Economic Security | **Oui** — "any bug that bypasses ... the post-time delta bounds" |
| **C-06** | Ripcord (flag off-chain) et growth-sanity-check (on-chain BNB) sont deux implémentations indépendantes de la même règle de plausibilité, jamais garanties synchrones ; et le bit ripcord n'est probablement jamais transmis au contrat BNB | Invariant, Flow Gap, Trust Gap, First Principles | Oui — "any path to posting a manipulated or ripcord-blocked rate" |
| **C-07** | Four-eyes basé sur rôle plat (known issue) sans vérification cryptographique que l'approbateur Slack ≠ le proposant — auto-approbation possible par un seul opérateur | Access Control, Trust Gap | Oui (contournement du four-eyes) |
| **C-08** | TOCTOU entre approbation Slack (hors-bande, délai arbitraire) et écriture/exécution on-chain réelle — la référence du delta-bound a pu bouger entre-temps | Execution Trace, Invariant, Trust Gap | Oui |
| **C-09** | Encodage cross-chain Solana→BNB du taux : décimales SPL vs EVM, endianness Borsh→ABI, coercion de valeur dégénérée (NaN/div-par-zéro) en entier avant publication | Math Precision, Periphery | Oui ("staleness/validation" de l'asset BNB) |
| **C-10** | Idempotence du webhook Slack protège l'état interne mais peut-être pas la création de proposition Squads V4 → une approbation = potentiellement 2 propositions exécutables | Flow Gap (seul, mais mécanisme précis et nouveau) | Oui (distinct du known issue replay, qui ne couvre que la resignature) |
| **C-11** | DAWN est à la fois le seul emprunteur ET la partie qui valorise son propre collatéral (aucune source de prix tierce documentée) — désalignement structurel, pas juste un bug ponctuel | Economic Security (seul, mais argument de fond) | Oui (valorisation manipulable) |
| **C-12** | Ripcord lisible publiquement (`GET /nav/*`) pendant que le chemin de rachat reste ouvert → un déposant informé sort avant la correction four-eyes, perte reportée sur les LP restants | Economic Security (seul) | Oui — exploitation active du known issue #2, pas une resoumission |
| **C-13** | Genesis / reset du growth-sanity-check : pas de valeur précédente (déploiement) ou valeur précédente à zéro → première publication ou publication post-reset sans borne réelle | Math Precision, Boundary | Oui |
| **C-14** | Confused deputy : infrafi-manager/infrafi-api pourrait détenir un signataire qui exécute directement les actions Squads-gated au lieu de seulement les proposer | Access Control (seul) | Oui (borrow/repay, pause) |
| **C-15** | Autorité de configuration du growth-bound (paramètre) potentiellement distincte de l'autorité de publication du taux — rotation désynchronisée (écho direct d'un bug Loopscale déjà confirmé : `operations_admin` incohérent) | Asymmetry (seul, mais corpus direct) | Oui |
| **C-16** | `/health` superficiel (process seulement) pourrait masquer une panne de lecture vault ou de publication BNB | Boundary (seul) | Oui (griefing/DoS partiel) |
| **C-17** | Indexer (source de LP_supply ou de data points) asynchrone et multi-provider — dédup/checkpoint non garanti au failover, latence vs lecture TVL en direct | Periphery, Flow Gap | Non direct (indexer nominalement hors-scope VPN) mais effet visible via infrafi-api |

## Les 3 pistes à vérifier EN PREMIER (coût ~0, pas besoin de code source)

1. **C-01** — résoudre l'identité des 2 comptes Solana. Dès que le réseau Solana (RPC ou Solscan) est
   accessible : `getAccountInfo` + décodage Anchor IDL (fetchable on-chain, le programme le confirme)
   sur `EZ8sq2FNnmqQo254irAMGNp7c6B7DPuKh22SyXAwuXSn` et `4rXteUmbxiXvgLqP14eQwtqkLyVNXVCBHnXyLQ9vZkSh`.
   Sept lentilles différentes buttent sur cette ambiguïté — la lever débloque C-01, C-03, C-05, C-08.
2. **C-04 / C-15** — lire l'autorité de pause du mint Token-2022 USD.infra (`dawn7ZUF...`) et la comparer
   à l'adresse du compte Squads V4 utilisé pour borrow/repay. Lecture on-chain simple, aucune source requise.
3. **C-13** — lire l'état actuel du contrat BNB publisher (`0x15a6f1f2705b3916b5b1d2b19b10f320778744c1`)
   sur BscScan : code vérifié ? valeur "previous rate" actuelle ? Si vérifié, ça répond en même temps à
   C-02, C-09, C-13, C-15 sans avoir besoin d'infrafi-api.

## Ce qui reste bloqué sur du code source (infrafi-api / infrafi-manager / indexer)

C-05, C-06 (côté off-chain), C-07, C-08, C-10, C-11, C-12, C-14, C-16, C-17 — tous nécessitent au minimum
la logique de validation côté Rust/Axum, inaccessible tant que les repos restent privés ou que le réseau
ne permet pas d'atteindre `api.infrastructure.finance`.

## Mise à jour de la matrice lentilles × composants (remplace la matrice v1 du fichier 00)

| | infrafi-api (reporting/NAV) | publisher BNB | vault Loopscale (intégration) | USD.infra mint | infrafi-manager (four-eyes) | infrafi-web/API publique |
|---|---|---|---|---|---|---|
| L1 (préconditions tiers) | C-03 | C-13 | C-01 | — | — | NON ATTAQUÉE |
| L2 (données non cross-checkées) | C-01, C-09 | C-09 | C-01 | — | — | NON ATTAQUÉE |
| L7 (self-dealing) | C-05, C-11 | — | — | — | C-07 | — |
| L9 (domaine ratio) | C-03 | C-02, C-13 | — | — | — | — |
| L10 (relayer non-authentifié) | C-06 | — | — | — | — | — |
| L13 (repair/stale) | C-03 | — | — | — | — | — |
| L18 (inclusion/exécution découplées) | — | C-06 | — | C-04 | C-10 | — |
| Access/trust (hors L1-L18, ajouté par les agents) | C-14 | C-15 | C-01 | C-04 | C-07, C-08, C-10 | C-16 |
| Reste (L3,L5,L6,L8,L11,L12,L14-L17) | jamais structurée | jamais structurée | jamais structurée | jamais structurée | jamais structurée | jamais structurée |

Matrice toujours loin d'être pleine (normal, sans source). Les 17 pistes consolidées couvrent large mais
restent toutes NON ATTAQUÉES par la modalité requise — inspection architecturale seulement, jamais PoC.

## Règle de non-régression (RÈGLE 9 / anti-faux-négatif)

Aucune de ces 17 pistes ne doit être close ou dégradée en "self-harm/admin-trusted/scope" sans le check
concret de RÈGLE 5 — en particulier C-05/C-07/C-08/C-11 impliquent des acteurs *supposés* de confiance,
mais chacun nuit potentiellement à AUTRUI (les LP/déposants) dans son mécanisme décrit, ce qui les garde
en scope selon le texte même du programme.
