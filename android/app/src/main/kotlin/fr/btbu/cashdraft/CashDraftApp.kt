package fr.btbu.cashdraft

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ReceiptLong
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import fr.btbu.cashdraft.core.*
import kotlinx.serialization.encodeToString
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

private val colors = lightColorScheme(primary = Color(0xFF17694C), secondary = Color(0xFF9A3655), tertiary = Color(0xFF80651E), surface = Color(0xFFFAFBFA), background = Color(0xFFFAFBFA), surfaceVariant = Color(0xFFE7EEE9))

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CashDraftApp(onShare: (ByteArray, String) -> Unit, model: CashViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    var route by rememberSaveable { mutableStateOf("documents") }
    var selectedId by rememberSaveable { mutableStateOf("") }
    var pendingIssue by remember { mutableStateOf<BillingDocument?>(null) }
    var leaveEditor by remember { mutableStateOf(false) }
    val snapshot = state.snapshot
    val home = { route = "documents" }
    fun open(next: String, id: String = "") { selectedId = id; route = next }
    val editing = route in listOf("documentEdit", "clientEdit", "catalogEdit", "profile")
    BackHandler(route !in listOf("documents", "clients", "catalog", "settings")) {
        if (editing) leaveEditor = true else home()
    }
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri -> uri?.let(model::exportBackup) }
    val import = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let(model::previewBackup) }

    MaterialTheme(colorScheme = colors, typography = Typography()) {
        Scaffold(
            topBar = {
                TopAppBar(title = { Text(when (route) {
                    "clients" -> "Clients"; "catalog" -> "Catalogue"; "settings" -> "Réglages"; "profile" -> "Mon entreprise"; "trash" -> "Corbeille"; "documentEdit" -> "Document"; "clientEdit" -> "Client"; "catalogEdit" -> "Article"; "detail" -> snapshot?.documents?.find { it.id == selectedId }?.number ?: "Document"; else -> "CashDraft"
                }, maxLines = 1) }, navigationIcon = {
                    if (route !in listOf("documents", "clients", "catalog", "settings")) Tool(Icons.AutoMirrored.Filled.ArrowBack, "Retour", !state.busy) { if (editing) leaveEditor = true else home() }
                })
            },
            bottomBar = {
                if (route in listOf("documents", "clients", "catalog", "settings")) NavigationBar {
                    listOf(Triple("documents", "Documents", Icons.AutoMirrored.Filled.ReceiptLong), Triple("clients", "Clients", Icons.Default.People), Triple("catalog", "Catalogue", Icons.Default.Inventory2), Triple("settings", "Réglages", Icons.Default.Settings)).forEach { (destination, label, icon) ->
                        NavigationBarItem(selected = route == destination, onClick = { route = destination }, enabled = !state.busy, icon = { Icon(icon, label) }, label = { Text(label, maxLines = 1) })
                    }
                }
            },
            floatingActionButton = {
                if (snapshot != null && route in listOf("documents", "clients", "catalog") && !state.busy) FloatingActionButton(onClick = {
                    open(when (route) { "clients" -> "clientEdit"; "catalog" -> "catalogEdit"; else -> "documentEdit" })
                }) { Icon(Icons.Default.Add, "Ajouter") }
            }
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).imePadding()) {
                if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (snapshot == null) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        if (state.busy) CircularProgressIndicator() else Button(onClick = model::load) { Text("Réessayer le chargement") }
                    }
                } else when (route) {
                    "documents" -> Documents(snapshot, onOpen = { open("detail", it.id) })
                    "trash" -> Documents(snapshot, trash = true, onOpen = { open("detail", it.id) })
                    "clients" -> Clients(snapshot) { open("clientEdit", it.id) }
                    "catalog" -> Catalog(snapshot) { open("catalogEdit", it.id) }
                    "profile" -> ProfileEditor(snapshot.profile, state.busy) { model.saveProfile(it) { route = "settings" } }
                    "clientEdit" -> ClientEditor(snapshot.clients.find { it.id == selectedId }, state.busy, onSave = { model.saveClient(it) { route = "clients" } }, onDelete = { model.deleteClient(it) { route = "clients" } })
                    "catalogEdit" -> CatalogEditor(snapshot.catalog.find { it.id == selectedId }, state.busy, onSave = { model.saveCatalog(it) { route = "catalog" } }, onDelete = { model.deleteCatalog(it) { route = "catalog" } })
                    "documentEdit" -> DocumentEditor(snapshot, snapshot.documents.find { it.id == selectedId }, state.busy) { document -> model.saveDocument(document) { open("detail", document.id) } }
                    "detail" -> {
                        val document = snapshot.documents.find { it.id == selectedId }
                        if (document == null) LaunchedEffect(Unit) { home() } else DocumentDetail(snapshot, document, state.busy,
                            onEdit = { open("documentEdit", document.id) },
                            onShare = { if (document.status == DocumentStatus.DRAFT) pendingIssue = document else model.pdf(document.id) { onShare(it, document.number) } },
                            onPreview = { model.pdf(document.id, true) { onShare(it, "BROUILLON-${document.number}") } },
                            onPayment = { model.addPayment(document.id, it) {} },
                            onTrash = { model.trash(document.id, document.deletedAt != null) { route = if (document.deletedAt == null) "documents" else "trash" } },
                            onDelete = { model.deleteDraft(document.id) { route = "trash" } },
                            onConvert = { model.convertQuote(document.id, home) }, onCredit = { model.createCredit(document.id, home) })
                    }
                    "settings" -> Settings(state, onProfile = { route = "profile" }, onExport = { export.launch("CashDraft-${LocalDate.now()}.json") }, onImport = { import.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) }, onPrevious = model::restorePrevious, onTrash = { route = "trash" })
                }
            }
        }

        state.error?.let { message -> AlertDialog(onDismissRequest = model::dismissError, title = { Text("Opération impossible") }, text = { Text(message) }, confirmButton = { TextButton(onClick = model::dismissError) { Text("Fermer") } }) }
        state.notice?.let { message -> AlertDialog(onDismissRequest = model::dismissError, text = { Text(message) }, confirmButton = { TextButton(onClick = model::dismissError) { Text("OK") } }) }
        state.importPreview?.let { preview -> AlertDialog(onDismissRequest = model::dismissImport, title = { Text("Restaurer cette sauvegarde ?") }, text = { Text("${preview.profile.name}\n${preview.clients.size} clients · ${preview.catalog.size} articles\n${preview.documents.size} documents, dont ${preview.documents.count { it.deletedAt != null }} dans la corbeille.\n\nLes données actuelles seront remplacées. Une copie avant import sera conservée sur cet appareil. Les achats ne sont pas importés.") }, dismissButton = { TextButton(onClick = model::dismissImport, enabled = !state.busy) { Text("Annuler") } }, confirmButton = { TextButton(onClick = model::confirmImport, enabled = !state.busy) { Text("Restaurer") } }) }
        pendingIssue?.let { document -> AlertDialog(onDismissRequest = { pendingIssue = null }, title = { Text("Émettre ${document.number} ?") }, text = { Text("Le document et son PDF seront figés. Cette première émission utilise un droit d'émission ; les partages suivants n'en utilisent pas.") }, dismissButton = { TextButton(onClick = { pendingIssue = null }) { Text("Annuler") } }, confirmButton = { TextButton(onClick = { pendingIssue = null; model.pdf(document.id) { onShare(it, document.number) } }) { Text("Émettre et partager") } }) }
        if (leaveEditor) AlertDialog(onDismissRequest = { leaveEditor = false }, title = { Text("Quitter sans enregistrer ?") }, dismissButton = { TextButton(onClick = { leaveEditor = false }) { Text("Continuer") } }, confirmButton = { TextButton(onClick = { leaveEditor = false; home() }) { Text("Quitter") } })
    }
}

