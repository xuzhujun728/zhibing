package com.zhibing.zhibing_app

import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CompletableFuture

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "zhibing/native"
        private const val PICK_REQUEST_CODE = 9103
        private var pendingPick: CompletableFuture<String?>? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "listBackupFiles" -> result.success(listBackupFiles())
                "copyDbToBackupFolder" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                    result.success(
                        copyDbToBackupFolder(
                            args["srcPath"] as? String ?: "",
                            args["fileName"] as? String ?: ""
                        )
                    )
                }
                "readBackupFileToCache" -> {
                    result.success(readBackupFileToCache(call.arguments as? String ?: ""))
                }
                "deleteBackupFile" -> {
                    result.success(deleteBackupFile(call.arguments as? String ?: ""))
                }
                "pickBackupFile" -> {
                    pickBackupFile().whenComplete { path, _ -> result.success(path) }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_REQUEST_CODE) {
            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            pendingPick?.complete(uri?.let { copyPickedToCache(it) })
            pendingPick = null
        }
    }

    private fun pickBackupFile(): CompletableFuture<String?> {
        val future = CompletableFuture<String?>()
        pendingPick = future
        runOnUiThread {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
            }
            try {
                // 备份目录已存在时，让文件选择器默认定位到该目录。
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && queryBackupRows().isNotEmpty()) {
                    intent.putExtra(
                        "android.provider.extra.INITIAL_URI",
                        Uri.parse("content://com.android.externalstorage.documents/document/primary%3ADownload%2Fzhibing")
                    )
                }
            } catch (_: Exception) {
            }
            try {
                startActivityForResult(intent, PICK_REQUEST_CODE)
            } catch (_: Exception) {
                pendingPick = null
                future.complete(null)
            }
        }
        return future
    }

    private fun copyPickedToCache(uri: Uri): String? {
        return try {
            var name = "picked_backup.db"
            try {
                contentResolver.query(
                    uri,
                    arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
                    null, null, null
                )?.use { c ->
                    if (c.moveToFirst()) name = c.getString(0) ?: name
                }
            } catch (_: Exception) {
            }
            val cacheDir = File(cacheDir, "backup")
            if (!cacheDir.exists()) cacheDir.mkdirs()
            val target = File(cacheDir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { input.copyTo(it) }
            }
            target.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun backupDirPath() = "Download/zhibing/"

    private fun queryBackupRows(): List<Pair<String, Long>> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return try {
                val result = mutableListOf<Pair<String, Long>>()
                contentResolver.query(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    arrayOf(
                        MediaStore.MediaColumns.DISPLAY_NAME,
                        MediaStore.MediaColumns.DATE_MODIFIED
                    ),
                    "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
                    arrayOf("${backupDirPath()}%"),
                    null
                )?.use { cursor ->
                    val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                    val modIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
                    while (cursor.moveToNext()) {
                        val name = cursor.getString(nameIdx) ?: continue
                        if (name.endsWith(".db", ignoreCase = true)) {
                            result.add(name to cursor.getLong(modIdx) * 1000L)
                        }
                    }
                }
                result
            } catch (_: Exception) {
                emptyList()
            }
        }
        return try {
            val dir = File(legacyDownloadsDir(), "zhibing")
            if (!dir.exists()) return emptyList()
            dir.listFiles { f -> f.isFile && f.name.endsWith(".db", ignoreCase = true) }
                ?.map { it.name to it.lastModified() }
                ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun legacyDownloadsDir() =
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)

    private fun queryBackupRowUri(fileName: String): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            var found: Uri? = null
            contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
                arrayOf(fileName, "${backupDirPath()}%"),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    found = ContentUris.withAppendedId(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        cursor.getLong(0)
                    )
                }
            }
            found
        } catch (_: Exception) {
            null
        }
    }

    private fun listBackupFiles(): List<Map<String, Any>> {
        return queryBackupRows().map { (name, lastModified) ->
            mapOf("name" to name, "lastModified" to lastModified)
        }
    }

    private fun copyDbToBackupFolder(srcPath: String, fileName: String): Boolean {
        val srcFile = File(srcPath)
        if (!srcFile.exists()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                deleteBackupFile(fileName)
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, backupDirPath())
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: return false
                contentResolver.openOutputStream(uri)?.use { out ->
                    srcFile.inputStream().use { it.copyTo(out) }
                }
                contentResolver.update(
                    uri,
                    ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                    null,
                    null
                )
                true
            } else {
                val dir = File(legacyDownloadsDir(), "zhibing")
                if (!dir.exists()) dir.mkdirs()
                val target = File(dir, fileName)
                srcFile.inputStream().use { input ->
                    target.outputStream().use { input.copyTo(it) }
                }
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun readBackupFileToCache(fileName: String): String? {
        return try {
            val cacheDir = File(cacheDir, "backup")
            if (!cacheDir.exists()) cacheDir.mkdirs()
            val target = File(cacheDir, fileName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = queryBackupRowUri(fileName) ?: return null
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { input.copyTo(it) }
                }
            } else {
                val src = File(File(legacyDownloadsDir(), "zhibing"), fileName)
                if (!src.exists()) return null
                src.inputStream().use { input ->
                    target.outputStream().use { input.copyTo(it) }
                }
            }
            target.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun deleteBackupFile(fileName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = queryBackupRowUri(fileName) ?: return false
                contentResolver.delete(uri, null, null) > 0
            } else {
                val f = File(File(legacyDownloadsDir(), "zhibing"), fileName)
                if (f.exists()) f.delete() else false
            }
        } catch (_: Exception) {
            false
        }
    }
}
