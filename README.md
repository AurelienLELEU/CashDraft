# CashDraft

Application iOS de devis et facturation locale, conçue pour les indépendants français.

Support et confidentialité : <https://aurelienleleu.github.io/CashDraft/>

## Démarrage

Ouvrir `CashDraft.xcodeproj` avec Xcode 16+ puis sélectionner un simulateur iPhone (iOS 17 minimum) ou la destination **My Mac (Mac Catalyst)**. Aucune dépendance externe ni connexion réseau n’est nécessaire.

## Achats intégrés

Les produits App Store Connect sont :

- `com.cashdraft.credits.20` — consommable, 20 émissions de documents ;
- `com.cashdraft.pro.lifetime` — non-consommable, documents de base illimités ;
- `com.cashdraft.studio.monthly` — abonnement mensuel Studio ;
- `com.cashdraft.studio.yearly` — abonnement annuel Studio.

Le fichier `CashDraft/Supporting/CashDraft.storekit` fournit le scénario StoreKit local pour les tests.

Les données métier résident exclusivement dans `Application Support/CashDraft/cashdraft.sqlite`; les sauvegardes sont des fichiers JSON que l’utilisateur choisit de partager ou conserver.

## Limite importante des crédits consommables

Apple ne restaure pas les achats intégrés **consommables** (le pack de 20 crédits) sur un nouvel appareil. La licence Pro Lifetime, elle, est restaurable nativement. Pour garantir la restauration des crédits sur un nouvel appareil tout en évitant les doublons, il faudrait un compte utilisateur et une vérification côté serveur — ce qui modifierait la promesse « 100 % offline ».

Le MVP fait donc le choix sans infrastructure : la licence et les crédits restants sont aussi sauvegardés dans le Keychain. Ils survivent à une réinstallation sur le **même iPhone** ; une sauvegarde JSON permet en plus à l’utilisateur de conserver ses données métier.