@Composable
private fun Tool(icon: ImageVector, label: String, enabled: Boolean = true, action: () -> Unit) {
    IconButton(onClick = action, enabled = enabled) { Icon(icon, label) }
}

@Composable
private fun Section(title: String) {
    Text(title, Modifier.padding(top = 14.dp, bottom = 4.dp), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
}

@Composable
private fun Field(label: String, value: String, multiline: Boolean = false, change: (String) -> Unit) {
    OutlinedTextField(value, change, Modifier.fillMaxWidth(), label = { Text(label) }, singleLine = !multiline, minLines = if (multiline) 2 else 1)
}

@Composable
private fun NumberField(label: String, value: Double?, invalid: (Boolean) -> Unit = {}, change: (Double) -> Unit) {
    var text by rememberSaveable { mutableStateOf(value?.toString()?.removeSuffix(".0")?.replace('.', ',') ?: "") }
    val parsed = text.replace(',', '.').toDoubleOrNull()
    val bad = text.isNotBlank() && (parsed == null || !parsed.isFinite())
    LaunchedEffect(bad) { invalid(bad) }
    OutlinedTextField(text, { input ->
        if (input.length <= 18 && Regex("-?[0-9]*([.,][0-9]*)?").matches(input)) {
            text = input
            val amount = input.replace(',', '.').toDoubleOrNull()
            invalid(input.isNotBlank() && (amount == null || !amount.isFinite()))
            if (amount?.isFinite() == true) change(amount) else if (input.isBlank()) change(0.0)
        }
    }, Modifier.fillMaxWidth(), label = { Text(label) }, isError = bad, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
}

@Composable
private fun Save(enabled: Boolean, action: () -> Unit) {
    Button(onClick = action, enabled = enabled, modifier = Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 24.dp)) {
        Icon(Icons.Default.Save, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Enregistrer")
    }
}

@Composable
private fun Documents(snapshot: Snapshot, trash: Boolean = false, onOpen: (BillingDocument) -> Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    var filter by rememberSaveable { mutableStateOf("Tous") }
    val documents = snapshot.documents.filter { (it.deletedAt != null) == trash }.sortedByDescending { it.issueDate }
    val shown = documents.filter { document ->
        val client = snapshot.clients.find { it.id == document.clientID }
        (filter == "Tous" || document.status.title == filter) && (document.number.contains(search, true) || client?.displayName?.contains(search, true) == true)
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (!trash) item {
            val issued = documents.filter { it.status == DocumentStatus.SENT || it.status == DocumentStatus.PAID }.filter { it.type != DocumentType.CREDIT_NOTE && (it.currencyCode ?: snapshot.profile.currencyCode) == snapshot.profile.currencyCode }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column { Text("À encaisser", style = MaterialTheme.typography.labelMedium); Text(money(issued.fold(BigDecimal.ZERO) { total, document -> total.add(document.netToPay) }, snapshot.profile.currencyCode), style = MaterialTheme.typography.headlineSmall, color = colors.primary) }
                Column(horizontalAlignment = Alignment.End) { Text("Documents", style = MaterialTheme.typography.labelMedium); Text(documents.size.toString(), style = MaterialTheme.typography.headlineSmall) }
            }
        }
        item { OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), leadingIcon = { Icon(Icons.Default.Search, null) }, label = { Text("Numéro ou client") }, singleLine = true) }
        item { LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { items(listOf("Tous") + DocumentStatus.entries.map { it.title }) { status -> FilterChip(filter == status, { filter = status }, label = { Text(status) }) } } }
        if (shown.isEmpty()) item { Text(if (trash) "La corbeille est vide." else "Aucun document.", Modifier.padding(vertical = 24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(shown, key = { it.id }) { document ->
            OutlinedCard(onClick = { onOpen(document) }, modifier = Modifier.fillMaxWidth(), shape = androidx.compose.foundation.shape.RoundedCornerShape(8.dp)) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(document.number.ifBlank { document.type.title }, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f)); Text(document.status.title, style = MaterialTheme.typography.labelMedium, color = if (document.status == DocumentStatus.PAID) colors.primary else colors.secondary) }
                    Text(snapshot.clients.find { it.id == document.clientID }?.displayName ?: "Client non sélectionné", style = MaterialTheme.typography.bodyMedium)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(frenchDate(document.issueDate), style = MaterialTheme.typography.labelMedium); Text(money(document.totalTTC, document.currencyCode ?: snapshot.profile.currencyCode), fontWeight = FontWeight.Medium) }
                    if (document.status == DocumentStatus.SENT && document.netToPay.signum() > 0 && Instant.parse(document.dueDate) < Instant.now()) Text("Échéance dépassée · ${frenchDate(document.dueDate)}", style = MaterialTheme.typography.labelMedium, color = colors.secondary)
                }
            }
        }
    }
}

