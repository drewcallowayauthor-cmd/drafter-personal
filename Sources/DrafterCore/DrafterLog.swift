import os

/// Per-module loggers, all under one subsystem so Console.app can filter Drafter's
/// output as a unit while still separating it by category. Every module that
/// previously swallowed an error via `try?` should log it through the matching
/// logger here rather than leaving no trace at all.
public enum DrafterLog {
    private static let subsystem = "com.drafter.app"

    public static let git = Logger(subsystem: subsystem, category: "git")
    public static let snapshot = Logger(subsystem: subsystem, category: "snapshot")
    public static let credential = Logger(subsystem: subsystem, category: "credential")
    public static let compile = Logger(subsystem: subsystem, category: "compile")
    public static let projectStore = Logger(subsystem: subsystem, category: "projectStore")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
