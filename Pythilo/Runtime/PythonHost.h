#ifndef PYTHON_HOST_H
#define PYTHON_HOST_H

#include <stddef.h>

/// Called from the Python threads. `kind` and `payload` are valid only during the call.
typedef void (*PyHostEventCallback)(const char *kind, const char *payload, size_t length);

void pyhost_set_event_callback(PyHostEventCallback callback);

/// Answers `_pythilo.call(request)` from Python, on the calling Python thread,
/// with the GIL released. Returns 0 and a malloc'd response, or non-zero and a
/// malloc'd message. The host frees whichever it gets.
typedef int (*PyHostCallHandler)(const char *request, size_t length, char **response, size_t *response_length);

void pyhost_set_call_handler(PyHostCallHandler handler);

/// Starts the interpreter on its own thread. That thread is Python's main
/// thread, so signals, asyncio and framework servers behave as they do on a
/// desktop. Safe to call more than once; only the first call does anything.
void pyhost_start(const char *bundle_path, const char *cache_path);

/// Queues a job for the Python main thread. Jobs run one at a time.
void pyhost_submit(const char *json);

/// Queues work for the analysis thread, which runs while a job is running.
void pyhost_analyze(const char *json);

/// Delivers a real SIGINT to the Python main thread. A blocked sleep, socket or
/// read wakes with KeyboardInterrupt; a native call holding the GIL does not.
void pyhost_send_interrupt(void);

/// Writes to the pipe behind sys.stdin.
void pyhost_write_input(const char *utf8);

/// Writes a debugger command, which the paused run is waiting for.
void pyhost_write_debug_command(const char *utf8);

#endif