@Composable
private fun Clients(snapshot: Snapshot, open: (Client) -> Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    LazyColumn(contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp)) {
        item { Field("Rechercher un client", search) { search = it } }
        if (snapshot.clients.isEmpty()) item { Text("Aucun client.", Modifier.padding(vertical = 24.dp)) }
        items(snapshot.clients.filter { it.displayName.contains(search, true) }.sortedBy { it.displayName.lowercase() }, key = { it.id }) { client ->
            ListItem(headlineContent = { Text(client.displayName) }, supportingContent = { Text(listOf(client.email, client.address).filter { it.isNotBlank() }.joinToString(" · ")) }, leadingContent = { Icon(Icons.Default.Person, null) }, modifier = Modifier.clickable { open(client) })
            HorizontalDivider()
        }
    }
}

@Composable
private fun Catalog(snapshot: Snapshot, open: (CatalogItem) -> Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    LazyColumn(contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp)) {
        item { Field("Rechercher un article", search) { search = it } }
        if (snapshot.catalog.isEmpty()) item { Text("Aucun article.", Modifier.padding(vertical = 24.dp)) }
        items(snapshot.catalog.filter { it.description.contains(search, true) }.sortedBy { it.description.lowercase() }, key = { it.id }) { item ->
            ListItem(headlineContent = { Text(item.description) }, supportingContent = { Text("${money(decimal(item.unitPriceHT), snapshot.profile.currencyCode)} HT / ${item.unit} · TVA ${item.vatRate} %") }, modifier = Modifier.clickable { open(item) })
            HorizontalDivider()
        }
    }
}

