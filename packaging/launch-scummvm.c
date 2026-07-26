#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
	char executable[PATH_MAX];
	ssize_t executable_length =
	    readlink("/proc/self/exe", executable, sizeof(executable) - 1);
	if (executable_length < 0) {
		perror("readlink");
		return 1;
	}
	executable[executable_length] = '\0';

	char *separator = strrchr(executable, '/');
	if (separator == NULL) {
		fputs("Could not determine application directory\n", stderr);
		return 1;
	}
	*separator = '\0';

	char scummvm[PATH_MAX];
	if (snprintf(scummvm, sizeof(scummvm), "%s/scummvm.bin", executable) >=
	    (int)sizeof(scummvm)) {
		fputs("ScummVM path is too long\n", stderr);
		return 1;
	}

	char library_path[PATH_MAX];
	if (snprintf(library_path, sizeof(library_path), "%s/lib", executable) >=
	    (int)sizeof(library_path)) {
		fputs("Library path is too long\n", stderr);
		return 1;
	}
	if (setenv("LD_LIBRARY_PATH", library_path, 1) < 0) {
		perror("setenv");
		return 1;
	}

	char **child_argv = calloc((size_t)argc + 1, sizeof(*child_argv));
	if (child_argv == NULL) {
		perror("calloc");
		return 1;
	}

	child_argv[0] = scummvm;
	int source = 1;
	if (argc > 1 && argv[1][0] == '{') {
		source = 2;
	}
	int destination = 1;
	while (source < argc) {
		child_argv[destination++] = argv[source++];
	}

	int log = open("/tmp/org.scummvm.scummvm.log",
	               O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (log >= 0) {
		dup2(log, STDOUT_FILENO);
		dup2(log, STDERR_FILENO);
		close(log);
	}

	execv(scummvm, child_argv);
	dprintf(STDERR_FILENO, "Could not start ScummVM: %s\n", strerror(errno));
	return 1;
}
