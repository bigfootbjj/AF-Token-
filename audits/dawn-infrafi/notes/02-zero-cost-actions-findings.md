# DAWN / InfraFi — Résultats des 3 actions à coût zéro (OSINT GitHub)

Méthode : recherche de code GitHub (`search_code`) sur les 4 identifiants on-chain du scope. Zéro accès
RPC/explorer nécessaire — tout vient de dépôts publics tiers qui référencent ces adresses. Toujours
NON ATTAQUÉ (observation, pas de PoC), mais ça change significativement l'état de plusieurs pistes.

## Résultat 1 — C-01 : l'asset #100745 (`EZ8sq2FN...`) n'est probablement PAS "le vault Loopscale"

Trouvé dans `sava-software/idl-clients` (lib cliente IDL Java, publique), fichier
`ExponentTranchingMarketTests.java`. Commentaire du fichier :

> "Pins `ExponentTranchingMarket` to two live markets ... captured from mainnet at slot 452336032
> (2026-10-01)" — soit **il y a 2 jours**, donc des données mainnet actuelles, pas historiques.

`EZ8sq2FNnmqQo254irAMGNp7c6B7DPuKh22SyXAwuXSn` apparaît comme un compte **writable** dans la liste
`refreshAccounts()` du marché `DzL8SjfkrPnybYfSh82QDhhFq2Nby2XVDnKRoTehkMsz` ("WIDE_MARKET") — un des
comptes `get_sy_state` consommés par l'instruction CPI `exponent_tranching::get_price` de **Kamino
Scope**, l'oracle qui price les tokens **Exponent** (SY/PT, tranching de yield) pour Loopscale.

