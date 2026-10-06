# Vérification CashDraft 1.0

## Vérifié le 1er octobre 2026

- Compilation iOS et Mac Catalyst non signée réussie avec `xcodebuild` (la signature dépend du compte Apple Developer local).
- Cible de tests Swift compilée ; les tests couvrent remises, TVA par taux, paiements, avoirs, sauvegarde, archives, pièces jointes et signatures. L’exécution sur simulateur n’a pas été possible, car le service CoreSimulator local est indisponible.
- Fichier StoreKit local présent pour les quatre produits.
- Captures iPhone 6,1 pouces préparées et contrôlées en JPEG 1170 × 2532.

## À vérifier sur iPhone/TestFlight avant soumission

- Première installation : cinq émissions Studio, puis brouillon filigrané sans crédit.
- Achat, restauration et expiration Sandbox des quatre droits StoreKit.
- PDF émis, verrouillage, réexport après changement de profil (doit rester identique), récapitulatif TVA.
- Notifications locales à J-7, J0 et J+1 ; annulation après passage payé/annulé.
- Export CSV et sauvegarde/import JSON avec pièces jointes et modèles.
- Synchronisation iCloud facultative sur deux appareils et conflit « dernière modification ».
