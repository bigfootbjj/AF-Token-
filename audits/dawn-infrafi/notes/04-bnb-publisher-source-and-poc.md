# DAWN / InfraFi — Contrat BNB publisher : source complète + PoC confirmé

Source vérifiée obtenue via **Sourcify** (`GET /v2/contract/56/0x15a6f1f2705b3916b5b1d2b19b10f320778744c1`),
qui contourne le blocage anti-bot de bscscan.com. Sauvegardée dans
`audits/dawn-infrafi/sources/USDTelExchangeRate.sol`. Contrat : `USDTelExchangeRate`, hérite de
`solady/auth/Ownable.sol`.

## Lecture live confirmée (RPC BSC public, aujourd'hui)

| Champ | Valeur |
|---|---|
| `owner()` | `0x457da8161d59a8dcc984a69008d90cc84b8c3ee7` — **Gnosis Safe Proxy** (bytecode confirmé par `eth_getCode`) |
| `_updater()` | `0x7ad7eee24ace80bb84d1bd8fe5798b852eaa0718` — **EOA simple** (code vide), hot key du service de publication |
| `_apyCeiling()` | `200000000000000000` = **exactement 20%** (échelle 1e18) |
| `getExchangeRate()` | rate = `1009565510281362300` (≈ **1.00957**), timestamp = **2026-08-06T00:00:20Z** |

**Le taux publié n'a pas été mis à jour depuis ~58 jours** (aujourd'hui : 2026-10-03). À vérifier si c'est
un problème opérationnel (service de publication en panne) ou simplement une croissance trop lente pour
justifier une mise à jour — mais ça confirme concrètement la piste C-16 (Boundary, `/health` superficiel).

## FINDING confirmé par PoC — `setExchangeRate` ne peut JAMAIS publier une baisse

```solidity
function setExchangeRate(uint128 newUSDTelExchangeRate) public onlyUpdater {
    ExchangeRate memory previous = _exchangeRate;
    if (newUSDTelExchangeRate < previous.usdtelExchangeRate) {
        revert ExchangeRateDecreased();   // <-- AUCUN moyen de publier une baisse, jamais
    }
    ...
}
```

**PoC exécuté** (simulation `eth_call` en lecture seule contre l'état mainnet réel, `from` = l'updater
réel `0x7ad7e...18`, aucune transaction émise, aucun état modifié — respecte la règle "pas de test sur
mainnet déployé" puisque `eth_call` ne mute rien) :

```
calldata: setExchangeRate(1.0e18)  // taux actuel = 1.00957e18, donc 1.0e18 est une baisse légitime
from: 0x7ad7eee24ace80bb84d1bd8fe5798b852eaa0718  (le VRAI updater actuel)
→ revert: 0x6143ab0a = ExchangeRateDecreased()
```

**Root cause :** `setExchangeRate` traite toute baisse comme invalide, quelle que soit la cause (pas
seulement une tentative malveillante — même l'updater légitime, avec une donnée réelle et correcte, ne
peut PHYSIQUEMENT PAS publier une baisse). Aucune fonction d'admin (owner/Gnosis Safe) ne permet non plus
de corriger ou réinitialiser la valeur — `setUpdater` ne change que l'adresse autorisée, pas la valeur
stockée.

**Impact concret :** si la vraie valeur du vault Loopscale DAWN baisse un jour (défaut de prêt, markdown
d'un deal, retrait massif qui démasque une perte latente), **le taux publié sur BNB Chain reste
indéfiniment bloqué à l'ancienne valeur trop haute**, sans aucun chemin de correction on-chain — seule
option : déployer un nouveau contrat et migrer tous les consommateurs en aval. Tant que ça n'est pas
fait, "downstream oracle and partner consumption" (texte officiel) continue de lire un prix faux et
surévalué.

**Alignement scope :** le texte officiel de l'asset #100375 dit explicitement *"In scope:
rate-publishing authorization, **staleness/validation**, and any path to posting a manipulated or
ripcord-blocked rate."* — c'est très exactement ce bug : un défaut de validation qui bloque la
*correction* vers le bas, créant une forme de staleness permanente et irréversible.

**Sévérité — honnêteté sur l'incertitude :** le contrat lui-même ne détient aucun fonds (pur oracle de
prix), donc "freezing of funds" ne s'applique pas directement à CET asset. L'impact réel dépend de qui
consomme ce taux en aval sur BNB Chain (un protocole de lending qui accepterait du collatéral valorisé
sur ce taux serait exploitable : emprunter contre un collatéral sur-évalué après une vraie baisse de
NAV). **Cette partie — identifier le(s) consommateur(s) downstream — reste à faire** ; sans ça, la
sévérité par défaut est plutôt Low/Medium ("contract fails to deliver promised returns"/staleness),
mais pourrait monter à High/Critical si un consommateur concret et un mécanisme d'extraction sont
démontrés. **Ne pas sur-vendre avant d'avoir identifié ce consommateur.**

## Bug secondaire (mineur) — la borne APY est un plafond composé, pas un plafond simple

`apy = (growth * SECONDS_PER_YEAR * APY_SCALE) / (previousRate * elapsed)` est vérifié à CHAQUE appel
contre le taux et le timestamp immédiatement précédents. Mathématiquement, enchaîner des mises à jour
très fréquentes (limité à ~1 par bloc BSC, ~3s) compose plutôt qu'additionne la croissance : sur une
période complète, la croissance totale atteignable tend vers `e^ceiling` au lieu de `(1+ceiling)`, soit
pour ceiling=20% un dépassement d'environ **+2 points de pourcentage sur un an** (22,1% au lieu de 20%)
dans le pire cas de fréquence maximale. **Nécessite le contrôle de la clé `_updater`** (hot key,
explicitement un risque accepté par le design du contrat lui-même) — donc sévérité faible et à la limite
du hors-scope ("attacks requiring access to leaked keys/credentials"). Noté pour mémoire, pas prioritaire.

**Point positif à noter (pas un bug) :** le design gère correctement le rattrapage après une pause —
l'allocation de croissance autorisée scale avec `elapsed`, donc une longue pause suivie d'une vraie
croissance légitime ne sera pas bloquée à tort. Ça infirme la piste Invariant-Agent "rate-limit-false-
positive-after-pause" telle que formulée — le mécanisme est en fait bien pensé sur ce point précis.

## Fichiers

- Source complète sauvegardée : `audits/dawn-infrafi/sources/USDTelExchangeRate.sol` (+ `lib/solady/...`)
- Owner = Gnosis Safe proxy (rassurant, cohérent avec un modèle de clé froide protégée)
- Updater = EOA simple (documenté et assumé par le contrat lui-même comme un risque borné)