**Ce que ça signifie :** la description officielle Immunefi ("Loopscale credit vault holding InfraFi
capital... DAWN is the sole whitelisted borrower") semble être un copier-coller générique appliqué aux
deux assets Solana (#100745 et #101014), alors que seul `4rXteUmbxiXvgLqP14eQwtqkLyVNXVCBHnXyLQ9vZkSh`
est nommé "DAWN vault" dans le `programOverview` officiel lui-même. `EZ8sq2...` ressemble bien plus à
un compte d'état de l'oracle Kamino Scope / Exponent Tranching Market qu'à un vault.

**Deux lectures possibles, à trancher dès que le réseau/RPC est accessible :**
- (a) Erreur d'étiquetage Immunefi (description dupliquée par erreur) — `EZ8sq2...` serait quand même
  légitimement in-scope parce que le NAV/la valorisation de collatéral DAWN en dépend indirectement
  (si Loopscale price du collatéral Exponent LP pour les deals DAWN via ce market Scope — cohérent avec
  l'audit "Exponent LP Pricing" déjà lu, qui couvrait exactement ce chemin de pricing côté Loopscale).
  Dans ce cas, c'est une dépendance d'oracle tierce dont la manipulation reste couverte par l'exclusion
  "incorrect data supplied by third party oracles... not to exclude oracle manipulation" — donc
  potentiellement attaquable si on peut montrer un chemin de manipulation affectant le NAV DAWN.
  (b) Immunefi a vraiment scope le mauvais compte pour #100745 — à signaler au programme si confirmé,
  mais **ne change rien à nos pistes** puisque C-01 portait justement sur la confusion d'identité.
- Vérification triviale dès accès réseau : lire le `owner` program du compte `EZ8sq2...` — s'il
  appartient au programme Kamino Scope / Exponent Tranching (pas à Loopscale
  `1oopBoJG58DgkUVKkEzKgyG9dvRmpgeEm1AVjoHkF78`), l'hypothèse (a)/(b) est confirmée.

**Impact sur la matrice :** C-01 passe de "ambiguïté entre 2 comptes identiques" à "un des deux comptes
scope n'est probablement pas du tout ce que sa description dit" — resserre et durcit la piste.

## Résultat 2 — Configuration Token-2022 du mint USD.infra (`dawn7ZUF...`) — AVEC CAVEAT IMPORTANT

Trouvé dans `MalteHerrmann/random-scripts`, fichier `20260519_solana_extension_inspector/audit-mextzNVP-dawn7ZUF.json`
— un outil tiers d'inspection d'extensions Token-2022, exécuté le **22 juin 2026** contre
**`rpcEndpoint: devnet.helius-rpc.com`** (devnet, pas mainnet).

**⚠️ Caveat : ceci est une capture devnet datée d'AVANT le lancement officiel du programme (12 juillet
2026). Peut ne plus refléter l'état mainnet actuel. À reconfirmer en priorité dès accès RPC mainnet.**

Ce que le fichier montre (si représentatif du design, même si les valeurs exactes doivent être
reconfirmées en mainnet) :

- Le token s'appelait alors **"USD.tel"** (name=symbol="USD.tel") — cohérent avec l'admin seedé
  `admin@usd.tel` du known issue #4 : ancien nom de marque avant le rebranding "USD.infra"/DAWN.
  Pas une alerte en soi, juste une confirmation de continuité de projet.
- Extensions actives : **MetadataPointer, TokenMetadata, TransferHook, PausableConfig**. Le programme
  officiel ne mentionne QUE "Pausable" dans sa description — si TransferHook est bien actif en mainnet,
  ça active directement la piste P-04 et réintroduit la surface couverte par l'audit Loopscale
  "Transfer Hook Feature" déjà lu (2 Low fixés côté Loopscale sur l'intégration TransferHook pour du
  collatéral — mécanisme transposable si USD.infra lui-même porte cette extension).
  **TransferHook.programId = `11111111111111111111111111111111`** (System Program / sentinel nul) dans
  ce snapshot — soit le hook n'était pas encore configuré à cette date (pré-lancement), soit c'est un
  artefact de requête devnet. À reconfirmer en priorité.
- **Toutes les autorités observées (freeze, TransferHook, TokenMetadata update, PausableConfig) pointent
  vers LE MÊME pubkey unique : `98Ck1KwGZcbPsY5bexhLnEBPWhkyrCMbNd9RpxGwJTKc`**, classifié "unfunded_eoa"
  (une simple paire de clés, PAS une PDA Squads V4 multisig). Si cette concentration persiste en mainnet,
  ça confirme très concrètement la piste **C-04/C-15 (asymmetric-emergency-lever-authority)** : le levier
  d'urgence "pause USD.infra" documenté comme passant par Squads V4 reposerait en réalité sur une seule
  clé simple — à l'opposé de ce que décrit le modèle de confiance officiel. C'est exactement le type de
  divergence "documentation vs config réelle" que 6 lentilles indépendantes avaient anticipée sans preuve.
- Mint authority = `Am4facCvkQkHjwSArPX8Jqxs1ss14XMoC8JkTV3BDG95`, classifiée PDA ("system_pda") —
  cohérent avec une autorité de mint gérée par programme plutôt qu'une clé simple (contraste avec les
  4 autorités EOA ci-dessus).

**Action prioritaire absolue dès accès réseau** : relire ces mêmes champs (freeze/pause/transferhook/
metadata authority) via `getAccountInfo` **sur mainnet** pour ce même mint. Si l'autorité pause reste
la même clé simple (`98Ck1Kw...` ou son équivalent mainnet) plutôt qu'une PDA Squads, c'est une
divergence documentée vs réalité directement soumissible comme finding (après confirmation du mapping
exact avec le modèle de confiance officiel — "DAWN's own USD.infra Token-2022 global pause", sans
préciser l'autorité exacte, donc à vérifier si Squads est VRAIMENT le détenteur annoncé ou juste
l'exécuteur habituel des actions borrow/repay, la pause pouvant être câblée différemment).

## Résultat 3 — sUSD.infra identifié + TVL réel

Via `alex0xhodler/defi_garden` (miroir de données DefiLlama) :
- **Mint sUSD.infra (parts du vault) = `GvEMgNT6GKiYTvg7TskDio6RKzQdCuhwmH55tVCLaJTe`** — adresse
  jusqu'ici inconnue, utile pour toute future analyse de compte (ex. vérifier son autorité, ses
  extensions Token-2022 si applicable).
- TVL USD.INFRA (pool "loopscale-lending") : **~$9.34M** au 2026-10-03, APY base 1.11% + reward 3.57%.
- Pool secondaire USD.INFRA/sUSD.INFRA sur Orca (DEX) : ~$817K TVL — donc sUSD.infra est aussi tradé
  sur un AMM public, pas seulement rachetable via le vault. **Nouvelle surface non couverte par nos 17
  pistes** : un déséquilibre entre le prix AMM de sUSD.infra et le NAV "officiel" publié pourrait être
  arbitré, et la liquidité AMM elle-même (817K, bien plus petite que les 9.34M TVL) est une cible de
  manipulation de prix spot moins chère que d'attaquer le vault lui-même. À ajouter comme piste C-18
  dans la prochaine consolidation.

## Résumé des mises à jour nécessaires sur `01-consolidated-leads-round2.md`

- C-01 : préciser la nouvelle évidence Kamino Scope/Exponent (ce document).
- C-04/C-15 : ajouter la référence à l'autorité EOA unique observée en devnet (ce document, avec caveat).
- Nouvelle piste **C-18** : marché secondaire sUSD.infra/USD.infra sur Orca (817K TVL) — divergence
  prix-AMM vs NAV-officiel, et profondeur de liquidité largement inférieure au TVL total du vault.
- Nouvelle donnée : adresse sUSD.infra (`GvEMgNT6GKiYTvg7TskDio6RKzQdCuhwmH55tVCLaJTe`) à ajouter à
  l'inventaire d'assets pour toute future lecture on-chain.
