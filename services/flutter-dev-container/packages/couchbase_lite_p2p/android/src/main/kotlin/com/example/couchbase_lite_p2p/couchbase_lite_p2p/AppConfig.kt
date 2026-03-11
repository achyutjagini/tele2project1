package com.example.couchbase_lite_p2p.couchbase_lite_p2p

object AppConfig {
    // Database Configuration
    const val DATABASE_NAME = "tele2_fieldwork"
    const val SCOPE_NAME = "technician"
    const val COLLECTION_WORK_ORDERS = "work_orders"
    const val COLLECTION_INSTRUCTIONS = "instructions"
    const val COLLECTION_WORK_LOGS = "work_logs"

    // Sync Gateway Configuration
    private const val DEFAULT_SYNC_URL = "ws://10.0.2.2:4984/main"
    val syncGatewayURL: String = DEFAULT_SYNC_URL

    val username: String = "user"
    val password: String = "password"

    // P2P Configuration
    const val P2P_PEER_GROUP_ID = "com.tele2.fieldwork"
    const val P2P_IDENTITY_LABEL = "com.tele2.fieldwork.p2p.identity"
    const val P2P_AUTO_START = true
}
