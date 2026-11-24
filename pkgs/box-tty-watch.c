/*
 * box-tty-watch -- CMD [ARG...]
 *
 * Runs inside a `bwrap --new-session` sandbox. The boxed command is in its
 * own session, detached from the outer terminal's foreground process group,
 * so the kernel does not deliver SIGWINCH when the pane/PTY is resized. Poll
 * the inherited stdin TTY's TIOCGWINSZ and, on a change, send SIGWINCH to
 * every other process in the sandbox PID namespace.
 *
 * kill(-1, SIGWINCH) cannot escape the box: with --unshare-pid it only
 * reaches the sandbox's own processes, and the kernel skips PID 1 (bwrap)
 * and the caller. SIGWINCH's default action is ignore, so non-TUIs are
 * unaffected.
 *
 * stdin is only inspected with ioctl; it is never read. stdio is inherited
 * by the command, and the watcher exits with the command's status.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t forward_sig;

static void
handle_signal(int sig)
{
	forward_sig = sig;
}

static int
exit_status(int status)
{
	if (WIFEXITED(status))
		return WEXITSTATUS(status);
	if (WIFSIGNALED(status))
		return 128 + WTERMSIG(status);
	return 1;
}

static void
install_forwarder(int sig)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = handle_signal;
	sigemptyset(&sa.sa_mask);
	/* No SA_RESTART: let a signal interrupt waitpid/nanosleep. */
	if (sigaction(sig, &sa, NULL) < 0) {
		fprintf(stderr, "box-tty-watch: sigaction: %s\n", strerror(errno));
		_exit(127);
	}
}

int
main(int argc, char **argv)
{
	int i = 1;
	char **cmd;
	struct winsize prev;
	int have_tty;
	pid_t pid;

	if (i < argc && strcmp(argv[i], "--") == 0)
		i++;
	if (i >= argc) {
		fprintf(stderr, "usage: box-tty-watch -- CMD [ARG...]\n");
		return 2;
	}
	cmd = &argv[i];

	/* Non-TTY stdin: behave exactly like the bare command. */
	if (ioctl(STDIN_FILENO, TIOCGWINSZ, &prev) < 0) {
		execvp(cmd[0], cmd);
		fprintf(stderr, "box-tty-watch: exec %s: %s\n", cmd[0], strerror(errno));
		return 127;
	}
	have_tty = 1;

	install_forwarder(SIGTERM);
	install_forwarder(SIGINT);
	install_forwarder(SIGHUP);

	pid = fork();
	if (pid < 0) {
		fprintf(stderr, "box-tty-watch: fork: %s\n", strerror(errno));
		return 127;
	}
	if (pid == 0) {
		execvp(cmd[0], cmd);
		fprintf(stderr, "box-tty-watch: exec %s: %s\n", cmd[0], strerror(errno));
		_exit(127);
	}

	for (;;) {
		int status;
		pid_t r;

		r = waitpid(pid, &status, WNOHANG);
		if (r == pid)
			return exit_status(status);
		if (r < 0 && errno != EINTR)
			return 1;

		if (forward_sig != 0) {
			int sig = forward_sig;

			forward_sig = 0;
			kill(pid, sig);
		}

		if (have_tty) {
			struct winsize cur;

			if (ioctl(STDIN_FILENO, TIOCGWINSZ, &cur) == 0) {
				if (cur.ws_row != prev.ws_row ||
				    cur.ws_col != prev.ws_col) {
					prev = cur;
					kill(-1, SIGWINCH);
				}
			} else if (errno != EINTR) {
				/* PTY gone: let the command finish unwatched. */
				have_tty = 0;
			}
		}

		{
			struct timespec delay = { .tv_sec = 0, .tv_nsec = 100000000 };

			nanosleep(&delay, NULL);
		}
	}
}