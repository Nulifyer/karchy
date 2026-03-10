package logging

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

type LogLevel int

const (
	LogLevelNone LogLevel = iota
	LogLevelError
	LogLevelWarn
	LogLevelInfo
	LogLevelDebug
	LogLevelTrace
)

var (
	logLevel     = LogLevelNone
	logWriter    io.Writer
	logFile      *os.File
	logStartTime = time.Now()
	enabled      bool
)

// Enabled returns whether logging is active.
func Enabled() bool { return enabled }

func Init(on bool) {
	enabled = on
	if !on {
		logLevel = LogLevelNone
		logWriter = nil
		return
	}

	logLevel = LogLevelDebug

	dir, err := os.UserConfigDir()
	if err != nil {
		dir = os.TempDir()
	}
	logDir := filepath.Join(dir, "karchy")
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "karchy: failed to create log dir: %v\n", err)
		return
	}

	path := filepath.Join(logDir, "karchy.log")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "karchy: failed to open log file: %v\n", err)
		return
	}

	logFile = f
	logWriter = f
	Info("--- logging started ---")
}

func SetLevel(l LogLevel) { logLevel = l }

func timestamp() string {
	return fmt.Sprintf("+%.3fs", time.Since(logStartTime).Seconds())
}

func logf(level string, minLevel LogLevel, format string, args ...any) {
	if logLevel < minLevel || logWriter == nil {
		return
	}
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(logWriter, "[%s] %s %s\n", level, timestamp(), msg)
}

func Trace(format string, args ...any) {
	logf("TRACE", LogLevelTrace, format, args...)
}

func Debug(format string, args ...any) {
	logf("DEBUG", LogLevelDebug, format, args...)
}

func Info(format string, args ...any) {
	logf("INFO", LogLevelInfo, format, args...)
}

func Warn(format string, args ...any) {
	logf("WARN", LogLevelWarn, format, args...)
}

func Error(format string, args ...any) {
	logf("ERROR", LogLevelError, format, args...)
}

// Close flushes and closes the log file. Safe to call even if logging is disabled.
func Close() {
	if logFile != nil {
		Info("--- logging stopped ---")
		logFile.Close()
		logFile = nil
		logWriter = nil
	}
}

func Fatal(format string, args ...any) {
	if logWriter != nil {
		msg := fmt.Sprintf(format, args...)
		fmt.Fprintf(logWriter, "[FATAL] %s %s\n", timestamp(), msg)
	}
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
