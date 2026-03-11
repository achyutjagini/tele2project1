package com.example.couchbase_lite_p2p.couchbase_lite_p2p

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import com.couchbase.lite.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URI
import java.text.SimpleDateFormat
import java.util.*

class CouchbaseLiteP2pPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private lateinit var database: Database
    private lateinit var multipeerSyncManager: MultipeerSyncManager
    private var replicator: Replicator? = null
    private val scope = CoroutineScope(Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    // Collections (fully qualified to avoid clash with kotlin.collections.Collection)
    private lateinit var workOrdersCollection: com.couchbase.lite.Collection
    private lateinit var instructionsCollection: com.couchbase.lite.Collection
    private lateinit var workLogsCollection: com.couchbase.lite.Collection

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "couchbase_lite_p2p")
        channel.setMethodCallHandler(this)
        initializeCouchbase()
    }

    private fun initializeCouchbase() {
        CouchbaseLite.init(context)
        val config = DatabaseConfiguration()
        database = Database(AppConfig.DATABASE_NAME, config)

        // Create scope and collections
        workOrdersCollection = database.createCollection(
            AppConfig.COLLECTION_WORK_ORDERS, AppConfig.SCOPE_NAME
        )
        instructionsCollection = database.createCollection(
            AppConfig.COLLECTION_INSTRUCTIONS, AppConfig.SCOPE_NAME
        )
        workLogsCollection = database.createCollection(
            AppConfig.COLLECTION_WORK_LOGS, AppConfig.SCOPE_NAME
        )

        multipeerSyncManager = MultipeerSyncManager(context, database)
        setupCollectionListeners()
        setupP2PListeners()
    }

    private fun setupCollectionListeners() {
        workOrdersCollection.addChangeListener(CollectionChangeListener { _ ->
            mainHandler.post {
                channel.invokeMethod("onWorkOrdersChanged", null)
            }
        })
        workLogsCollection.addChangeListener(CollectionChangeListener { _ ->
            mainHandler.post {
                channel.invokeMethod("onWorkLogsChanged", null)
            }
        })
    }

    private fun setupP2PListeners() {
        scope.launch {
            multipeerSyncManager.syncState.collect { state ->
                val statusMap = mutableMapOf(
                    "isRunning" to state.isRunning,
                    "myPeerID" to (state.myPeerID ?: ""),
                    "connectedPeers" to state.connectedPeers.size,
                    "status" to state.syncStatus
                )
                if (state.error != null) {
                    statusMap["error"] = state.error
                }
                mainHandler.post {
                    channel.invokeMethod("onP2PStatusChanged", statusMap)
                }
            }
        }
    }

    private var syncUrl: String? = null
    private var restartAttempt = 0

    private fun startSyncGatewayReplication(urlString: String) {
        syncUrl = urlString
        restartAttempt = 0

        // Stop any existing replicator first
        replicator?.stop()
        replicator = null

        createAndStartReplicator(urlString)
    }

    private fun createAndStartReplicator(urlString: String) {
        try {
            val url = URI(urlString)
            val target = URLEndpoint(url)
            val config = ReplicatorConfiguration(target)
            config.isContinuous = true
            config.setMaxAttempts(Int.MAX_VALUE) // Never stop retrying
            config.setMaxAttemptWaitTime(10) // Retry every 10 seconds max
            config.setHeartbeat(30) // Detect broken connections within 30 seconds

            // Add all technician collections to replication
            config.addCollection(workOrdersCollection, null)
            config.addCollection(instructionsCollection, null)
            config.addCollection(workLogsCollection, null)

            replicator = Replicator(config)

            replicator?.addChangeListener { change ->
                val status = change.status
                val statusStr = when (status.activityLevel) {
                    ReplicatorActivityLevel.STOPPED -> "Stopped"
                    ReplicatorActivityLevel.OFFLINE -> "Offline"
                    ReplicatorActivityLevel.CONNECTING -> "Connecting"
                    ReplicatorActivityLevel.IDLE -> "Idle"
                    ReplicatorActivityLevel.BUSY -> "Busy"
                }
                val errorStr = status.error?.message
                val statusMap = mapOf(
                    "status" to statusStr,
                    "error" to errorStr,
                    "completed" to status.progress.completed,
                    "total" to status.progress.total
                )
                mainHandler.post {
                    channel.invokeMethod("onSyncGatewayStatusChanged", statusMap)
                }

                // Reset restart counter on successful connection
                if (status.activityLevel == ReplicatorActivityLevel.IDLE ||
                    status.activityLevel == ReplicatorActivityLevel.BUSY) {
                    restartAttempt = 0
                }

                // Auto-restart with exponential backoff when replicator stops unexpectedly
                if (status.activityLevel == ReplicatorActivityLevel.STOPPED && syncUrl != null) {
                    restartAttempt++
                    // Backoff: 5s, 10s, 15s, 20s... capped at 30s
                    val delay = (restartAttempt * 5000L).coerceAtMost(30000L)
                    Log.i("CouchbaseLiteP2p", "Replicator stopped — retry #$restartAttempt in ${delay/1000}s")
                    mainHandler.postDelayed({
                        if (syncUrl != null) {
                            createAndStartReplicator(syncUrl!!)
                        }
                    }, delay)
                }
            }

            replicator?.start()
        } catch (e: Exception) {
            mainHandler.post {
                channel.invokeMethod("onSyncGatewayStatusChanged", mapOf(
                    "status" to "Error",
                    "error" to e.message
                ))
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // Work Orders
            "getWorkOrders" -> {
                scope.launch {
                    try {
                        val status = call.argument<String>("status")
                        val orders = getWorkOrders(status)
                        result.success(orders)
                    } catch (e: Exception) {
                        result.error("DB_ERROR", e.message, null)
                    }
                }
            }
            "getWorkOrder" -> {
                scope.launch {
                    try {
                        val id = call.argument<String>("id")!!
                        val order = getWorkOrder(id)
                        result.success(order)
                    } catch (e: Exception) {
                        result.error("DB_ERROR", e.message, null)
                    }
                }
            }
            "updateWorkOrderStatus" -> {
                scope.launch {
                    try {
                        val id = call.argument<String>("id")!!
                        val status = call.argument<String>("status")!!
                        updateWorkOrderStatus(id, status)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DB_ERROR", e.message, null)
                    }
                }
            }

            // Instructions
            "getInstructions" -> {
                scope.launch {
                    try {
                        val workOrderId = call.argument<String>("workOrderId")!!
                        val instructions = getInstructions(workOrderId)
                        result.success(instructions)
                    } catch (e: Exception) {
                        result.error("DB_ERROR", e.message, null)
                    }
                }
            }

            // Work Logs
            "getWorkLogs" -> {
                scope.launch {
                    try {
                        val workOrderId = call.argument<String>("workOrderId")!!
                        val logs = getWorkLogs(workOrderId)
                        result.success(logs)
                    } catch (e: Exception) {
                        result.error("DB_ERROR", e.message, null)
                    }
                }
            }
            "saveWorkLog" -> {
                scope.launch {
                    try {
                        val data = call.argument<Map<String, Any>>("data")!!
                        val id = saveWorkLog(data)
                        result.success(id)
                    } catch (e: Exception) {
                        result.error("DB_ERROR", e.message, null)
                    }
                }
            }
            "savePhoto" -> {
                scope.launch {
                    try {
                        val workLogId = call.argument<String>("workLogId")!!
                        val photoBytes = call.argument<ByteArray>("photoBytes")!!
                        val caption = call.argument<String>("caption") ?: ""
                        val id = savePhoto(workLogId, photoBytes, caption)
                        result.success(id)
                    } catch (e: Exception) {
                        result.error("DB_ERROR", e.message, null)
                    }
                }
            }
            "getPhotos" -> {
                scope.launch {
                    try {
                        val workLogId = call.argument<String>("workLogId")!!
                        val photos = getPhotos(workLogId)
                        result.success(photos)
                    } catch (e: Exception) {
                        result.error("DB_ERROR", e.message, null)
                    }
                }
            }

            // Sync
            "startP2P" -> {
                multipeerSyncManager.start()
                result.success(true)
            }
            "getP2PStatus" -> {
                val state = multipeerSyncManager.syncState.value
                val statusMap = mutableMapOf(
                    "isRunning" to state.isRunning,
                    "myPeerID" to (state.myPeerID ?: ""),
                    "connectedPeers" to state.connectedPeers.size,
                    "status" to state.syncStatus
                )
                if (state.error != null) {
                    statusMap["error"] = state.error
                }
                result.success(statusMap)
            }
            "startSyncGatewayReplication" -> {
                val url = call.argument<String>("url")
                if (url != null) {
                    startSyncGatewayReplication(url)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "URL is required", null)
                }
            }

            // Seed demo data
            "seedDemoData" -> {
                scope.launch {
                    try {
                        seedDemoData()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DB_ERROR", e.message, null)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    // --- Work Orders ---

    private suspend fun getWorkOrders(statusFilter: String?): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val results = mutableListOf<Map<String, Any?>>()
        val query = if (statusFilter != null) {
            database.createQuery(
                "SELECT META().id, * FROM ${AppConfig.SCOPE_NAME}.${AppConfig.COLLECTION_WORK_ORDERS} WHERE type = 'work_order' AND status = '$statusFilter' ORDER BY scheduled_date DESC"
            )
        } else {
            database.createQuery(
                "SELECT META().id, * FROM ${AppConfig.SCOPE_NAME}.${AppConfig.COLLECTION_WORK_ORDERS} WHERE type = 'work_order' ORDER BY scheduled_date DESC"
            )
        }
        val rs = query.execute()
        for (row in rs) {
            val map = mutableMapOf<String, Any?>()
            map["id"] = row.getString("id")
            val wo = row.getDictionary(AppConfig.COLLECTION_WORK_ORDERS)
            if (wo != null) {
                map["title"] = wo.getString("title")
                map["description"] = wo.getString("description")
                map["status"] = wo.getString("status")
                map["priority"] = wo.getString("priority")
                map["address"] = wo.getString("address")
                map["customer_name"] = wo.getString("customer_name")
                map["scheduled_date"] = wo.getString("scheduled_date")
                map["assigned_to"] = wo.getString("assigned_to")
                map["type"] = wo.getString("type")
            }
            results.add(map)
        }
        return@withContext results
    }

    private suspend fun getWorkOrder(id: String): Map<String, Any?>? = withContext(Dispatchers.IO) {
        val doc = workOrdersCollection.getDocument(id) ?: return@withContext null
        return@withContext documentToMap(doc, id)
    }

    private suspend fun updateWorkOrderStatus(id: String, status: String) = withContext(Dispatchers.IO) {
        val doc = workOrdersCollection.getDocument(id)?.toMutable() ?: return@withContext
        doc.setString("status", status)
        doc.setString("updated_at", dateFormat.format(Date()))
        workOrdersCollection.save(doc)
    }

    // --- Instructions ---

    private suspend fun getInstructions(workOrderId: String): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val results = mutableListOf<Map<String, Any?>>()
        val query = database.createQuery(
            "SELECT META().id, * FROM ${AppConfig.SCOPE_NAME}.${AppConfig.COLLECTION_INSTRUCTIONS} WHERE work_order_id = '$workOrderId' ORDER BY step_number ASC"
        )
        val rs = query.execute()
        for (row in rs) {
            val map = mutableMapOf<String, Any?>()
            map["id"] = row.getString("id")
            val inst = row.getDictionary(AppConfig.COLLECTION_INSTRUCTIONS)
            if (inst != null) {
                map["work_order_id"] = inst.getString("work_order_id")
                map["step_number"] = inst.getInt("step_number")
                map["title"] = inst.getString("title")
                map["description"] = inst.getString("description")
                map["type"] = inst.getString("type")
            }
            results.add(map)
        }
        return@withContext results
    }

    // --- Work Logs ---

    private suspend fun getWorkLogs(workOrderId: String): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val results = mutableListOf<Map<String, Any?>>()
        val query = database.createQuery(
            "SELECT META().id, * FROM ${AppConfig.SCOPE_NAME}.${AppConfig.COLLECTION_WORK_LOGS} WHERE work_order_id = '$workOrderId' ORDER BY created_at DESC"
        )
        val rs = query.execute()
        for (row in rs) {
            val map = mutableMapOf<String, Any?>()
            map["id"] = row.getString("id")
            val log = row.getDictionary(AppConfig.COLLECTION_WORK_LOGS)
            if (log != null) {
                map["work_order_id"] = log.getString("work_order_id")
                map["technician_id"] = log.getString("technician_id")
                map["notes"] = log.getString("notes")
                map["work_done"] = log.getString("work_done")
                map["created_at"] = log.getString("created_at")
                map["type"] = log.getString("type")
                // Photo IDs stored as array
                val photoIds = log.getArray("photo_ids")
                if (photoIds != null) {
                    map["photo_ids"] = (0 until photoIds.count()).map { photoIds.getString(it) }
                }
            }
            results.add(map)
        }
        return@withContext results
    }

    private suspend fun saveWorkLog(data: Map<String, Any>): String = withContext(Dispatchers.IO) {
        val id = "wl_${UUID.randomUUID()}"
        val doc = MutableDocument(id)
        doc.setString("type", "work_log")
        doc.setString("work_order_id", data["work_order_id"] as String)
        doc.setString("technician_id", data["technician_id"] as? String ?: "tech_001")
        doc.setString("notes", data["notes"] as? String ?: "")
        doc.setString("work_done", data["work_done"] as? String ?: "")
        doc.setString("created_at", dateFormat.format(Date()))
        doc.setArray("photo_ids", MutableArray())
        workLogsCollection.save(doc)
        return@withContext id
    }

    // --- Photos ---

    private suspend fun savePhoto(workLogId: String, photoBytes: ByteArray, caption: String): String = withContext(Dispatchers.IO) {
        val id = "photo_${UUID.randomUUID()}"
        val doc = MutableDocument(id)
        doc.setString("type", "photo")
        doc.setString("work_log_id", workLogId)
        doc.setString("caption", caption)
        doc.setString("created_at", dateFormat.format(Date()))

        // Store photo as blob
        val blob = Blob("image/jpeg", photoBytes)
        doc.setBlob("image", blob)

        workLogsCollection.save(doc)

        // Add photo ID to work log's photo_ids array
        val logDoc = workLogsCollection.getDocument(workLogId)?.toMutable()
        if (logDoc != null) {
            val photoIds = logDoc.getArray("photo_ids") ?: MutableArray()
            photoIds.addString(id)
            logDoc.setArray("photo_ids", photoIds)
            workLogsCollection.save(logDoc)
        }

        return@withContext id
    }

    private suspend fun getPhotos(workLogId: String): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val results = mutableListOf<Map<String, Any?>>()
        val query = database.createQuery(
            "SELECT META().id, * FROM ${AppConfig.SCOPE_NAME}.${AppConfig.COLLECTION_WORK_LOGS} WHERE type = 'photo' AND work_log_id = '$workLogId'"
        )
        val rs = query.execute()
        for (row in rs) {
            val map = mutableMapOf<String, Any?>()
            map["id"] = row.getString("id")
            val photo = row.getDictionary(AppConfig.COLLECTION_WORK_LOGS)
            if (photo != null) {
                map["caption"] = photo.getString("caption")
                map["created_at"] = photo.getString("created_at")
                // Return blob as base64 for Flutter
                val blob = photo.getBlob("image")
                if (blob != null) {
                    map["image_base64"] = Base64.encodeToString(blob.content, Base64.NO_WRAP)
                }
            }
            results.add(map)
        }
        return@withContext results
    }

    // --- Demo Data ---

    private suspend fun seedDemoData() = withContext(Dispatchers.IO) {
        // Only seed if empty
        val check = database.createQuery(
            "SELECT META().id FROM ${AppConfig.SCOPE_NAME}.${AppConfig.COLLECTION_WORK_ORDERS} LIMIT 1"
        )
        if (check.execute().allResults().isNotEmpty()) return@withContext

        val now = dateFormat.format(Date())
        val tomorrow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }.time
        val dayAfter = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 2) }.time

        // Work Orders
        val orders = listOf(
            mapOf(
                "id" to "wo_001", "title" to "Fiber Installation - Residential",
                "description" to "Install fiber optic connection for new residential customer. Run cable from distribution point to ONT inside property.",
                "status" to "pending", "priority" to "high",
                "address" to "Sveavagen 42, Stockholm", "customer_name" to "Erik Lindqvist",
                "scheduled_date" to dateFormat.format(tomorrow), "assigned_to" to "tech_001"
            ),
            mapOf(
                "id" to "wo_002", "title" to "Router Replacement",
                "description" to "Replace faulty Tele2 router. Customer reports intermittent connectivity and WiFi drops.",
                "status" to "pending", "priority" to "medium",
                "address" to "Kungsgatan 15, Stockholm", "customer_name" to "Anna Bergstrom",
                "scheduled_date" to dateFormat.format(tomorrow), "assigned_to" to "tech_001"
            ),
            mapOf(
                "id" to "wo_003", "title" to "5G Antenna Maintenance",
                "description" to "Scheduled maintenance on 5G small cell antenna. Check signal levels, clean equipment, verify backhaul connection.",
                "status" to "in_progress", "priority" to "high",
                "address" to "Gotgatan 78, Stockholm", "customer_name" to "Tele2 Infrastructure",
                "scheduled_date" to now, "assigned_to" to "tech_001"
            ),
            mapOf(
                "id" to "wo_004", "title" to "Business Line Troubleshooting",
                "description" to "Business customer reporting packet loss on dedicated line. Run diagnostics and identify fault.",
                "status" to "completed", "priority" to "critical",
                "address" to "Birger Jarlsgatan 10, Stockholm", "customer_name" to "Nordic Solutions AB",
                "scheduled_date" to now, "assigned_to" to "tech_001"
            ),
            mapOf(
                "id" to "wo_005", "title" to "TV Box Setup",
                "description" to "Set up Tele2 TV box and configure channels for new customer. Ensure streaming quality is acceptable.",
                "status" to "pending", "priority" to "low",
                "address" to "Vastmannagatan 22, Stockholm", "customer_name" to "Lars Johansson",
                "scheduled_date" to dateFormat.format(dayAfter), "assigned_to" to "tech_001"
            ),
            mapOf(
                "id" to "wo_006", "title" to "Tunnel Repeater Installation",
                "description" to "Install cellular repeater system in Sodra Lanken tunnel segment B3. Area has zero mobile coverage. All work must be logged offline and synced after exiting tunnel. Coordinate with traffic control for lane closures.",
                "status" to "pending", "priority" to "critical",
                "address" to "Sodra Lanken Tunnel, Segment B3, Stockholm", "customer_name" to "Trafikverket",
                "scheduled_date" to dateFormat.format(tomorrow), "assigned_to" to "tech_001"
            ),
            mapOf(
                "id" to "wo_007", "title" to "Server Room Fiber Splice",
                "description" to "Splice damaged fiber trunk in basement server room at Ericsson HQ. Thick concrete walls and RF shielding block all cellular and WiFi signals. Bring portable OTDR for testing. Badge access required — contact facility manager on arrival.",
                "status" to "pending", "priority" to "high",
                "address" to "Torshamnsgatan 23, Kista, Stockholm", "customer_name" to "Ericsson AB",
                "scheduled_date" to dateFormat.format(tomorrow), "assigned_to" to "tech_001"
            ),
            mapOf(
                "id" to "wo_008", "title" to "Underground Parking DAS Repair",
                "description" to "Repair distributed antenna system (DAS) on level P3 of parking garage. No cellular coverage at this depth. Document signal levels at each antenna node before and after repair. Use P2P sync with partner technician at ground level if needed.",
                "status" to "in_progress", "priority" to "high",
                "address" to "Arenastaden P-hus, Solna", "customer_name" to "Fabege Parkering AB",
                "scheduled_date" to now, "assigned_to" to "tech_001"
            ),
            mapOf(
                "id" to "wo_009", "title" to "Hospital MRI Wing Cable Run",
                "description" to "Run shielded ethernet and fiber through MRI wing at Karolinska. Extreme RF shielding in this zone blocks all wireless signals completely. Work only during approved maintenance windows 06:00-08:00. All equipment must be MRI-safe — no ferromagnetic tools.",
                "status" to "pending", "priority" to "medium",
                "address" to "Karolinska Universitetssjukhuset, Eugeniavägen 3, Solna", "customer_name" to "Karolinska Universitetssjukhuset",
                "scheduled_date" to dateFormat.format(dayAfter), "assigned_to" to "tech_001"
            )
        )

        for (order in orders) {
            val doc = MutableDocument(order["id"] as String)
            doc.setString("type", "work_order")
            for ((key, value) in order) {
                if (key != "id") doc.setString(key, value)
            }
            doc.setString("created_at", now)
            workOrdersCollection.save(doc)
        }

        // Instructions for wo_001
        val instructions001 = listOf(
            mapOf("step" to 1, "title" to "Site Survey", "desc" to "Check the distribution point location and plan cable route to customer premises. Verify fiber availability at the distribution point."),
            mapOf("step" to 2, "title" to "Cable Routing", "desc" to "Route fiber cable from distribution point to customer premises. Use existing ducts where possible. Mark any obstacles."),
            mapOf("step" to 3, "title" to "ONT Installation", "desc" to "Mount the ONT (Optical Network Terminal) at agreed location. Connect fiber cable to ONT and verify optical power levels."),
            mapOf("step" to 4, "title" to "Router Setup", "desc" to "Connect Tele2 router to ONT via ethernet. Configure WiFi network name and password per customer preference."),
            mapOf("step" to 5, "title" to "Testing", "desc" to "Run speed test to verify connection meets subscribed tier. Test on WiFi and wired. Check all rooms for WiFi coverage.")
        )
        for (inst in instructions001) {
            val doc = MutableDocument("inst_001_${inst["step"]}")
            doc.setString("type", "instruction")
            doc.setString("work_order_id", "wo_001")
            doc.setInt("step_number", inst["step"] as Int)
            doc.setString("title", inst["title"] as String)
            doc.setString("description", inst["desc"] as String)
            instructionsCollection.save(doc)
        }

        // Instructions for wo_003
        val instructions003 = listOf(
            mapOf("step" to 1, "title" to "Safety Check", "desc" to "Ensure all safety equipment is worn. Check weather conditions. Verify access credentials for site."),
            mapOf("step" to 2, "title" to "Visual Inspection", "desc" to "Inspect antenna mounting, cables, and connectors for physical damage or wear. Take photos of any issues found."),
            mapOf("step" to 3, "title" to "Signal Measurement", "desc" to "Use signal analyzer to measure RSRP, RSRQ, and SINR values. Compare against baseline and document results."),
            mapOf("step" to 4, "title" to "Backhaul Verification", "desc" to "Check fiber backhaul connection status. Run throughput test and verify latency is within acceptable range.")
        )
        for (inst in instructions003) {
            val doc = MutableDocument("inst_003_${inst["step"]}")
            doc.setString("type", "instruction")
            doc.setString("work_order_id", "wo_003")
            doc.setInt("step_number", inst["step"] as Int)
            doc.setString("title", inst["title"] as String)
            doc.setString("description", inst["desc"] as String)
            instructionsCollection.save(doc)
        }

        // Instructions for wo_006 (Tunnel Repeater)
        val instructions006 = listOf(
            mapOf("step" to 1, "title" to "Pre-Entry Sync", "desc" to "Before entering the tunnel, ensure all work order data is fully synced to your device. Verify offline mode is working — you will have zero connectivity inside."),
            mapOf("step" to 2, "title" to "Traffic Control Coordination", "desc" to "Confirm lane closure with Trafikverket traffic control. Set up safety barriers and warning signs per tunnel work protocol TF-2024."),
            mapOf("step" to 3, "title" to "Mount Repeater Hardware", "desc" to "Install the bi-directional amplifier at marked position B3-R7. Secure antenna brackets to tunnel ceiling using approved concrete anchors. Route coaxial donor and service cables along cable tray."),
            mapOf("step" to 4, "title" to "Power Connection", "desc" to "Connect repeater to dedicated power outlet B3-PWR-12. Verify UPS backup is operational. Log power draw readings."),
            mapOf("step" to 5, "title" to "Signal Verification", "desc" to "Power on repeater and measure coverage using RF scanner. Walk-test 200m in each direction logging signal at 10m intervals. Take photos of signal meter at each checkpoint."),
            mapOf("step" to 6, "title" to "Exit & Sync", "desc" to "After exiting the tunnel, allow device to reconnect and sync all logged data, photos, and measurements to the cloud. Verify everything uploaded successfully.")
        )
        for (inst in instructions006) {
            val doc = MutableDocument("inst_006_${inst["step"]}")
            doc.setString("type", "instruction")
            doc.setString("work_order_id", "wo_006")
            doc.setInt("step_number", inst["step"] as Int)
            doc.setString("title", inst["title"] as String)
            doc.setString("description", inst["desc"] as String)
            instructionsCollection.save(doc)
        }

        // Instructions for wo_007 (Server Room Fiber Splice)
        val instructions007 = listOf(
            mapOf("step" to 1, "title" to "Facility Check-In", "desc" to "Report to reception and obtain visitor badge. Contact facility manager to escort you to the basement server room. Note: all wireless signals are blocked below ground level."),
            mapOf("step" to 2, "title" to "Identify Damaged Fiber", "desc" to "Locate trunk cable TR-14 in rack C7. Use visual fault locator to pinpoint the break. Document the damage with photos before starting repair."),
            mapOf("step" to 3, "title" to "Prepare Splice", "desc" to "Strip fiber coating, clean and cleave both ends. Set up fusion splicer on stable surface. Ensure splice protector sleeves are ready."),
            mapOf("step" to 4, "title" to "Fusion Splice & Test", "desc" to "Perform fusion splice and verify estimated loss is below 0.05 dB. Apply heat-shrink splice protector. Use OTDR to confirm end-to-end link budget is within spec."),
            mapOf("step" to 5, "title" to "Exit & Sync Results", "desc" to "Return to ground level where connectivity resumes. Allow all work logs, photos, and test results to sync automatically. Verify sync completed before leaving the site.")
        )
        for (inst in instructions007) {
            val doc = MutableDocument("inst_007_${inst["step"]}")
            doc.setString("type", "instruction")
            doc.setString("work_order_id", "wo_007")
            doc.setInt("step_number", inst["step"] as Int)
            doc.setString("title", inst["title"] as String)
            doc.setString("description", inst["desc"] as String)
            instructionsCollection.save(doc)
        }

        // Instructions for wo_008 (Underground Parking DAS)
        val instructions008 = listOf(
            mapOf("step" to 1, "title" to "Survey Antenna Nodes", "desc" to "Walk level P3 and identify all DAS antenna nodes (expect 8 nodes). Measure and log signal level at each node using RF analyzer. Mark any nodes showing degraded output."),
            mapOf("step" to 2, "title" to "Trace Faulty Cable Run", "desc" to "Use cable tester to trace the coax run from the master unit on P1 down to P3. Identify the section with excessive loss or damage."),
            mapOf("step" to 3, "title" to "Replace Damaged Section", "desc" to "Swap the faulty cable section and connectors. Use proper weatherproof N-type connectors. Ensure all connections are torqued to spec."),
            mapOf("step" to 4, "title" to "Post-Repair Verification", "desc" to "Re-measure signal at all P3 antenna nodes. Compare before/after readings. Ensure coverage meets minimum -85 dBm across the entire level. Use P2P sync to share results with partner technician at ground level.")
        )
        for (inst in instructions008) {
            val doc = MutableDocument("inst_008_${inst["step"]}")
            doc.setString("type", "instruction")
            doc.setString("work_order_id", "wo_008")
            doc.setInt("step_number", inst["step"] as Int)
            doc.setString("title", inst["title"] as String)
            doc.setString("description", inst["desc"] as String)
            instructionsCollection.save(doc)
        }
    }

    private fun documentToMap(doc: Document, id: String): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        map["id"] = id
        for (key in doc.keys) {
            map[key] = doc.getValue(key)
        }
        return map
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        multipeerSyncManager.stop()
        syncUrl = null // Prevent auto-restart on intentional shutdown
        replicator?.stop()
        try {
            database.close()
        } catch (e: Exception) {
            // Ignore
        }
    }
}