@Composable
private fun ProfileEditor(initial: CompanyProfile, busy: Boolean, save: (CompanyProfile) -> Unit) {
    val saver = Saver<CompanyProfile, String>(save = { BackupCodec.json.encodeToString(it) }, restore = { BackupCodec.json.decodeFromString(it) })
    var profile by rememberSaveable(stateSaver = saver) { mutableStateOf(initial) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Section("Identité")
        Field("Raison sociale", profile.name) { profile = profile.copy(name = it) }
        Field("Forme juridique", profile.legalForm) { profile = profile.copy(legalForm = it) }
        Field("Adresse", profile.address, true) { profile = profile.copy(address = it) }
        Field("SIRET", profile.siret) { profile = profile.copy(siret = it) }
        Field("Numéro de TVA", profile.vatNumber) { profile = profile.copy(vatNumber = it) }
        Field("Email", profile.email) { profile = profile.copy(email = it) }
        Field("Téléphone", profile.phone) { profile = profile.copy(phone = it) }
        Section("Règlement et mentions")
        Field("Conditions de règlement", profile.defaultPaymentTerms, true) { profile = profile.copy(defaultPaymentTerms = it) }
        Field("Mention d'exonération de TVA", profile.vatExemptionNotice, true) { profile = profile.copy(vatExemptionNotice = it) }
        Field("Escompte", profile.earlyPaymentDiscountText.orEmpty(), true) { profile = profile.copy(earlyPaymentDiscountText = it) }
        Field("Pénalités de retard", profile.latePaymentPenaltyText.orEmpty(), true) { profile = profile.copy(latePaymentPenaltyText = it) }
        Field("Indemnité de recouvrement", profile.recoveryIndemnityText.orEmpty(), true) { profile = profile.copy(recoveryIndemnityText = it) }
        Field("IBAN", profile.iban.orEmpty()) { profile = profile.copy(iban = it) }
        Field("BIC", profile.bic.orEmpty()) { profile = profile.copy(bic = it) }
        Field("Pied de page", profile.footerText.orEmpty(), true) { profile = profile.copy(footerText = it) }
        Save(!busy) { save(profile) }
    }
}

