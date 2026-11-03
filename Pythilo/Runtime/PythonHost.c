#include "PythonHost.h"

#include <Python/Python.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct Job {
    char *json;
    struct Job *next;
} Job;

typedef struct JobQueue {
    pthread_mutex_t lock;
    pthread_cond_t ready;
    Job *head;
    Job *tail;
} JobQueue;

static JobQueue main_queue = {PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER, NULL, NULL};
static JobQueue analysis_queue = {PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER, NULL, NULL};

static PyHostEventCallback event_callback = NULL;
static pthread_t python_thread;
static bool started = false;
static pthread_mutex_t start_lock = PTHREAD_MUTEX_INITIALIZER;
static int input_pipe[2] = {-1, -1};
static int debug_pipe[2] = {-1, -1};
static char *bundle_root = NULL;
static char *cache_root = NULL;

static void queue_push(JobQueue *queue, const char *json) {
    Job *job = malloc(sizeof(Job));
    job->json = strdup(json);
    job->next = NULL;
    pthread_mutex_lock(&queue->lock);
    if (queue->tail) {
        queue->tail->next = job;
    } else {
        queue->head = job;
    }
    queue->tail = job;
    pthread_cond_signal(&queue->ready);
    pthread_mutex_unlock(&queue->lock);
}

static char *queue_pop(JobQueue *queue) {
    pthread_mutex_lock(&queue->lock);
    while (queue->head == NULL) {
        pthread_cond_wait(&queue->ready, &queue->lock);
    }
    Job *job = queue->head;
    queue->head = job->next;
    if (queue->head == NULL) {
        queue->tail = NULL;
    }
    pthread_mutex_unlock(&queue->lock);
    char *json = job->json;
    free(job);
    return json;
}

static void send_event(const char *kind, const char *payload, size_t length) {
    if (event_callback) {
        event_callback(kind, payload, length);
    }
}

static void send_text_event(const char *kind, const char *text) {
    send_event(kind, text, strlen(text));
}

// The `_pythilo` module: the whole interface between the runtime and the app.

static PyObject *host_emit(PyObject *self, PyObject *args) {
    const char *kind;
    const char *payload;
    Py_ssize_t length;
    if (!PyArg_ParseTuple(args, "ss#", &kind, &payload, &length)) {
        return NULL;
    }
    send_event(kind, payload, (size_t)length);
    Py_RETURN_NONE;
}

static PyHostCallHandler call_handler = NULL;

void pyhost_set_call_handler(PyHostCallHandler handler) {
    call_handler = handler;
}

// A synchronous request to the app, such as a Core ML prediction. Bytes in, bytes out.
static PyObject *host_call(PyObject *self, PyObject *args) {
    const char *request;
    Py_ssize_t length;
    if (!PyArg_ParseTuple(args, "y#", &request, &length)) {
        return NULL;
    }
    if (call_handler == NULL) {
        PyErr_SetString(PyExc_RuntimeError, "The app does not answer calls here.");
        return NULL;
    }
    char *response = NULL;
    size_t response_length = 0;
    int status;
    Py_BEGIN_ALLOW_THREADS
    status = call_handler(request, (size_t)length, &response, &response_length);
    Py_END_ALLOW_THREADS
    PyObject *result;
    if (status == 0) {
        result = PyBytes_FromStringAndSize(response ? response : "", (Py_ssize_t)response_length);
    } else {
        PyErr_SetString(PyExc_RuntimeError, response ? response : "The app could not answer.");
        result = NULL;
    }
    free(response);
    return result;
}

static PyObject *host_input_fd(PyObject *self, PyObject *args) {
    return PyLong_FromLong(input_pipe[0]);
}

static PyObject *host_debug_fd(PyObject *self, PyObject *args) {
    return PyLong_FromLong(debug_pipe[0]);
}

