package com.appreveal.mcpserver

import fi.iki.elonen.NanoHTTPD
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * MCP HTTP server built on NanoHTTPD.
 * Accepts POST requests with JSON-RPC 2.0 payloads, routes through MCPRouter.
 */
internal class MCPServer(
    port: Int = 0,
    val sessionToken: String = makeSessionToken(),
) : NanoHTTPD(port) {
    companion object {
        private const val SESSION_TOKEN_QUERY_NAME = "appreveal_session_token"
        private const val SESSION_TOKEN_HEADER_NAME = "x-appreveal-session"

        private fun makeSessionToken(): String {
            val bytes = ByteArray(32)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString(separator = "") { "%02x".format(it.toInt() and 0xff) }
        }
    }

    /**
     * The actual port the server is listening on (valid after start()).
     */
    val actualPort: Int
        get() = super.getListeningPort()

    val url: String
        get() = "http://127.0.0.1:$actualPort/"

    val sessionUrl: String
        get() = "$url?$SESSION_TOKEN_QUERY_NAME=$sessionToken"

    override fun serve(session: IHTTPSession): Response {
        if (session.method == Method.GET && session.uri.substringBefore("?") == "/health") {
            return jsonResponse(
                Response.Status.OK,
                """{"status":"ok","port":$actualPort,"auth":"session-token","discovery":"android-nsd"}""",
                session,
            )
        }

        if (session.method == Method.OPTIONS) {
            return jsonResponse(Response.Status.NO_CONTENT, "", session)
        }

        if (session.method != Method.POST) {
            return jsonResponse(
                Response.Status.METHOD_NOT_ALLOWED,
                """{"error":"Only POST is supported"}""",
                session,
            )
        }

        if (!isAuthorized(session)) {
            return jsonResponse(
                Response.Status.UNAUTHORIZED,
                MCPGson.gson.toJson(
                    MCPResponse.error(null, MCPError.internalError("Unauthorized")),
                ),
                session,
            )
        }

        return try {
            val files = HashMap<String, String>()
            session.parseBody(files)
            val json = files["postData"] ?: ""

            if (json.isBlank()) {
                return jsonResponse(
                    Response.Status.BAD_REQUEST,
                    """{"error":"Empty body"}""",
                    session,
                )
            }

            val requestObject = MCPGson.gson.fromJson(json, com.google.gson.JsonObject::class.java)
            val expectsResponse = requestObject.has("id")
            val request = MCPGson.gson.fromJson(requestObject, MCPRequest::class.java)
            val response = MCPRouter.handle(request)
            if (!expectsResponse) {
                return jsonResponse(Response.Status.NO_CONTENT, "", session)
            }
            val responseJson = MCPGson.gson.toJson(response)

            jsonResponse(
                Response.Status.OK,
                responseJson,
                session,
            )
        } catch (e: Exception) {
            val errorResponse =
                MCPResponse.error(
                    null,
                    MCPError.internalError(e.message ?: "Server error"),
                )
            jsonResponse(
                Response.Status.INTERNAL_ERROR,
                MCPGson.gson.toJson(errorResponse),
                session,
            )
        }
    }

    private fun isAuthorized(session: IHTTPSession): Boolean {
        val queryToken = session.parameters[SESSION_TOKEN_QUERY_NAME]?.firstOrNull()
        if (constantTimeEquals(queryToken, sessionToken)) return true

        val headerToken = session.headers[SESSION_TOKEN_HEADER_NAME]
        if (constantTimeEquals(headerToken, sessionToken)) return true

        val bearerToken = session.headers["authorization"]?.let(::readBearerToken)
        return constantTimeEquals(bearerToken, sessionToken)
    }

    private fun readBearerToken(value: String): String? {
        val prefix = "Bearer "
        return if (value.startsWith(prefix, ignoreCase = true)) {
            value.substring(prefix.length).trim()
        } else {
            null
        }
    }

    private fun constantTimeEquals(
        actual: String?,
        expected: String,
    ): Boolean {
        if (actual == null) return false
        val actualBytes = actual.toByteArray(Charsets.UTF_8)
        val expectedBytes = expected.toByteArray(Charsets.UTF_8)
        return actualBytes.size == expectedBytes.size &&
            MessageDigest.isEqual(actualBytes, expectedBytes)
    }

    private fun jsonResponse(
        status: Response.Status,
        body: String,
        session: IHTTPSession,
    ): Response {
        val response = newFixedLengthResponse(status, "application/json", body)
        val origin = session.headers["origin"]
        if (origin != null && isLoopbackOrigin(origin)) {
            response.addHeader("Access-Control-Allow-Origin", origin)
            response.addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            response.addHeader("Access-Control-Allow-Headers", "Authorization, Content-Type, X-AppReveal-Session")
            response.addHeader("Vary", "Origin")
        }
        return response
    }

    private fun isLoopbackOrigin(origin: String): Boolean =
        try {
            val uri = java.net.URI(origin)
            val host = uri.host?.trimEnd('.')?.lowercase() ?: return false
            (uri.scheme == "http" || uri.scheme == "https") &&
                (host == "localhost" || host.endsWith(".localhost") || host == "127.0.0.1" || host.startsWith("127.") || host == "::1")
        } catch (_: Exception) {
            false
        }
}
