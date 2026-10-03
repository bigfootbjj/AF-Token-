# Brouillon de rapport Immunefi — DAWN USD.infra Vault

**Statut : brouillon, PAS envoyé. À relire avant toute soumission.**

Deux findings sur le même contrat, chacun avec un PoC Foundry exécutable (fork mainnet via
`anvil` local pré-chargé avec le bytecode/storage réels — voir `../poc/README.md` pour la
justification détaillée et la procédure complète ; reproduction : `cd ../poc && forge test
--match-contract USDTelExchangeRatePoCTest -vvv --rpc-url http://127.0.0.1:8545` après avoir
suivi les 3 étapes du README). Conforme à la guideline Web3 PoC d'Immunefi : code exécutable
(pas de screenshot), fork mainnet, pas de PoC "unit test" déconnecté d'un état réel — le
contrat interrogé est le bytecode et le storage RÉELS copiés depuis le mainnet BNB Chain.

---

# FINDING 1 — Le taux publié ne peut jamais être corrigé à la baisse

## TITRE

`USDTelExchangeRate.setExchangeRate` ne peut jamais publier une baisse du taux de change, gelant le prix de l'oracle BNB Chain indéfiniment au-dessus de sa vraie valeur après toute perte réelle du vault.

## SÉVÉRITÉ (corrigée — alignée sur le mapping officiel du programme)

**LOW**, selon le mapping officiel sévérité↔impact publié dans le JSON du programme Immunefi
(champ `impacts`, pas une grille générique) : la seule catégorie smart-contract qui correspond à ce
finding sans consommateur downstream démontré est *"Contract fails to deliver promised returns, but
doesn't lose value"*, explicitement listée à **LOW** pour ce programme. Aucune autre catégorie ne
s'applique honnêtement : pas de "Permanent freezing of funds" / "Protocol insolvency" (Critical) ni
de "Griefing" (Medium) sans dommage concret démontré à un tiers — le contrat lui-même ne détient
aucun fonds et aucun consommateur downstream n'a pu être identifié (recherche exhaustive : GitHub,
BscScan, DefiLlama, web, API publique de infrastructure.finance — toutes négatives).

