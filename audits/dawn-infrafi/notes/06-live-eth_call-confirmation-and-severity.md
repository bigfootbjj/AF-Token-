# DAWN / InfraFi — Confirmation finale par `eth_call` live + conclusion de sévérité

Suite à la demande : *"on pousse plus loin la recherche du consommateur downstream, et on confirme
la sévérité"*. Deux volets : (A) recherche du consommateur downstream du taux BNB, (B) confirmation
finale, avec les vrais chiffres actuels, que le bug Finding 1 est actif en ce moment même.

## A. Recherche du consommateur downstream — résultat : NÉGATIF (documenté honnêtement)

Pistes épuisées, toutes négatives :
- **BscScan API** : bloquée (redirection Cloudflare via le proxy), Etherscan v2 unifié refuse l'accès
  gratuit pour la chain BSC (`"Free API access is not supported for this chain"`).
- **GitHub code search** (`DAWN`, `USD.infra`, `USDTelExchangeRate`, adresse du contrat) : aucun
  résultat pertinent en dehors de nos propres fichiers d'audit.
- **DefiLlama** : aucun pool BNB Chain associé à DAWN / USD.infra / Loopscale.
- **WebSearch** : uniquement des mentions génériques de "marchés de prêt Solana", aucun lien concret
  avec BNB Chain.
- **API `api.infrastructure.finance`** : `/openapi.json` (public, non authentifié) liste toutes les
  routes exposées. Aucune route ne concerne BNB/BSC. Test direct de `{network}` = `bnb`, `bsc`,
  `bnbchain`, `ethereum` sur `/vault/{network}/nav` → systématiquement `"Bad request: Invalid
  network"`. Seul `solana` est un réseau valide pour cette API.

**Conclusion A :** aucun consommateur on-chain ou off-chain du taux publié sur BNB Chain n'a pu être
identifié avec les moyens d'OSINT disponibles. Ceci est documenté comme un point d'incertitude
persistant, pas comme une preuve d'absence — conformément à la règle anti-fabrication : on ne
prétend pas qu'il n'existe aucun consommateur, seulement qu'on n'en a trouvé aucun.

## B. Preuve matérielle que le bug est actif MAINTENANT (pas hypothétique)

### B.1 — Le vrai taux n'a JAMAIS atteint le taux publié, à aucun moment de l'historique

