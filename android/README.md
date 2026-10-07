# CashDraft Android

Première version native Kotlin / Jetpack Compose, Android 8.0 (API 26) ou ultérieur. Projet indépendant de Xcode, dans le même dépôt que l'application iOS. Aucun serveur CashDraft, SDK publicitaire, suivi analytique ni permission Internet.

## Compilation

Ouvrir ce dossier dans Android Studio avec un JDK 17, le SDK Android 36 et les Build Tools 35.0.0. Le wrapper Gradle 8.11.1 est fourni. Android Studio configure le SDK dans `local.properties`, qui ne doit pas être versionné.

```powershell
./gradlew.bat :core:test :app:assembleDebug :app:lintDebug
```

Sur Windows, le bootstrap télécharge un JDK 17, Gradle et le SDK dans `.toolchain/`, sans installation globale. Le cache Gradle est placé dans `%LOCALAPPDATA%/CashDraftAndroid/gradle`, et les sorties de compilation dans `%LOCALAPPDATA%/CashDraftAndroid/build`, hors OneDrive. Les licences Google demandent une acceptation explicite.

```powershell
./tools/bootstrap.ps1 -CoreOnly
./tools/bootstrap.ps1
```

Le bootstrap copie l'APK de développement dans `artifacts/CashDraft-debug.apk`. Une compilation Gradle sans `-PlocalBuildRoot` conserve le chemin `app/build/outputs/apk/debug/app-debug.apk` ; dans un dossier OneDrive, passer `-PlocalBuildRoot="$env:LOCALAPPDATA/CashDraftAndroid/build"` pour éviter les fichiers verrouillés. L'installer sur un appareil de test. Cette version est signée pour le développement, pas pour la production Google Play ; ne pas versionner les fichiers de signature ou secrets.

La version Android 0.2.0 rapproche la présentation des listes iOS : surfaces claires, accent vert, navigation sobre, statuts et montants hiérarchisés. Les données et règles de facturation restent inchangées. Le rendu doit encore être vérifié sur un appareil Android.

## Fonctions portées

Profil d'entreprise et mentions de règlement ; clients ; catalogue HT/TVA ; devis, factures, avoirs et notes d'honoraires ; remises ; acomptes et retenues ; paiements partiels et solde ; conversion devis/facture ; création d'avoir ; historique ; corbeille avec restauration ; PDF multipage et partage Android ; sauvegarde JSON et restauration avec aperçu et confirmation.

Les données et droits d'essai sont stockés dans SQLite et écrits en transaction. L'émission fige le document et archive le PDF dans la même transaction que la consommation du droit. Les partages ultérieurs reprennent ces octets, sans consommer de droit. L'aperçu porte la mention BROUILLON et n'émet pas le document. Les documents émis ne peuvent pas être modifiés ni supprimés définitivement ; ils restent dans la corbeille pour conserver leur numéro.

Cinq émissions d'essai sur une nouvelle installation. Google Play Billing n'est pas intégré : après l'essai, les brouillons et leur aperçu restent disponibles, mais aucune émission supplémentaire n'est autorisée. Cette version ne garantit pas un essai unique après réinstallation et n'est pas commercialisable en l'état.

## Sauvegardes iOS et Android

Format métier CashDraft `1.0`, dates ISO 8601, identifiants stables, documents supprimés et PDF base64. Les droits d'achat ne sont pas importés. Les champs iOS non édités sur Android sont conservés dans le JSON : signatures, pièces jointes, entités commerciales et modèles. Ils ne sont pas encore utilisables dans l'interface Android ni rendus dans les nouveaux PDF. Un PDF émis importé sans archive n'est pas recréé avec le profil actuel : le réexporter depuis l'appareil d'origine.

Le sélecteur Android laisse choisir la destination sans permission globale sur les fichiers. Le JSON n'est pas chiffré : choisir une destination privée. L'import remplace les données après confirmation ; une copie avant import est conservée sur l'appareil et restaurable depuis Réglages. Limite de cette version : 50 Mo par sauvegarde/base métier. Les sauvegardes système et transferts automatiques Android sont désactivés pour éviter de copier les droits locaux.

Les achats Apple et l'accès Studio Apple ne sont pas transférés. Vérifier sur iOS tout champ avancé importé avant émission d'un nouveau PDF Android : cette première version ne propose pas la parité complète du rendu.

## Avant publication

Restent à intégrer : Play Billing et validation des achats ; identité sécurisée des droits d'essai ; restauration des achats ; synchronisation Android à choisir séparément d'iCloud ; signatures ; pièces jointes ; modèles ; entités commerciales ; logos et personnalisation PDF ; rappels d'échéance ; export comptable CSV ; contacts/adresses détaillés ; correction des paiements ; validation métier et mentions juridiques avancées. Faire vérifier les obligations françaises applicables avant utilisation réelle.

## Vérification

Tests JVM : remises avant TVA, ventilation par taux, paiements, avoir négatif et remise en montant, consommation unique, verrouillage et stabilité du PDF, corbeille/numérotation, sauvegardes et champs iOS préservés.

```powershell
./gradlew.bat -PcoreOnly=true :core:test
./gradlew.bat :app:assembleDebugAndroidTest
./gradlew.bat :app:connectedDebugAndroidTest
```

La dernière commande nécessite un appareil ou émulateur. Les tests instrumentés contrôlent SQLite au-delà de la taille d'un curseur, la sauvegarde avant import sans réinitialisation des droits, un PDF multipage non blanc et la navigation. Compilation/lint ne remplacent pas une vérification visuelle : petit et grand écran, clavier ouvert, rotation, redémarrage, partage et sélecteur de fichiers.

Le projet iOS reste dans `../ios/` ; Idle Crystal Corp et StockChef ne sont pas modifiés.

État vérifié sur ce poste Windows : 11 tests JVM réussis, APK de développement et APK des tests instrumentés compilés, lint sans erreur (avertissements de mises à jour et suggestions de style conservés). Aucun appareil/émulateur connecté : tests instrumentés et contrôle visuel non exécutés. Les 29 fichiers iOS déplacés ont été vérifiés identiques avant/après déplacement ; la compilation Xcode n'a pas été relancée, car elle exige macOS.