@Composable
private fun ClientEditor(initial: Client?, busy: Boolean, onSave: (Client) -> Unit, onDelete: (String) -> Unit) {
    val saver = Saver<Client, String>(save = { BackupCodec.json.encodeToString(it) }, restore = { BackupCodec.json.decodeFromString(it) })
    var client by rememberSaveable(initial?.id, stateSaver = saver) { mutableStateOf(initial ?: Client()) }
    var confirmDelete by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Field("Entreprise ou nom", client.companyName) { client = client.copy(companyName = it) }
        Field("Contact", client.contactName) { client = client.copy(contactName = it) }
        Field("Adresse", client.address, true) { client = client.copy(address = it) }
        Field("Email", client.email) { client = client.copy(email = it) }
        Field("Téléphone", client.phone) { client = client.copy(phone = it) }
        Field("SIRET", client.siret) { client = client.copy(siret = it) }
        Field("Numéro de TVA", client.vatNumber.orEmpty()) { client = client.copy(vatNumber = it) }
        Save(!busy && client.displayName.isNotBlank()) { onSave(client) }
        if (initial != null) TextButton(onClick = { confirmDelete = true }, enabled = !busy) { Icon(Icons.Default.Delete, null); Text("Supprimer le client") }
    }
    if (confirmDelete) DeleteConfirmation("Supprimer ce client ?", { confirmDelete = false }) { onDelete(client.id); confirmDelete = false }
}