Historique complet récupéré via `GET /vault/solana/nav/history` (15 points, du genesis
2026-09-19 à aujourd'hui 2026-10-03) :

| | Valeur |
|---|---|
| Taux réel actuel (`/vault/solana/nav`, live) | **1.0013803491389677** (snapshot 2026-10-03T18:01:50Z) |
| Taux réel MAXIMUM jamais atteint (tout l'historique) | **1.0013803491389677** (= aujourd'hui, le point le plus haut jamais enregistré) |
| Taux réel MINIMUM (genesis) | 1.000000032174443 |
| Taux publié sur BNB Chain (`getExchangeRate()`, live, relu à l'instant) | **1.0095655102813623**, inchangé depuis le **2026-08-06T00:00:20Z** |

Le taux publié sur BNB Chain est donc **supérieur à la plus haute valeur jamais atteinte par le vrai
vault, à tout moment de son histoire connue** — y compris aujourd'hui, son point le plus haut à ce
jour. Ce n'est plus une hypothèse ("si jamais la NAV baisse un jour") : le taux publié est **déjà
faux et surévalué, maintenant**, et ce depuis le début de l'historique mesurable du vault (le taux
BNB date d'avant même le genesis Solana enregistré par l'API).

### B.2 — Simulation `eth_call` en lecture seule : la correction honnête est bloquée, maintenant

Calcul du taux réel actuel à l'échelle 1e18 :
```
1.0013803491389677 * 1e18 = 1001380349138967700
                           = 0x0de59e1f3b7c1c94 (hex, 32 bytes padded)
```

Calldata construit avec `cast calldata "setExchangeRate(uint128)" 1001380349138967700` :
```
0x530a09e40000000000000000000000000000000000000000000000000de59e1f3b7c1c94
```

**Appel `eth_call` (lecture seule, aucune transaction diffusée, aucun état modifié — conforme à la
règle "pas de test sur mainnet déployé")**, simulant le VRAI updater actuel tentant de publier le
VRAI taux actuel, à l'instant :

```
from: 0x7ad7eee24ace80bb84d1bd8fe5798b852eaa0718   (le vrai _updater() actuel)
to:   0x15a6f1f2705b3916b5b1d2b19b10f320778744c1   (le vrai contrat déployé)
data: 0x530a09e40000000000000000000000000000000000000000000000000de59e1f3b7c1c94
```

Résultat, confirmé **indépendamment sur 4 fournisseurs RPC publics différents** (nodereal,
publicnode, defibit, bsc-dataseed) :

```
{"error":{"code":3,"message":"execution reverted: 0x6143ab0a","data":"0x6143ab0a"}}
```

`0x6143ab0a` = `cast sig "ExchangeRateDecreased()"` → confirmé, c'est exactement le même selector.

État on-chain relu au même moment (`getExchangeRate()`, calldata `0xe6aa216c`) :
```
rate      = 0x0e02b27b91ce7b7c = 1009565510281362300 (1.0095655102813623) — inchangé
timestamp = 0x6a73ce94         = 1785974420 (2026-08-06T00:00:20Z)        — inchangé depuis 58+ jours
```

**Ce que ça prouve concrètement :** si le service de publication (qui détient la vraie clé
`_updater`, sans aucune compromission) essayait AUJOURD'HUI de publier le vrai taux actuel du vault
(1.00138) pour remplacer la valeur obsolète et déjà trop haute (1.00957), l'appel échouerait
systématiquement avec `ExchangeRateDecreased()`. Il n'existe aucune fonction alternative
(`setUpdater`, `transferOwnership`, `renounceOwnership`, handover 2 étapes du owner Gnosis Safe) qui
permette de modifier `_exchangeRate` autrement que par `setExchangeRate`. Le défaut est donc
**permanent et sans contournement on-chain**, et **actif dès aujourd'hui**, pas seulement dans un
scénario futur hypothétique.

## Conclusion de sévérité (honnête, ni gonflée ni minimisée)

**Ce qui est prouvé avec des données réelles, pas des hypothèses :**
1. Le taux publié est факtuellement déjà trop haut par rapport à la réalité du vault, depuis le début
   de l'historique connu, et le restera tant qu'aucune mise à jour corrective n'est tentée.
2. Toute tentative de correction, avec la vraie clé légitime et le vrai chiffre actuel, échoue
   actuellement et échouera pour toujours tant que le vrai taux reste sous 1.00957 — ce qui est
   actuellement le cas avec une marge confortable (écart ≈ 0.82%).
3. Il n'existe, par conception du contrat, **aucun chemin de correction on-chain**, quel que soit
   l'acteur (updater, owner, Gnosis Safe multisig).

**Ce qui reste non prouvé, honnêtement signalé :**
- Aucun consommateur downstream identifié qui *utiliserait* ce taux publié pour une action
  économiquement exploitable (ex: accepter du collatéral surévalué, minter/brûler des tokens basés
  sur ce taux, déclencher un paiement). Le texte officiel du scope mentionne "downstream oracle and
  partner consumption" sans nommer d'intégration concrète, et le endpoint public de l'API ne sert
  aucune donnée BNB — rien ne prouve qu'une intégration active existe aujourd'hui.
- Impossible de déterminer si une mise à jour à la hausse légitime est prévue prochainement qui
  masquerait le problème en pratique (par ex. si le vrai taux dépasse un jour 1.00957, la prochaine
  hausse publiée "rattraperait" näivement l'écart sans jamais exposer la cause racine — mais la
  *prochaine baisse réelle*, elle, resterait bloquée pour toujours, perpétuant le problème).

**Verdict de sévérité : LOW — corrigé après vérification du mapping officiel du programme.**

Correction importante : une première passe avait conclu "Medium" par analogie avec la grille
Immunefi générique. En relisant le champ `impacts` du JSON **officiel du programme DAWN** lui-même
(pas une grille générique), le mapping exact est :

```
LOW    | Contract fails to deliver promised returns, but doesn't lose value
MEDIUM | Griefing (e.g. no profit motive for an attacker, but damage to the users or the protocol)
MEDIUM | Block stuffing / Theft of gas / Unbounded gas consumption / contract unable to operate due to lack of funds
CRITICAL | Permanent freezing of funds / Protocol insolvency / ...
```

Le seul impact qui correspond honnêtement à ce finding, sans consommateur downstream démontré, est
*"Contract fails to deliver promised returns, but doesn't lose value"* — **officiellement LOW pour
ce programme**, pas Medium. "Griefing" (Medium) exigerait un dommage concret démontré à des
utilisateurs ou au protocole, ce qu'on n'a pas (on a un oracle stale, pas un dommage tracé à un
tiers). Donc :

- **Pas Low "théorique"** : ce n'est pas un simple nice-to-have — le défaut est démontré actif,
  aujourd'hui, avec des données live, sur l'actif explicitement en scope ("rate-publishing
  authorization, staleness/validation"). Mais actif ≠ sévérité plus haute : le mapping officiel du
  programme classe quand même cette catégorie d'impact en LOW.
- **Pas Medium/High/Critical** : aucune perte de fonds n'est démontrée ni même identifiable, faute
  de consommateur downstream confirmé. Le contrat lui-même ne détient aucun actif ("freezing of
  funds" ne s'applique pas). Gonfler au-delà de LOW sans preuve d'un mécanisme d'extraction
  économique concret serait contraire à la règle anti-inflation du protocole v7.2 — **et maintenant
  contraire aussi au mapping officiel du programme lui-même**, qui est la source de vérité qui
  prime sur toute grille générique.

Si un jury Immunefi identifie un consommateur concret (accès à du code non public, un partenaire
confidentiel, etc.) causant un freezing de fonds ou une insolvabilité, la sévérité pourrait
légitimement monter à Critical sous une catégorie différente — mais ça n'est PAS affirmé ici
faute de preuve, conformément à la règle "jamais gonfler, jamais fabriquer".

## Statut

Brouillon de recherche complémentaire. Pas envoyé. À intégrer dans
`05-report-draft-exchangerate-no-decrease.md` (sections PREUVE DE CONCEPT et SÉVÉRITÉ du Finding 1).
