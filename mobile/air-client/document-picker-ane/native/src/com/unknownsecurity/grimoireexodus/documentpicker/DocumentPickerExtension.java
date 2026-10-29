package com.unknownsecurity.grimoireexodus.documentpicker;

import com.adobe.fre.FREContext;
import com.adobe.fre.FREExtension;

public final class DocumentPickerExtension implements FREExtension {
    private static volatile DocumentPickerContext activeContext;
    private static boolean pickerOpen;

    @Override
    public void initialize() {
    }

    @Override
    public FREContext createContext(String extensionId) {
        DocumentPickerContext context = new DocumentPickerContext();
        activeContext = context;
        return context;
    }

    @Override
    public void dispose() {
        activeContext = null;
        pickerOpen = false;
    }

    static synchronized boolean beginPicker() {
        if (pickerOpen) {
            return false;
        }
        pickerOpen = true;
        return true;
    }

    static synchronized void finishPicker(String code, String level) {
        pickerOpen = false;
        DocumentPickerContext context = activeContext;
        if (context != null) {
            context.dispatchStatusEventAsync(code, level == null ? "" : level);
        }
    }

    static void clearContext(DocumentPickerContext context) {
        if (activeContext == context) {
            activeContext = null;
        }
    }
}
