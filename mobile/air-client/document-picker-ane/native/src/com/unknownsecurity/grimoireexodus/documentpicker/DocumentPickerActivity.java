package com.unknownsecurity.grimoireexodus.documentpicker;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

public final class DocumentPickerActivity extends Activity {
    static final String CACHE_DIRECTORY = "grimoire-document-picker";
    private static final int REQUEST_DOCUMENT = 41071;
    private static final long MAX_BYTES = 2L * 1024L * 1024L;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (savedInstanceState == null) {
            openDocument();
        }
    }

    private void openDocument() {
        try {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivityForResult(intent, REQUEST_DOCUMENT);
        } catch (Throwable error) {
            DocumentPickerExtension.finishPicker("error",
                "The Android document picker could not be opened.");
            finish();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_DOCUMENT) {
            return;
        }
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            DocumentPickerExtension.finishPicker("cancel", "");
            finish();
            return;
        }

        File output = null;
        try {
            Uri uri = data.getData();
            String displayName = readDisplayName(uri);
            File cacheFolder = new File(getCacheDir(), CACHE_DIRECTORY);
            if (!cacheFolder.exists() && !cacheFolder.mkdirs()) {
                throw new IllegalStateException("Picker cache is unavailable.");
            }
            output = File.createTempFile("selected-", ".gbot", cacheFolder);
            copyBounded(uri, output);

            JSONObject payload = new JSONObject();
            payload.put("path", output.getAbsolutePath());
            payload.put("name", displayName);
            DocumentPickerExtension.finishPicker("select", payload.toString());
        } catch (Throwable error) {
            if (output != null) {
                output.delete();
            }
            DocumentPickerExtension.finishPicker("error",
                "The selected document could not be read.");
        }
        finish();
    }

    private String readDisplayName(Uri uri) {
        Cursor cursor = null;
        try {
            cursor = getContentResolver().query(uri,
                new String[] { OpenableColumns.DISPLAY_NAME }, null, null, null);
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) {
                    String value = cursor.getString(index);
                    if (value != null && value.length() > 0) {
                        return value;
                    }
                }
            }
        } catch (Throwable ignored) {
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
        return "selected.gbot";
    }

    private void copyBounded(Uri uri, File output) throws Exception {
        InputStream input = null;
        FileOutputStream stream = null;
        long total = 0;
        try {
            input = getContentResolver().openInputStream(uri);
            if (input == null) {
                throw new IllegalStateException("Document stream is unavailable.");
            }
            stream = new FileOutputStream(output, false);
            byte[] buffer = new byte[16384];
            int read;
            while ((read = input.read(buffer)) != -1) {
                total += read;
                if (total > MAX_BYTES) {
                    throw new IllegalStateException("Document exceeds the safe mobile limit.");
                }
                stream.write(buffer, 0, read);
            }
            stream.flush();
            if (total <= 0) {
                throw new IllegalStateException("Document is empty.");
            }
        } finally {
            if (stream != null) {
                stream.close();
            }
            if (input != null) {
                input.close();
            }
        }
    }
}
