# DAWN / InfraFi — Vérification on-chain mainnet (réseau débloqué)

Dès que `api.mainnet-beta.solana.com` et `api.infrastructure.finance` ont été autorisés par Mathieu,
lecture RPC directe (`getAccountInfo`, `jsonParsed`) sur les 4 comptes du scope + les 2 autorités
qu'ils référencent. Données réelles, slot ~453000104-453000300 (aujourd'hui). Ceci **corrige** certaines
hypothèses du round précédent et **confirme** une piste importante.

## Correction : C-01 (comptes dupliqués) — la piste OSINT GitHub était un faux indice

`EZ8sq2FNnmqQo254irAMGNp7c6B7DPuKh22SyXAwuXSn` : `owner = 1oopBoJG58DgkUVKkEzKgyG9dvRmpgeEm1AVjoHkF78`
(programme Loopscale), `space = 162`.
`4rXteUmbxiXvgLqP14eQwtqkLyVNXVCBHnXyLQ9vZkSh` : même owner (Loopscale), **même space = 162**.

**Les deux comptes sont bien réellement possédés par le programme Loopscale, de taille identique** —
cohérent avec la description officielle dupliquée (probablement deux comptes du même type : vault +
strategy, ou deux vaults liés). L'hypothèse du tour précédent (EZ8sq2 = compte Kamino
Scope/Exponent Tranching, basée sur son apparition dans `sava-software/idl-clients`) est **infirmée**
par la lecture directe — cette lib de test utilisait très probablement des pubkeys mainnet réels
au hasard comme données de fixture, sans rapport fonctionnel. **Leçon : l'OSINT GitHub donne des pistes,
la lecture on-chain directe tranche.** C-01 est maintenant **clos comme non-préoccupant** (pas une
divergence de scope, juste une description Immunefi réutilisée pour deux comptes liés légitimes).

## Confirmation forte : C-04/C-15 — l'autorité de pause USD.infra est une clé unique, PAS un multisig Squads

Lecture du mint USD.infra (`dawn7ZUF7h7anFuEsDdAU1Y3HYwikwqNMAENZsQJdNL`), mainnet, à l'instant :

- `supply`: 10,327,416.346235 USD.infra (6 décimales) — cohérent avec le TVL DefiLlama (~9.3-10.3M$).
- Extensions actives : `metadataPointer`, `transferHook` (**`programId: null`** — hook présent mais pas
  câblé à un programme, donc inactif actuellement), `pausableConfig` (**`paused: false`**), `tokenMetadata`
  (name/symbol = "USD.infra" — confirme le rebranding depuis "USD.tel" vu dans le snapshot devnet).
- `mintAuthority`: `Am4facCvkQkHjwSArPX8Jqxs1ss14XMoC8JkTV3BDG95` — compte **inexistant on-chain**
  (`value: null`, 0 lamports). C'est normal et attendu : c'est la PDA du programme de wrap M0
  (`mextzNVPUbLbvyBwqBqnC5J1SSwjDLjjR4yppf6EBzc`, confirmé par l'audit devnet lu précédemment), qui
  signe par CPI sans avoir besoin d'exister comme compte financé. **Hors-scope** (M0 program internals),
  rien d'anormal.
- **`freezeAuthority` = `pausableConfig.authority` = `transferHook.authority` = `metadataPointer.authority`
  = UN SEUL ET MÊME PUBKEY : `4X9oEExyxYVzWzXWame931CCAF7XbgCbp9ZKg4ECW4Hi`.**

Lecture de ce pubkey : `owner = 11111111111111111111111111111111` (System Program), `executable: false`,
`space: 0`, `lamports: 18523520` (~0.0185 SOL).

**C'est un wallet simple (EOA) financé — PAS une PDA du programme Squads V4** (`SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf`).
Si c'était un vault multisig Squads, `owner` serait le programme Squads V4, pas le System Program.

**Ce que ça confirme concrètement :** le programme décrit explicitement "DAWN's own USD.infra Token-2022
global pause" comme exécuté "through a Squads V4 multisig" (même phrase que pour borrow/repay). Sur
la configuration mainnet actuelle, **l'autorité de pause (et de freeze, et de TransferHook, et de mise à
jour des métadonnées) du mint est une clé unique, pas un multisig N-sur-M.** C'est vérifié, pas une
hypothèse — lecture directe, deux comptes, aujourd'hui.

### Soumissibilité — à nuancer honnêtement

Ce n'est **pas automatiquement un finding soumissible** tel quel : Immunefi exclut explicitement les
"Impacts involving centralization risks" et les "impacts caused by attacks requiring access to leaked
keys/credentials" (le scénario "si cette clé est compromise, le pause est détourné" est hors-scope par
construction — c'est vrai de n'importe quelle clé). Ce qui est soumissible, c'est si on peut montrer que
l'écart entre le modèle documenté (multisig) et la réalité (clé unique) ouvre un chemin **qui nuit à
autrui** sans nécessiter de compromission — ex. : si le même constat s'étend à l'autorité borrow/repay
du vault Loopscale (pas seulement la pause USD.infra), ça rapprocherait du texte in-scope
"any path that lets deal valuations (or borrow/repay) be executed ... without the trusted-operator role"
si cette autorité se révèle être, elle aussi, une clé simple plutôt que le multisig annoncé.

**Prochaine étape pour trancher** : décoder les données brutes du compte vault Loopscale (`EZ8sq2...` /
`4rXteU...`, 162 bytes chacun) via l'IDL Anchor — le programme affirme qu'il est "fetchable on-chain".
Nécessite soit l'IDL JSON (dérivable via la convention PDA d'Anchor `["anchor:idl"]`), soit le schéma
public du programme Loopscale. Pas fait dans cette passe (nécessite un script de décodage Borsh dédié,
au-delà d'une vérification rapide) — à faire en prochaine session si on veut pousser ce fil.

## sUSD.infra (parts du vault) — rien d'anormal

`GvEMgNT6GKiYTvg7TskDio6RKzQdCuhwmH55tVCLaJTe` : supply 10,027,325.9281 sUSD.infra. Toutes les
autorités (mint, freeze, metadataPointer, mintCloseAuthority, tokenMetadata update) pointent vers
`4rXteUmbxiXvgLqP14eQwtqkLyVNXVCBHnXyLQ9vZkSh` — **le compte vault Loopscale lui-même** (PDA du
programme), pas un wallet humain. C'est le pattern attendu et sûr (le vault contrôle ses propres parts
par logique on-chain, pas par clé externe). Ratio approximatif TVL/LP actuel ≈ 10.33M / 10.03M ≈ 1.03 —
cohérent avec un vault jeune en légère croissance, pas de signe de dérive déjà visible dans ce seul
instantané.

## BscScan / contrat BNB — toujours bloqué, mais différemment

`bscscan.com` et `solscan.io` renvoient maintenant un vrai `403` du site lui-même (protection anti-bot
Cloudflare probable), pas un rejet du proxy réseau — le proxy laisse passer la connexion. `api.bscscan.com`
redirige (301) mais nécessite une clé API pour les endpoints utiles. Les RPC BSC publics testés
(`bsc-dataseed.binance.org`, `bsc-dataseed1.binance.org`) renvoient 404 sur la racine HTTP (normal, ce
sont des endpoints JSON-RPC POST-only, pas des pages web) — à tester avec un vrai appel JSON-RPC
(`eth_getCode`) plutôt qu'un GET nu avant de conclure qu'ils sont inaccessibles.
