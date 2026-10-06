# CashDraft

Deux applications natives dans un seul dépôt, avec données métier locales et sans serveur CashDraft.

- [iOS](ios/README.md) : projet SwiftUI existant, déplacé sans modification dans `ios/` ; ouvrir `ios/CashDraft.xcodeproj` sur macOS.
- [Android](android/README.md) : application Kotlin et Jetpack Compose, avec un module métier testable indépendamment du SDK Android.

Le déplacement conserve les chemins relatifs internes du projet Xcode. Les documents et anciennes pages GitHub Pages restent dans `ios/docs/` ; leur source de publication doit être adaptée si ce dépôt publie encore ces pages. Le site commun est https://btbu.aurelienleleu.fr/cashdraft/.

Les fonctions de paiement et de synchronisation sont propres à chaque plateforme : une licence Apple n’est pas automatiquement une licence Google Play et iCloud n’est pas disponible dans l’application Android. Aucun compte, serveur ou transfert automatique des droits d’achat entre stores n’est ajouté.