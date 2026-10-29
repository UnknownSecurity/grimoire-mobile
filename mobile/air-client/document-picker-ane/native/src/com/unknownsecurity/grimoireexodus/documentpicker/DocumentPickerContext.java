package com.unknownsecurity.grimoireexodus.documentpicker;

import android.app.Activity;
import android.content.Intent;

import com.adobe.fre.FREContext;
import com.adobe.fre.FREFunction;
import com.adobe.fre.FREObject;

import java.io.File;
import java.util.HashMap;
import java.util.Map;

public final class DocumentPickerContext extends FREContext {
    @Override
    public Map<String, FREFunction> getFunctions() {
        Map<String, FREFunction> functions = new HashMap<String, FREFunction>();
        functions.put("browse", new BrowseFunction());
        functions.put("cleanup", new CleanupFunction());
        return functions;
    }

    @Override
    public void dispose() {
        DocumentPickerExtension.clearContext(this);
    }

    private static final class BrowseFunction implements FREFunction {
        @Override
        public FREObject call(FREContext context, FREObject[] arguments) {
            boolean started = false;
            try {
                if (!DocumentPickerExtension.beginPicker()) {
                    return FREObject.newObject(false);
                }
                final Activity activity = context.getActivity();
                activity.runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        try {
                            Intent intent = new Intent(activity, DocumentPickerActivity.class);
                            activity.startActivity(intent);
                        } catch (Throwable error) {
                            DocumentPickerExtension.finishPicker("error",
                                "The Android document picker could not be opened.");
                        }
                    }
                });
                started = true;
            } catch (Throwable error) {
                DocumentPickerExtension.finishPicker("error",
                    "The Android document picker could not be opened.");
            }
            try {
                return FREObject.newObject(started);
            } catch (Throwable ignored) {
                return null;
            }
        }
    }

    private static final class CleanupFunction implements FREFunction {
        @Override
        public FREObject call(FREContext context, FREObject[] arguments) {
            boolean deleted = false;
            try {
                if (arguments != null && arguments.length > 0 && arguments[0] != null) {
                    String requestedPath = arguments[0].getAsString();
                    File cacheRoot = new File(context.getActivity().getCacheDir(),
                        DocumentPickerActivity.CACHE_DIRECTORY).getCanonicalFile();
                    File selected = new File(requestedPath).getCanonicalFile();
                    String rootPath = cacheRoot.getPath() + File.separator;
                    if (selected.getPath().startsWith(rootPath) && selected.isFile()) {
                        deleted = selected.delete();
                    }
                }
            } catch (Throwable ignored) {
            }
            try {
                return FREObject.newObject(deleted);
            } catch (Throwable ignored) {
                return null;
            }
        }
    }
}
