#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int extract_launch_target(const char *argument, char *target,
                                 size_t target_size) {
	const char marker[] = "\"target\"";
	const char *position = strstr(argument, marker);
	if (position == NULL)
		return 0;
	position += sizeof(marker) - 1;
	while (*position == ' ' || *position == '\t')
		++position;
	if (*position++ != ':')
		return 0;
	while (*position == ' ' || *position == '\t')
		++position;
	if (*position++ != '"')
		return 0;

	size_t length = 0;
	while (*position != '\0' && *position != '"') {
		char character = *position++;
		if (!((character >= 'a' && character <= 'z') ||
		      (character >= 'A' && character <= 'Z') ||
		      (character >= '0' && character <= '9') || character == '_' ||
		      character == '-'))
			return 0;
		if (length + 1 >= target_size)
			return 0;
		target[length++] = character;
	}
	if (*position != '"' || length == 0)
		return 0;
	target[length] = '\0';
	return 1;
}

static void set_webos_locale(char *gui_language) {
	gui_language[0] = '\0';

	FILE *locale_file = fopen("/var/luna/preferences/localeInfo", "r");
	if (locale_file == NULL)
		return;

	char contents[4096];
	size_t length = fread(contents, 1, sizeof(contents) - 1, locale_file);
	fclose(locale_file);
	contents[length] = '\0';

	const char marker[] = "\"UI\":\"";
	char *ui = strstr(contents, marker);
	if (ui == NULL)
		return;
	ui += sizeof(marker) - 1;

	char locale[32];
	size_t destination = 0;
	while (*ui != '\0' && *ui != '"' &&
	       destination < sizeof(locale) - sizeof(".UTF-8")) {
		locale[destination++] = *ui == '-' ? '_' : *ui;
		++ui;
	}
	if (destination < 2)
		return;

	gui_language[0] = locale[0];
	gui_language[1] = locale[1];
	gui_language[2] = '\0';

	memcpy(locale + destination, ".UTF-8", sizeof(".UTF-8"));
	setenv("LANG", locale, 1);
	setenv("LC_MESSAGES", locale, 1);
}

static void ensure_gui_language(const char *gui_language) {
	if (gui_language[0] == '\0')
		return;

	const char *home = getenv("HOME");
	if (home == NULL)
		return;

	char config_directory[PATH_MAX];
	char config_path[PATH_MAX];
	char temporary_path[PATH_MAX];
	if (snprintf(config_directory, sizeof(config_directory),
	             "%s/.config/scummvm", home) >= (int)sizeof(config_directory) ||
	    snprintf(config_path, sizeof(config_path), "%s/scummvm.ini",
	             config_directory) >= (int)sizeof(config_path) ||
	    snprintf(temporary_path, sizeof(temporary_path), "%s.tmp.%ld",
	             config_path, (long)getpid()) >= (int)sizeof(temporary_path))
		return;

	FILE *config = fopen(config_path, "r");
	if (config != NULL) {
		char line[1024];
		while (fgets(line, sizeof(line), config) != NULL) {
			if (strncmp(line, "gui_language=", sizeof("gui_language=") - 1) ==
			    0) {
				fclose(config);
				return;
			}
		}
		rewind(config);
	} else if (errno != ENOENT) {
		return;
	}

	char parent_directory[PATH_MAX];
	if (snprintf(parent_directory, sizeof(parent_directory), "%s/.config",
	             home) >= (int)sizeof(parent_directory)) {
		if (config != NULL)
			fclose(config);
		return;
	}
	mkdir(parent_directory, 0755);
	mkdir(config_directory, 0755);

	FILE *temporary = fopen(temporary_path, "w");
	if (temporary == NULL) {
		if (config != NULL)
			fclose(config);
		return;
	}

	int inserted = 0;
	if (config != NULL) {
		char line[1024];
		while (fgets(line, sizeof(line), config) != NULL) {
			fputs(line, temporary);
			if (!inserted &&
			    (strcmp(line, "[scummvm]\n") == 0 ||
			     strcmp(line, "[scummvm]\r\n") == 0)) {
				fprintf(temporary, "gui_language=%s\n", gui_language);
				inserted = 1;
			}
		}
		fclose(config);
	}
	if (!inserted)
		fprintf(temporary, "\n[scummvm]\ngui_language=%s\n", gui_language);

	if (fclose(temporary) == 0) {
		if (rename(temporary_path, config_path) < 0)
			unlink(temporary_path);
	} else {
		unlink(temporary_path);
	}
}

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
	char gui_language[3];
	set_webos_locale(gui_language);
	ensure_gui_language(gui_language);

	char **child_argv = calloc((size_t)argc + 2, sizeof(*child_argv));
	if (child_argv == NULL) {
		perror("calloc");
		return 1;
	}

	char launch_target[65] = {0};
	child_argv[0] = scummvm;
	int source = 1;
	int destination = 1;
	while (source < argc) {
		if (extract_launch_target(argv[source], launch_target,
		                          sizeof(launch_target))) {
			++source;
			continue;
		}
		child_argv[destination++] = argv[source++];
	}
	if (launch_target[0] != '\0')
		child_argv[destination++] = launch_target;

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
