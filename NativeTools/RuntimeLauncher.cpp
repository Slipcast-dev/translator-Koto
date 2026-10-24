// Небольшой watchdog владеет единственным дочерним runtime и переживает аварийный выход GUI.
// Он не читает запросы, модель или API-ключ: только exec, ожидание и безопасное завершение child.
#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/wait.h>
#include <unistd.h>

namespace {
volatile std::sig_atomic_t stop_requested = 0;
void on_signal(int) { stop_requested = 1; }

// RAII гарантирует reap: нельзя оставить зомби или передать владение случайному PID.
class ChildProcess {
public:
    explicit ChildProcess(pid_t pid) : pid_(pid) {}
    ChildProcess(const ChildProcess&) = delete;
    ChildProcess& operator=(const ChildProcess&) = delete;
    ~ChildProcess() { stop(); }
    bool poll(int& status) {
        if (pid_ <= 0) return true;
        const auto result = waitpid(pid_, &status, WNOHANG);
        if (result == pid_ || (result < 0 && errno == ECHILD)) { pid_ = -1; return true; }
        return false;
    }
    void stop() {
        if (pid_ <= 0) return;
        kill(pid_, SIGTERM);
        int status = 0;
        for (int attempt = 0; attempt < 20; ++attempt) {
            if (poll(status)) return;
            usleep(50000);
        }
        kill(pid_, SIGKILL);
        while (waitpid(pid_, &status, 0) < 0 && errno == EINTR) {}
        pid_ = -1;
    }
private:
    pid_t pid_;
};
}

int main(int argc, char* argv[]) {
    // Первый аргумент — sibling llama-server. Никакого shell или интерпретации строк.
    if (argc < 2) return 64;
    const pid_t parent = getppid();
    if (parent <= 1) return 65;
    const std::string path(argv[1]);
    const auto slash = path.rfind('/');
    if (slash == std::string::npos || path.substr(slash + 1) != "llama-server") return 66;
    std::signal(SIGTERM, on_signal);
    std::signal(SIGINT, on_signal);
    const pid_t pid = fork();
    if (pid < 0) return 71;
    if (pid == 0) {
        std::signal(SIGTERM, SIG_DFL);
        std::signal(SIGINT, SIG_DFL);
        execv(argv[1], argv + 1);
        _exit(127);
    }
    ChildProcess child(pid);
    int status = 0;
    while (!child.poll(status)) {
        // После смерти GUI kernel переподчиняет watchdog другому parent; PID reuse не даёт ложный успех.
        if (stop_requested || getppid() != parent) { child.stop(); return 0; }
        usleep(100000);
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