**Ce qui distingue quand même ce finding d'un simple "Low" théorique :** confirmé **actif
aujourd'hui**, pas seulement en hypothèse de baisse future — preuve en direct, avec les vrais
chiffres actuels (section B de `06-live-eth_call-confirmation-and-severity.md`), que le taux publié
est déjà faux (surévalué d'environ 0,82 % depuis le 2026-08-06) et que sa correction honnête est
déjà bloquée, maintenant, par la vraie clé `_updater`. Si un jury Immunefi identifie un consommateur
concret causant un freezing de fonds ou une insolvabilité en aval, la sévérité remonterait sous une
catégorie différente ("Permanent freezing of funds" ou "Protocol insolvency", Critical) — **non
affirmé ici faute de preuve**, conformément à la règle anti-inflation.

## SCOPE

Asset Immunefi #100375 : `0x15a6f1f2705b3916b5b1d2b19b10f320778744c1` (BNB Chain) :
> "In scope: rate-publishing authorization, staleness/validation, and any path to posting a manipulated or ripcord-blocked rate."

## RÉSUMÉ

`setExchangeRate` **rejette systématiquement toute valeur inférieure à la précédente**, sans aucune exception ni voie de recours administrative. Si la vraie valeur du vault Loopscale DAWN baisse un jour (défaut de prêt, markdown d'un deal, perte latente démasquée par un retrait), le taux publié sur BNB reste **bloqué indéfiniment** à l'ancienne valeur trop haute.

## CAUSE RACINE

Fichier : `src/USDTelExchangeRate.sol`, fonction `setExchangeRate(uint128)` :

```solidity
function setExchangeRate(uint128 newUSDTelExchangeRate) public onlyUpdater {
    ExchangeRate memory previous = _exchangeRate;

    // The exchange rate is expected to be monotonically non-decreasing.
    if (newUSDTelExchangeRate < previous.usdtelExchangeRate) {
        revert ExchangeRateDecreased();
    }
    ...
}
```

Aucune autre fonction du contrat (`setUpdater`, `transferOwnership`, ownership handover hérité de Solady `Ownable`) ne permet de modifier `_exchangeRate`. **Structurellement aucun chemin** pour corriger la valeur stockée vers le bas, quel que soit le rôle.

## SCÉNARIO

1. Le vault Loopscale DAWN subit une perte réelle (défaut, markdown, insolvabilité partielle) → le NAV réel baisse.
2. `infrafi-api` (détenteur de la clé `_updater` réelle `0x7aD7EEe24ACE80bb84D1bd8fe5798b852Eaa0718`) calcule honnêtement le nouveau taux, inférieur, et tente de le publier.
3. L'appel **revert** avec `ExchangeRateDecreased()` — confirmé par PoC Foundry ci-dessous.
4. Le taux reste bloqué à l'ancienne valeur, indéfiniment.
5. Tout consommateur de `getExchangeRate()` en aval reçoit un prix faux et surévalué.

## IMPACT

- **Direct, démontré, ACTIF AUJOURD'HUI (pas hypothétique) :** l'historique complet du vault réel
  (`GET /vault/solana/nav/history`, endpoint public de `api.infrastructure.finance`, 15 points du
  genesis 2026-09-19 à aujourd'hui) montre que le taux réel du vault **n'a jamais, à aucun moment,
  atteint la valeur publiée sur BNB Chain**. Taux réel maximum jamais enregistré (aujourd'hui même,
  son point le plus haut à ce jour) : **1.0013803491389677**. Taux publié sur BNB, inchangé depuis le
  2026-08-06 : **1.0095655102813623**. Écart actuel : **≈ 0,82 %**, et constant depuis le début de
  l'historique mesurable. L'oracle BNB Chain est donc **déjà surévalué par rapport à la réalité**, pas
  seulement "structurellement incapable de refléter une future baisse".
- **Confirmé par simulation en direct (voir PREUVE DE CONCEPT) :** une tentative, avec la vraie clé
  `_updater`, de publier aujourd'hui le vrai taux actuel du vault (correction légitime et honnête,
  aucune malveillance) **échoue réellement, maintenant**, avec `ExchangeRateDecreased()` — confirmé
  par `eth_call` en lecture seule sur 4 fournisseurs RPC indépendants.
- **Potentiel, non démontré faute d'accès :** si un protocole tiers BNB Chain price du collatéral/règlement sur ce taux, un attaquant pourrait extraire de la valeur sur l'écart prix-figé/vraie-valeur. **Aucun consommateur downstream identifié** (recherche GitHub, BscScan, DefiLlama, web, et API publique de infrastructure.finance — toutes négatives, détail dans `06-live-eth_call-confirmation-and-severity.md`).

## PREUVE DE CONCEPT

PoC Foundry exécutable, fork mainnet (voir `../poc/test/USDTelExchangeRate.PoC.t.sol`, fonction `test_PoC_ExchangeRateCanNeverBeCorrectedDownward`). Extrait :

```solidity
function test_PoC_ExchangeRateCanNeverBeCorrectedDownward() public {
    (uint128 rateBefore,) = target.getExchangeRate();
    address updater = target._updater();

    // Simulate a real loss event: a correctly-computed, honest 1% lower rate.
    uint128 correctedLowerRate = rateBefore - (rateBefore / 100);

    vm.warp(block.timestamp + 1 days);
    vm.prank(updater);                      // the REAL, currently-authorized updater
    vm.expectRevert(IUSDTelExchangeRate.ExchangeRateDecreased.selector);
    target.setExchangeRate(correctedLowerRate);
}
```

Sortie réelle (`forge test -vvv`, voir `../poc/run-output.txt`) :

```
[PASS] test_PoC_ExchangeRateCanNeverBeCorrectedDownward() (gas: 32837)
Logs:
  === FINDING 1: exchange rate has no downward recovery path ===
  Real contract         : 0x15A6F1f2705B3916b5B1D2b19b10F320778744C1
  Real updater key       : 0x7aD7EEe24ACE80bb84D1bd8fe5798b852Eaa0718
  Current published rate : 1009565510281362300
  Current timestamp      : 1785974420
  Honest corrected rate after a 1% real loss: 999469855178548677
  setExchangeRate(correctedLowerRate) REVERTED: ExchangeRateDecreased()
```

### Confirmation complémentaire — simulation `eth_call` live avec les VRAIS chiffres actuels

Au-delà du PoC Foundry (fork avec un scénario de baisse de 1%), une seconde confirmation a été
produite **directement contre le mainnet réel, en lecture seule** (`eth_call`, aucune transaction
diffusée, aucun état modifié — conforme à la règle Immunefi "pas de test sur mainnet déployé"), en
utilisant le **vrai taux réel actuel du vault** (1.0013803491389677, via l'API publique
`api.infrastructure.finance/vault/solana/nav`) plutôt qu'un scénario hypothétique :

```
calldata: setExchangeRate(1001380349138967700)   // = 0x530a09e4...0de59e1f3b7c1c94
from:     0x7ad7eee24ace80bb84d1bd8fe5798b852eaa0718   (le VRAI updater actuel)
to:       0x15a6f1f2705b3916b5b1d2b19b10f320778744c1   (le VRAI contrat déployé)
```

Résultat, confirmé indépendamment sur 4 fournisseurs RPC publics (nodereal, publicnode, defibit,
bsc-dataseed) :

```
{"error":{"code":3,"message":"execution reverted: 0x6143ab0a","data":"0x6143ab0a"}}
```

`0x6143ab0a` = selector exact de `ExchangeRateDecreased()`. Détail complet, décodage, et
méthodologie dans `06-live-eth_call-confirmation-and-severity.md`. **Conclusion : la correction
légitime est bloquée aujourd'hui, avec les vrais chiffres d'aujourd'hui — ce n'est plus un scénario
hypothétique de "1% de perte un jour".**

## POURQUOI PAS DOUBLON

Aucun known issue officiel ne couvre ça (les 5 listés : JWT localStorage, ripcord non-bloquant, replay Slack, admin seedé, rôle plat). Aucun audit public (Loopscale/Adevar/Offside/Highland, tous lus) ne couvre ce contrat BNB — jamais audité publiquement.

## POURQUOI PAS EXCLU

- Pas une "incorrect data from third party oracle" — le bug est dans la validation InfraFi elle-même.
- Pas un "centralization risk" — existe même pour la clé `updater` légitime et honnête.
- Pas un gap opérationnel/self-harm — atteignable en production par le fonctionnement normal (une baisse de NAV est un risque de crédit ordinaire, pas un scénario exotique).
- Match direct avec le texte in-scope : "staleness/validation" et "any path to posting a manipulated or ripcord-blocked rate" (un taux bloqué-trop-haut est fonctionnellement "ripcord-blocked" en permanence).

## CORRECTION RECOMMANDÉE

```diff
 function setExchangeRate(uint128 newUSDTelExchangeRate) public onlyUpdater {
     ExchangeRate memory previous = _exchangeRate;

-    // The exchange rate is expected to be monotonically non-decreasing.
-    if (newUSDTelExchangeRate < previous.usdtelExchangeRate) {
-        revert ExchangeRateDecreased();
-    }
-
     uint256 elapsed = block.timestamp - previous.timestamp;

-    if (newUSDTelExchangeRate > previous.usdtelExchangeRate) {
+    // Validate the magnitude of change in either direction against the ceiling.
+    if (newUSDTelExchangeRate != previous.usdtelExchangeRate) {
         if (elapsed == 0) {
             revert StaleTimestamp();
         }
-        uint256 growth = newUSDTelExchangeRate - previous.usdtelExchangeRate;
+        uint256 delta = newUSDTelExchangeRate > previous.usdtelExchangeRate
+            ? newUSDTelExchangeRate - previous.usdtelExchangeRate
+            : previous.usdtelExchangeRate - newUSDTelExchangeRate;
-        uint256 apy = (growth * SECONDS_PER_YEAR * APY_SCALE) / (uint256(previous.usdtelExchangeRate) * elapsed);
+        uint256 apy = (delta * SECONDS_PER_YEAR * APY_SCALE) / (uint256(previous.usdtelExchangeRate) * elapsed);
         if (apy > _apyCeiling) {
             revert ApyCeilingExceeded(apy, _apyCeiling);
         }
     }
     _exchangeRate = ExchangeRate(newUSDTelExchangeRate, uint64(block.timestamp));
     emit ExchangeRateUpdated(newUSDTelExchangeRate, uint64(block.timestamp));
 }
```

---

# FINDING 2 — Le plafond de croissance annuelle se compose au lieu de borner

**Convergence exceptionnelle : les 12/12 agents du scan formel `solidity-auditor v4` (lancé indépendamment sur ce même contrat) ont identifié ce bug unanimement, chacun avec sa propre preuve mathématique indépendante.**

## TITRE

Le plafond `_apyCeiling` de `setExchangeRate` borne la croissance simple par appel, pas la croissance composée réelle — des mises à jour fréquentes et parfaitement ordinaires (mensuelles, quotidiennes) font croître le taux au-delà du plafond documenté, sans aucune malveillance.

## SÉVÉRITÉ (corrigée — alignée sur le mapping officiel du programme)

**LOW**, même raisonnement que Finding 1 : aucune catégorie officielle smart-contract du programme
ne correspond mieux que *"Contract fails to deliver promised returns, but doesn't lose value"*
(LOW) — ici le "promised return" étant la garantie documentée dans le contrat lui-même qu'un
`_updater` (même compromis) ne peut faire croître le taux au-delà du plafond annoncé. Pas de perte
de valeur démontrée, pas de consommateur downstream identifié qui serait lésé par cet excès. Chaque
appel individuel respecte le contrôle ; le dépassement n'apparaît qu'à l'échelle de la séquence.
Point notable conservé : **aucune compromission n'est nécessaire** — un service de publication
honnête, à cadence normale, viole déjà la garantie documentée ("a compromised updater can only push
rates (bounded by the APY ceiling)" — commentaire du contrat lui-même, qui s'avère faux même sans
compromission). Cette robustesse de la preuve (12/12 agents convergents) justifie de le signaler
malgré la sévérité officielle basse — mais honnêtement, LOW et non Medium.

## SCOPE

Même asset #100375 — "staleness/validation" et "any path to posting a manipulated ... rate" couvrent un taux publié au-delà de sa borne de plausibilité documentée.

## CAUSE RACINE

```solidity
uint256 apy = (growth * SECONDS_PER_YEAR * APY_SCALE) / (uint256(previous.usdtelExchangeRate) * elapsed);
if (apy > _apyCeiling) {
    revert ApyCeilingExceeded(apy, _apyCeiling);
}
```

Le contrôle compare la croissance de CET appel contre le taux immédiatement précédent — jamais contre une référence fixe (ex. le taux il y a un an). Enchaîner N appels, chacun saturant son propre contrôle, compose multiplicativement : `rate_N = rate_0 * (1 + ceiling/N)^N`, qui tend vers `rate_0 * e^ceiling` au lieu du `rate_0 * (1 + ceiling)` qu'un seul appel annuel autoriserait.

## PREUVE DE CONCEPT

PoC Foundry exécutable (`test_PoC_APYCeilingCompoundingBypass` et sa variante `_DailyCadence`), même fork que Finding 1. Sortie réelle :

```
[PASS] test_PoC_APYCeilingCompoundingBypass() (gas: 156620)
Logs:
  Starting rate   : 1009565510281362300
  APY ceiling     : 200000000000000000 / scale 1000000000000000000  (20%)
  -- Baseline: one update after 365 days, at the maximum allowed growth --
  Max rate a SINGLE yearly update may legally reach: 1211478612337634760
  -- Attack: same updater key, same one-year span, split into 12 monthly calls --
    call 1 -> new rate: 1026391602119385005
    ...
    call 12 -> new rate: 1231055182864894940
  Final rate after 12 individually-compliant monthly calls: 1231055182864894940
  Max rate a single yearly update may legally reach       : 1211478612337634760
  Excess over the documented annual ceiling (1e18 = 100%): 16159237421027008   (+1.62% relative)

[PASS] test_PoC_APYCeilingCompoundingBypass_DailyCadence() (gas: 2899071)
Logs:
  Final rate after 365 daily calls over one year : 1233018558960841832
  Max rate a single yearly update may legally reach: 1211478612337634760
  Excess over the documented annual ceiling (1e18 = 100%): 17779881876448649   (+1.79% relative)
```

Chaque appel individuel passe `ApyCeilingExceeded` — aucun n'est "faux" isolément. Le dépassement grandit avec la fréquence des appels et tend vers `e^0.2 - 1 ≈ 22.14%` de croissance réelle (contre 20% documentés) à fréquence très élevée — démontré mathématiquement de façon convergente par les 12 agents du scan formel (voir leurs traces complètes, ex. avec un plafond à 100% pour amplifier l'effet : 12 appels mensuels → ×2.25 au lieu de ×2.0 attendu, soit +12.5%).

## POURQUOI PAS DOUBLON / EXCLU

Mêmes arguments que Finding 1 (contrat jamais audité publiquement, aucun known issue ne couvre ça). Pas un problème de clé compromise — fonctionne pour un `_updater` parfaitement honnête à cadence normale.

## CORRECTION RECOMMANDÉE

Comparer la croissance contre une référence fixe (ex. taux et timestamp d'il y a un an), ou utiliser une formule d'intérêts composés (`previous * e^(ceiling * elapsed / year)`), au lieu d'un intérêt simple recalculé à chaque appel depuis le dernier point.

---

## Points ouverts avant soumission (les deux findings)

1. **Sévérité réelle de Finding 1 et 2** — recherche du consommateur downstream exhaustive (GitHub,
   BscScan, DefiLlama, web, API publique infrastructure.finance) : **négative**. Severité retenue,
   alignée sur le mapping officiel sévérité↔impact du programme (champ `impacts` du JSON, pas une
   grille générique) : **LOW** pour les deux findings — seule catégorie applicable sans
   consommateur downstream démontré : *"Contract fails to deliver promised returns, but doesn't lose
   value"*, officiellement LOW pour ce programme. Confirmé actif aujourd'hui par preuve live (pas
   seulement hypothétique), voir `06-live-eth_call-confirmation-and-severity.md`. Si un jury
   Immunefi a accès à une intégration non publique causant un freezing de fonds ou une
   insolvabilité, la sévérité pourrait monter sous une catégorie Critical différente — non affirmé
   ici faute de preuve.
2. ~~Historique des mises à jour non récupéré~~ — **résolu** : l'historique complet du vault réel
   (`/vault/solana/nav/history`, 15 points depuis le genesis) prouve que le taux réel n'a **jamais**
   atteint le taux publié sur BNB, à aucun moment de son histoire. Voir note 06.
3. Confirmer qu'aucune règle de staleness cachée côté `infrafi-api` ne compense déjà ces défauts off-chain (code non accessible).
4. Les deux PoC tournent contre un `anvil` local chargé avec le bytecode/storage réels (contournement d'une limitation anti-abus `eth_getProof`-en-batch commune à tous les RPC BSC publics testés) — voir `../poc/README.md` pour la justification complète et comment relancer avec un RPC premium si disponible. La confirmation complémentaire par `eth_call` live (point 1 ci-dessus) ne dépend pas de ce contournement — elle interroge directement le mainnet réel, en lecture seule.