static PyMethodDef host_methods[] = {
    {"emit", host_emit, METH_VARARGS, "Send an event to the app."},
    {"call", host_call, METH_VARARGS, "Ask the app something and wait for the answer."},
    {"input_fd", host_input_fd, METH_NOARGS, "Read end of the stdin pipe."},
    {"debug_fd", host_debug_fd, METH_NOARGS, "Read end of the debugger command pipe."},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef host_module = {
    PyModuleDef_HEAD_INIT, "_pythilo", NULL, -1, host_methods, NULL, NULL, NULL, NULL,
};

static PyObject *host_module_init(void) {
    return PyModule_Create(&host_module);
}

static void report_python_error(const char *context) {
    PyObject *type, *value, *traceback;
    PyErr_Fetch(&type, &value, &traceback);
    PyErr_NormalizeException(&type, &value, &traceback);
    PyObject *text = value ? PyObject_Str(value) : NULL;
    const char *message = text ? PyUnicode_AsUTF8(text) : "unknown error";
    char buffer[2048];
    snprintf(buffer, sizeof(buffer), "%s: %s", context, message ? message : "unknown error");
    send_text_event("host_error", buffer);
    Py_XDECREF(text);
    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(traceback);
    PyErr_Clear();
}

static bool initialize_python(void) {
    PyStatus status;
    PyPreConfig preconfig;
    PyConfig config;

    setenv("NO_COLOR", "1", 1);
    setenv("PYTHON_COLORS", "0", 1);

    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    status = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(status)) {
        send_text_event("host_error", status.err_msg ? status.err_msg : "pre-initialize failed");
        return false;
    }

    if (PyImport_AppendInittab("_pythilo", host_module_init) != 0) {
        send_text_event("host_error", "could not register the _pythilo module");
        return false;
    }

    PyConfig_InitIsolatedConfig(&config);
    config.buffered_stdio = 0;
    config.install_signal_handlers = 1;
    config.write_bytecode = 1;

    char path[4096];
    snprintf(path, sizeof(path), "%s/python", bundle_root);
    status = PyConfig_SetBytesString(&config, &config.home, path);
    if (!PyStatus_Exception(status)) {
        // The bundle is read-only, and a project folder should not fill up with
        // __pycache__, so all bytecode goes to one writable cache.
        snprintf(path, sizeof(path), "%s/pycache", cache_root);
        status = PyConfig_SetBytesString(&config, &config.pycache_prefix, path);
    }
    if (!PyStatus_Exception(status)) {
        status = PyConfig_Read(&config);
    }
    if (!PyStatus_Exception(status)) {
        status = Py_InitializeFromConfig(&config);
    }
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        send_text_event("host_error", status.err_msg ? status.err_msg : "initialize failed");
        return false;
    }
    return true;
}

static void *analysis_main(void *unused) {
    for (;;) {
        char *json = queue_pop(&analysis_queue);
        PyGILState_STATE gil = PyGILState_Ensure();
        PyObject *module = PyImport_ImportModule("pythilo_runtime.analysis");
        PyObject *result = module ? PyObject_CallMethod(module, "dispatch", "s", json) : NULL;
        if (!result) {
            report_python_error("analysis");
        }
        Py_XDECREF(result);
        Py_XDECREF(module);
        PyGILState_Release(gil);
        free(json);
    }
    return NULL;
}

static void *python_main(void *unused) {
    if (!initialize_python()) {
        return NULL;
    }

    char script[8192];
    snprintf(script, sizeof(script),
             "import sys, site\n"
             "sys.path.insert(0, %c%s/app%c)\n"
             "site.addsitedir(%c%s/app_packages%c)\n",
             '"', bundle_root, '"', '"', bundle_root, '"');
    if (PyRun_SimpleString(script) != 0) {
        send_text_event("host_error", "could not configure sys.path");
        return NULL;
    }

    PyObject *runtime = PyImport_ImportModule("pythilo_runtime");
    PyObject *booted = runtime ? PyObject_CallMethod(runtime, "boot", "ss", bundle_root, cache_root) : NULL;
    if (!booted) {
        report_python_error("boot");
        return NULL;
    }
    Py_DECREF(booted);

    PyThreadState *saved = PyEval_SaveThread();
    pthread_t analysis_thread;
    if (pthread_create(&analysis_thread, NULL, analysis_main, NULL) == 0) {
        pthread_detach(analysis_thread);
    }

    for (;;) {
        char *json = queue_pop(&main_queue);
        PyEval_RestoreThread(saved);
        PyObject *result = PyObject_CallMethod(runtime, "dispatch", "s", json);
        if (!result) {
            report_python_error("dispatch");
        }
        Py_XDECREF(result);
        saved = PyEval_SaveThread();
        free(json);
    }
    return NULL;
}

void pyhost_set_event_callback(PyHostEventCallback callback) {
    event_callback = callback;
}

void pyhost_start(const char *bundle_path, const char *cache_path) {
    pthread_mutex_lock(&start_lock);
    if (!started) {
        started = true;
        bundle_root = strdup(bundle_path);
        cache_root = strdup(cache_path);
        pipe(input_pipe);
        pipe(debug_pipe);
        pthread_attr_t attributes;
        pthread_attr_init(&attributes);
        // Recursive user code hits Python's recursion limit long before this.
        pthread_attr_setstacksize(&attributes, 16 * 1024 * 1024);
        pthread_create(&python_thread, &attributes, python_main, NULL);
        pthread_attr_destroy(&attributes);
    }
    pthread_mutex_unlock(&start_lock);
}

void pyhost_submit(const char *json) {
    queue_push(&main_queue, json);
}

void pyhost_analyze(const char *json) {
    queue_push(&analysis_queue, json);
}

void pyhost_send_interrupt(void) {
    if (started) {
        pthread_kill(python_thread, SIGINT);
    }
}

static void write_all(int fd, const char *text) {
    size_t remaining = strlen(text);
    while (remaining > 0 && fd >= 0) {
        ssize_t written = write(fd, text, remaining);
        if (written <= 0) {
            return;
        }
        text += written;
        remaining -= (size_t)written;
    }
}

void pyhost_write_input(const char *utf8) {
    write_all(input_pipe[1], utf8);
}

void pyhost_write_debug_command(const char *utf8) {
    write_all(debug_pipe[1], utf8);
}