@Composable
private fun CatalogEditor(initial: CatalogItem?, busy: Boolean, onSave: (CatalogItem) -> Unit, onDelete: (String) -> Unit) {
    val saver = Saver<CatalogItem, String>(save = { BackupCodec.json.encodeToString(it) }, restore = { BackupCodec.json.decodeFromString(it) })
    var item by rememberSaveable(initial?.id, stateSaver = saver) { mutableStateOf(initial ?: CatalogItem()) }
    var invalidPrice by remember { mutableStateOf(false) }
    var invalidVat by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Field("Libellé", item.description, true) { item = item.copy(description = it) }
        NumberField("Prix unitaire HT", item.unitPriceHT, { invalidPrice = it }) { item = item.copy(unitPriceHT = it) }
        NumberField("TVA (%)", item.vatRate, { invalidVat = it }) { item = item.copy(vatRate = it) }
        Field("Unité", item.unit) { item = item.copy(unit = it) }
        Save(!busy && item.description.isNotBlank() && !invalidPrice && !invalidVat) { onSave(item) }
        if (initial != null) TextButton(onClick = { confirmDelete = true }, enabled = !busy) { Icon(Icons.Default.Delete, null); Text("Supprimer l'article") }
    }
    if (confirmDelete) DeleteConfirmation("Supprimer cet article ?", { confirmDelete = false }) { onDelete(item.id); confirmDelete = false }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DocumentEditor(snapshot: Snapshot, initial: BillingDocument?, busy: Boolean, save: (BillingDocument) -> Unit) {
    val saver = Saver<BillingDocument, String>(save = { BackupCodec.json.encodeToString(it) }, restore = { BackupCodec.json.decodeFromString(it) })
    var document by rememberSaveable(initial?.id, stateSaver = saver) { mutableStateOf(initial ?: BillingDocument(number = DocumentRules.nextNumber(snapshot, DocumentType.INVOICE), items = listOf(DocumentItem()), currencyCode = snapshot.profile.currencyCode)) }
    var selectClient by remember { mutableStateOf(false) }
    var selectCatalog by remember { mutableStateOf(false) }
    var invalidNumbers by remember { mutableStateOf(setOf<String>()) }
    var issueDateValid by remember { mutableStateOf(true) }
    var dueDateValid by remember { mutableStateOf(true) }
    fun invalid(key: String, bad: Boolean) { invalidNumbers = if (bad) invalidNumbers + key else invalidNumbers - key }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { items(DocumentType.entries.toList()) { type -> FilterChip(document.type == type, {
            document = document.copy(type = type, number = DocumentRules.nextNumber(snapshot, type, DocumentRules.year(document)))
        }, label = { Text(type.title) }) } }
        Field("Numéro", document.number) { document = document.copy(number = it) }
        OutlinedButton(onClick = { selectClient = true }, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.Person, null); Spacer(Modifier.width(8.dp)); Text(snapshot.clients.find { it.id == document.clientID }?.displayName ?: "Sélectionner un client") }
        DateField("Date d'émission (AAAA-MM-JJ)", document.issueDate, { issueDateValid = it }) { document = document.copy(issueDate = it) }
        DateField("Échéance (AAAA-MM-JJ)", document.dueDate, { dueDateValid = it }) { document = document.copy(dueDate = it) }
        Field("Projet", document.projectTitle.orEmpty()) { document = document.copy(projectTitle = it) }
        Field("Référence", document.projectReference.orEmpty()) { document = document.copy(projectReference = it) }
        Field("Bon de commande", document.purchaseOrderNumber.orEmpty()) { document = document.copy(purchaseOrderNumber = it) }
        Section("Lignes")
        document.items.forEach { item -> key(item.id) {
            HorizontalDivider()
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Ligne ${document.items.indexOf(item) + 1}", Modifier.weight(1f), fontWeight = FontWeight.Medium)
                Tool(Icons.Default.Delete, "Supprimer la ligne") { document = document.copy(items = document.items.filterNot { it.id == item.id }); invalidNumbers = invalidNumbers.filterNot { it.endsWith(item.id) }.toSet() }
            }
            fun update(value: DocumentItem) { document = document.copy(items = document.items.map { if (it.id == value.id) value else it }) }
            Field("Description", item.description, true) { update(item.copy(description = it)) }
            NumberField("Quantité", item.quantity, { invalid("quantity-${item.id}", it) }) { update(item.copy(quantity = it)) }
            Field("Unité", item.unitLabel.orEmpty()) { update(item.copy(unitLabel = it)) }
            NumberField("Prix unitaire HT", item.unitPriceHT, { invalid("price-${item.id}", it) }) { update(item.copy(unitPriceHT = it)) }
            NumberField("TVA (%)", item.vatRate, { invalid("vat-${item.id}", it) }) { update(item.copy(vatRate = it)) }
            NumberField("Remise de ligne (%)", item.discountPercent, { invalid("discount-${item.id}", it) }) { update(item.copy(discountPercent = it)) }
            Text("Total HT : ${money(item.totalLineHT, document.currencyCode ?: snapshot.profile.currencyCode)}", style = MaterialTheme.typography.bodyMedium)
        } }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { document = document.copy(items = document.items + DocumentItem()) }) { Icon(Icons.Default.Add, null); Text("Ligne") }
            OutlinedButton(onClick = { selectCatalog = true }) { Icon(Icons.Default.Inventory2, null); Text("Catalogue") }
        }
        Section("Remises et acomptes")
        NumberField("Remise globale (%)", document.globalDiscountPercent, { invalid("global", it) }) { document = document.copy(globalDiscountPercent = it, globalDiscountAmount = null) }
        NumberField("Acompte déjà reçu", document.depositAmount, { invalid("deposit", it) }) { document = document.copy(depositAmount = it) }
        NumberField("Retenue", document.retentionAmount, { invalid("retention", it) }) { document = document.copy(retentionAmount = it) }
        Field("Notes", document.notes, true) { document = document.copy(notes = it) }
        Totals(document, snapshot.profile.currencyCode)
        Save(!busy && invalidNumbers.isEmpty() && issueDateValid && dueDateValid) { save(document) }
    }
    if (selectClient) AlertDialog(onDismissRequest = { selectClient = false }, title = { Text("Client") }, text = { LazyColumn(Modifier.heightIn(max = 380.dp)) {
        if (snapshot.clients.isEmpty()) item { Text("Aucun client enregistré.") }
        items(snapshot.clients.sortedBy { it.displayName }, key = { it.id }) { client -> ListItem(headlineContent = { Text(client.displayName) }, modifier = Modifier.clickable { document = document.copy(clientID = client.id); selectClient = false }) }
    } }, confirmButton = { TextButton(onClick = { selectClient = false }) { Text("Fermer") } })
    if (selectCatalog) AlertDialog(onDismissRequest = { selectCatalog = false }, title = { Text("Catalogue") }, text = { LazyColumn(Modifier.heightIn(max = 380.dp)) {
        if (snapshot.catalog.isEmpty()) item { Text("Aucun article enregistré.") }
        items(snapshot.catalog, key = { it.id }) { item -> ListItem(headlineContent = { Text(item.description) }, modifier = Modifier.clickable { document = document.copy(items = document.items + DocumentItem(description = item.description, unitPriceHT = item.unitPriceHT, vatRate = item.vatRate, unitLabel = item.unit)); selectCatalog = false }) }
    } }, confirmButton = { TextButton(onClick = { selectCatalog = false }) { Text("Fermer") } })
}

