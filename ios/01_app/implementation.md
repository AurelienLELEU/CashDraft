# Implémentation CashDraft 1.0

- Architecture native SwiftUI, stockage local SQLite et données de licence sécurisées par le système.
- Pas de serveur exploité par BTBU. iCloud/CloudKit est une synchronisation facultative Studio, vers la base privée de l’utilisateur.
- PDF figé et sauvegardé lors de la première émission ; les exports ultérieurs utilisent cette archive.
- Achats StoreKit locaux configurés : crédits, Pro Lifetime, Studio mensuel et annuel.
- Les documents restent en brouillon sans droit d’émission ; le partage d’un brouillon l’émet et applique le droit requis.
