package com.unknownsecurity.grimoireexodus.runner;

import com.adobe.fre.FREContext;
import com.adobe.fre.FREExtension;

public final class RunnerExtension implements FREExtension {
    @Override
    public void initialize() {
    }

    @Override
    public FREContext createContext(String extensionId) {
        return new RunnerContext();
    }

    @Override
    public void dispose() {
    }
}