@Composable
private fun DateField(label: String, value: String, valid: (Boolean) -> Unit, change: (String) -> Unit) {
    var text by rememberSaveable { mutableStateOf(value.take(10)) }
    val date = runCatching { LocalDate.parse(text) }.getOrNull()
    LaunchedEffect(date != null) { valid(date != null) }
    OutlinedTextField(text, { text = it; val parsed = runCatching { LocalDate.parse(it) }.getOrNull(); valid(parsed != null); parsed?.let { day -> change(day.atStartOfDay().toInstant(ZoneOffset.UTC).toString()) } }, Modifier.fillMaxWidth(), label = { Text(label) }, singleLine = true, isError = date == null, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii))
}

@Composable
private fun Totals(document: BillingDocument, currency: String) {
    val code = document.currencyCode ?: currency
    HorizontalDivider()
    listOf("Total HT" to document.totalHT, "TVA" to document.totalVAT, "Total TTC" to document.totalTTC, "Encaissé" to document.paidAmount, (if (document.type == DocumentType.CREDIT_NOTE) "Montant de l'avoir" else "Reste à payer") to (if (document.type == DocumentType.CREDIT_NOTE) document.creditAmount else document.netToPay)).forEach { (label, amount) ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(label, Modifier.weight(1f)); Text(money(amount, code), fontWeight = FontWeight.Medium) }
    }
}

@Composable
private fun DocumentDetail(snapshot: Snapshot, document: BillingDocument, busy: Boolean, onEdit: () -> Unit, onShare: () -> Unit, onPreview: () -> Unit, onPayment: (DocumentPayment) -> Unit, onTrash: () -> Unit, onDelete: () -> Unit, onConvert: () -> Unit, onCredit: () -> Unit) {
    var payment by remember { mutableStateOf(false) }
    var delete by remember { mutableStateOf(false) }
    val draft = document.status == DocumentStatus.DRAFT
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("${document.type.title} · ${document.status.title}", style = MaterialTheme.typography.titleMedium, color = colors.primary)
        Text(snapshot.clients.find { it.id == document.clientID }?.displayName ?: "Client non sélectionné")
        Text("${frenchDate(document.issueDate)} · Échéance ${frenchDate(document.dueDate)}")
        document.items.forEach { item -> Column { Text(item.description, fontWeight = FontWeight.Medium); Text("${item.quantity} ${item.unitLabel.orEmpty()} · ${money(item.totalLineHT, document.currencyCode ?: snapshot.profile.currencyCode)} HT", style = MaterialTheme.typography.bodyMedium) } }
        Totals(document, snapshot.profile.currencyCode)
        if (document.deletedAt == null) {
            if (draft) OutlinedButton(onClick = onEdit, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.Edit, null); Spacer(Modifier.width(8.dp)); Text("Modifier le brouillon") }
            Button(onClick = onShare, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.Share, null); Spacer(Modifier.width(8.dp)); Text(if (draft) "Émettre et partager le PDF" else "Partager le PDF archivé") }
            if (draft) OutlinedButton(onClick = onPreview, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.Visibility, null); Spacer(Modifier.width(8.dp)); Text("Aperçu brouillon") }
            if (!draft && document.type != DocumentType.CREDIT_NOTE && document.status != DocumentStatus.CANCELLED) OutlinedButton(onClick = { payment = true }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.Payments, null); Spacer(Modifier.width(8.dp)); Text("Enregistrer un paiement") }
            if (document.type == DocumentType.QUOTE) OutlinedButton(onClick = onConvert, enabled = !busy) { Icon(Icons.AutoMirrored.Filled.ReceiptLong, null); Spacer(Modifier.width(8.dp)); Text("Convertir en facture") }
            if (!draft && document.type in listOf(DocumentType.INVOICE, DocumentType.HONORARIUM_NOTE)) OutlinedButton(onClick = onCredit, enabled = !busy) { Icon(Icons.AutoMirrored.Filled.Undo, null); Spacer(Modifier.width(8.dp)); Text("Créer un avoir") }
        }
        (document.payments ?: emptyList()).takeIf { it.isNotEmpty() }?.let { payments -> Section("Paiements"); payments.forEach { Text("${frenchDate(it.date)} · ${it.method} · ${money(decimal(it.amount), document.currencyCode ?: snapshot.profile.currencyCode)}\n${it.reference}") } }
        (document.events ?: emptyList()).takeIf { it.isNotEmpty() }?.let { events -> Section("Historique"); events.asReversed().forEach { Text("${frenchDate(it.date)} · ${it.title}", style = MaterialTheme.typography.bodySmall) } }
        TextButton(onClick = onTrash, enabled = !busy) { Icon(if (document.deletedAt != null) Icons.Default.RestoreFromTrash else Icons.Default.Delete, null); Text(if (document.deletedAt != null) "Restaurer" else "Mettre à la corbeille") }
        if (document.deletedAt != null && draft) TextButton(onClick = { delete = true }, enabled = !busy) { Text("Supprimer définitivement le brouillon") }
    }
    if (payment) PaymentDialog(document.netToPay.toDouble(), { payment = false }) { onPayment(it); payment = false }
    if (delete) DeleteConfirmation("Supprimer définitivement ce brouillon ?", { delete = false }) { onDelete(); delete = false }
}

