# Brouillon de rapport Immunefi — DAWN USD.infra Vault

**Statut : brouillon, PAS envoyé. À relire avant toute soumission.**

---

## TITRE

`USDTelExchangeRate.setExchangeRate` ne peut jamais publier une baisse du taux de change, gelant le prix de l'oracle BNB Chain indéfiniment au-dessus de sa vraie valeur après toute perte réelle du vault.

## SÉVÉRITÉ (proposée, à discuter)

**Medium**, avec justification pour une révision à High si un consommateur downstream concret est identifié (voir "Points ouverts" en fin de document). Pas de vol/perte de fonds démontré *sur cet asset lui-même* (le contrat ne détient aucun fonds) — mais un défaut de validation permanent et sans recours sur l'asset explicitement désigné in-scope pour "staleness/validation".

## SCOPE

Asset Immunefi #100375 : `0x15a6f1f2705b3916b5b1d2b19b10f320778744c1` (BNB Chain), décrit officiellement comme :
> "In scope: rate-publishing authorization, staleness/validation, and any path to posting a manipulated or ripcord-blocked rate."

## RÉSUMÉ

Le contrat `USDTelExchangeRate` (déployé sur BNB Chain, source vérifiée récupérée via Sourcify) stocke et publie le taux de change USD.infra, avec un plafond de croissance annualisée (`_apyCeiling`, actuellement 20%). Sa fonction `setExchangeRate` **rejette systématiquement toute valeur inférieure à la précédente**, sans aucune exception ni voie de recours administrative. Si la vraie valeur du vault Loopscale DAWN baisse un jour (défaut de prêt, markdown d'un deal, perte latente démasquée par un retrait), le taux publié sur BNB reste **bloqué indéfiniment** à l'ancienne valeur trop haute.

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

Aucune autre fonction du contrat (`setUpdater`, `transferOwnership`, `requestOwnershipHandover`/`completeOwnershipHandover` hérités de Solady `Ownable`) ne permet de modifier `_exchangeRate` directement. Il n'existe **structurellement aucun chemin** pour corriger la valeur stockée vers le bas, quel que soit le rôle (updater ou owner).

## SCÉNARIO

1. Le vault Loopscale DAWN subit un événement de perte réelle (défaut de prêt, markdown de deal, insolvabilité partielle) → le NAV réel baisse.
2. `infrafi-api` (le service off-chain légitime, détenteur de la clé `_updater` réelle `0x7ad7eee24ace80bb84d1bd8fe5798b852eaa0718`) calcule le nouveau taux, inférieur à l'ancien, et tente de le publier via `setExchangeRate`.
3. L'appel **revert** avec `ExchangeRateDecreased()` — confirmé par PoC (voir ci-dessous), peu importe que la baisse soit légitime et correctement calculée.
4. Le taux stocké reste à l'ancienne valeur (trop haute) indéfiniment. Aucune fonction d'admin ne permet de le corriger.
5. Tout système qui lit `getExchangeRate()` en aval ("downstream oracle and partner consumption", texte officiel) continue de recevoir un prix faux et surévalué, sans aucun signal d'alerte on-chain (pas d'event, pas de flag de staleness forcé — le timestamp avance bien à chaque tentative RÉUSSIE, mais une tentative de baisse échouée ne laisse même pas de trace on-chain, puisqu'elle revert).

## IMPACT

- **Direct, démontré :** l'oracle de taux de change devient structurellement incapable de refléter une baisse réelle de valeur — violation du but même du contrat ("staleness/validation" explicitement in-scope). C'est un défaut permanent, non un état transitoire.
- **Potentiel, non démontré faute d'accès :** si un protocole tiers sur BNB Chain utilise ce taux comme prix de référence pour du collatéral ou un règlement, un attaquant pourrait exploiter l'écart entre le prix figé (trop haut) et la vraie valeur pour extraire des fonds de ce protocole tiers après un événement de perte réel. **Aucun consommateur downstream n'a pu être identifié** (recherche GitHub + web négative) — ce point reste ouvert.

## PREUVE DE CONCEPT

Simulation en lecture seule (`eth_call`, zéro transaction, zéro état modifié), contre l'état mainnet réel, exécutée le 2026-10-03 :

```
RPC: https://bsc-dataseed.binance.org
Contrat: 0x15a6f1f2705b3916b5b1d2b19b10f320778744c1

1) Lecture de l'état actuel :
   getExchangeRate() → rate = 1009565510281362300 (≈1.00957), timestamp = 1785974420 (2026-08-06)
   _updater() → 0x7ad7eee24ace80bb84d1bd8fe5798b852eaa0718

2) Simulation : l'updater RÉEL tente de publier une baisse légitime vers 1.0e18 :

   eth_call({
     from: "0x7ad7eee24ace80bb84d1bd8fe5798b852eaa0718",
     to:   "0x15a6f1f2705b3916b5b1d2b19b10f320778744c1",
     data: "0x530a09e40000000000000000000000000000000000000000000000000de0b6b3a7640000"
           // selector setExchangeRate(uint128) + argument 1.0e18
   })

   → {"error":{"code":3,"message":"execution reverted: 0x6143ab0a",
       "data":"0x6143ab0a"}}
     // 0x6143ab0a = keccak256("ExchangeRateDecreased()")[:4] — confirmé.
```

Le revert se produit avec la clé `updater` **réelle et actuellement autorisée** — ce n'est pas un problème d'autorisation, c'est que la fonction elle-même rejette structurellement toute baisse.

## POURQUOI PAS DOUBLON

Aucun known issue officiel ne mentionne ce comportement (les 5 known issues listés concernent JWT localStorage, ripcord non-bloquant, replay webhook Slack, admin seedé, rôle plat — aucun ne touche au contrat BNB). Aucun audit public (Loopscale/Adevar/Offside/Highland, tous lus) ne couvre ce contrat — il n'a jamais été audité publiquement. Mécanisme et composant distincts de toute piste déjà notée en interne (P-01 à P-05, C-01 à C-18).

## POURQUOI PAS EXCLU

- Pas une "incorrect data from third party oracle" — le bug est dans la validation du contrat InfraFi lui-même, pas dans une donnée tierce.
- Pas un "centralization risk" — le bug existe même pour la clé `updater` légitime et honnête ; ce n'est pas une question de qui contrôle la clé.
- Pas un gap opérationnel/self-harm — le chemin est atteignable en production par le fonctionnement normal du service (une vraie baisse de NAV n'est pas un scénario exotique, c'est un risque de crédit ordinaire pour un protocole de lending).
- Match direct avec le texte in-scope explicite de l'asset : "staleness/validation" et "any path to posting a manipulated or ripcord-blocked rate" (un taux bloqué-trop-haut est fonctionnellement un taux "ripcord-blocked" en permanence, sans jamais lever le signal ripcord).

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

-    // Only validate growth; a flat (unchanged) rate is always allowed even
-    // within the same block, but any increase requires elapsed time.
-    if (newUSDTelExchangeRate > previous.usdtelExchangeRate) {
+    // Validate the MAGNITUDE of change in either direction against the ceiling,
+    // instead of forbidding decreases outright.
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

Garde le même garde-fou contre une variation anormalement rapide (dans les deux sens, borné par le même `_apyCeiling`), mais permet enfin à l'oracle de refléter une vraie baisse.

---

## Points ouverts avant soumission

1. **Sévérité réelle** — dépend d'identifier un consommateur downstream sur BNB Chain. Recherche GitHub/web négative à ce stade. Sans ça, classification honnête = Medium (défaut de validation sans extraction démontrée).
2. **Historique des mises à jour** — non récupéré (coût RPC élevé pour la fenêtre de 58 jours, limite de plage de blocs du nœud public). Pas bloquant pour le finding principal, qui est structurel et indépendant de la cadence historique.
3. **Confirmer qu'aucune règle de "staleness" cachée côté infrafi-api** ne compense déjà ce défaut en stoppant la publication/alertant les partenaires en cas d'échec de `setExchangeRate` — on n'a pas le code infrafi-api pour vérifier ça. Si une telle compensation existe côté off-chain, ça nuance (sans l'annuler) la sévérité.