@Composable
private fun PaymentDialog(remaining: Double, dismiss: () -> Unit, save: (DocumentPayment) -> Unit) {
    var amount by remember { mutableStateOf(remaining) }
    var method by remember { mutableStateOf("Virement") }
    var reference by remember { mutableStateOf("") }
    var invalid by remember { mutableStateOf(false) }
    AlertDialog(onDismissRequest = dismiss, title = { Text("Paiement") }, text = { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        NumberField("Montant reçu", amount, { invalid = it }) { amount = it }
        Field("Mode de paiement", method) { method = it }
        Field("Référence", reference) { reference = it }
    } }, dismissButton = { TextButton(onClick = dismiss) { Text("Annuler") } }, confirmButton = { TextButton(onClick = { save(DocumentPayment(amount = amount, method = method, reference = reference)) }, enabled = !invalid && amount > 0) { Text("Enregistrer") } })
}

@Composable
private fun DeleteConfirmation(title: String, dismiss: () -> Unit, delete: () -> Unit) {
    AlertDialog(onDismissRequest = dismiss, title = { Text(title) }, dismissButton = { TextButton(onClick = dismiss) { Text("Annuler") } }, confirmButton = { TextButton(onClick = delete) { Text("Supprimer") } })
}

@Composable
private fun Settings(state: AppState, onProfile: () -> Unit, onExport: () -> Unit, onImport: () -> Unit, onPrevious: () -> Unit, onTrash: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Section("Entreprise")
        ListItem(headlineContent = { Text(state.snapshot?.profile?.name?.ifBlank { "Mon entreprise" } ?: "Mon entreprise") }, supportingContent = { Text(state.snapshot?.profile?.siret.orEmpty()) }, leadingContent = { Icon(Icons.Default.Business, null) }, modifier = Modifier.clickable(enabled = !state.busy, onClick = onProfile))
        HorizontalDivider()
        Section("Sauvegardes")
        OutlinedButton(onClick = onExport, enabled = !state.busy, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.FileDownload, null); Spacer(Modifier.width(8.dp)); Text("Exporter la sauvegarde JSON") }
        OutlinedButton(onClick = onImport, enabled = !state.busy, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.FileUpload, null); Spacer(Modifier.width(8.dp)); Text("Importer une sauvegarde") }
        TextButton(onClick = onPrevious, enabled = !state.busy) { Icon(Icons.Default.History, null); Spacer(Modifier.width(8.dp)); Text("Revenir aux données avant import") }
        OutlinedButton(onClick = onTrash, enabled = !state.busy, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.DeleteOutline, null); Spacer(Modifier.width(8.dp)); Text("Corbeille") }
        HorizontalDivider()
        Section("Émissions")
        Text("${state.license.trialRemaining} émissions d'essai restantes · ${state.license.credits} crédits")
        Text("Achats Google Play et synchronisation : non disponibles dans cette version.", style = MaterialTheme.typography.bodySmall)
        Text("CashDraft Android 0.1.0", style = MaterialTheme.typography.labelSmall)
    }
}