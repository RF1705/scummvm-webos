#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/*
 * LG libhelpers' HJson API. No header ships with it; these signatures come
 * from the disassembly of the stock libhelpers.so.2 of webOS 1 (WT1H),
 * webOS 6 (W21A) and webOS 24 (W24G), which agree:
 *   HString *HJson_getValueFromStr(const char *json, const char *key);
 *     NULL for invalid JSON or a missing or null key; an object value is
 *     returned serialized. The caller frees the result with HString_free().
 *   const char *HString_toStr(HString *string);
 *   void HString_free(HString *string);
 * They only use pbnjson: no Luna call and no g_lsMutex.
 */
typedef struct HString HString;
static HString *(*hjson_get_value_from_str)(const char *json, const char *key);
static const char *(*hstring_to_str)(HString *string);
static void (*hstring_free)(HString *string);

static int load_hjson(void) {
	void *helpers = dlopen("libhelpers.so.2", RTLD_NOW | RTLD_LOCAL);
	if (helpers == NULL)
		return 0;
	hjson_get_value_from_str = (HString * (*)(const char *, const char *))
	    dlsym(helpers, "HJson_getValueFromStr");
	hstring_to_str = (const char *(*)(HString *))dlsym(helpers, "HString_toStr");
	hstring_free = (void (*)(HString *))dlsym(helpers, "HString_free");
	return hjson_get_value_from_str != NULL && hstring_to_str != NULL &&
	       hstring_free != NULL;
}

/* The value of key in json as a malloc'd string, or NULL. */
static char *json_value(const char *json, const char *key) {
	if (json == NULL)
		return NULL;
	HString *value = hjson_get_value_from_str(json, key);
	if (value == NULL)
		return NULL;
	const char *string = hstring_to_str(value);
	char *copy = string != NULL ? strdup(string) : NULL;
	hstring_free(value);
	return copy;
}

static int valid_target(const char *target) {
	size_t length = strlen(target);
	if (length == 0 || length > 64)
		return 0;
	for (size_t i = 0; i < length; ++i) {
		char c = target[i];
		if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		      (c >= '0' && c <= '9') || c == '_' || c == '-'))
			return 0;
	}
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

	/* {"localeInfo": {"locales": {"UI": "en-GB", ...}, ...}, ...} */
	char *info = json_value(contents, "localeInfo");
	char *locales = json_value(info, "locales");
	char *ui = json_value(locales, "UI");
	free(info);
	free(locales);
	if (ui == NULL)
		return;

	char locale[32];
	size_t destination = 0;
	for (const char *source = ui;
	     *source != '\0' && destination < sizeof(locale) - sizeof(".UTF-8");
	     ++source)
		locale[destination++] = *source == '-' ? '_' : *source;
	free(ui);
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

/*
 * Loaded through a DT_NEEDED entry of scummvm.bin, so this runs before main()
 * in the process webOS launched. webOS 1 grants the app's Luna role only to
 * the executable named by appinfo "main", so the setup must not exec another
 * program.
 */
__attribute__((constructor)) static void scummvm_webos_init(int argc,
                                                            char **argv) {
	int log = open("/tmp/org.scummvm.scummvm.log",
	               O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (log >= 0) {
		dup2(log, STDOUT_FILENO);
		dup2(log, STDERR_FILENO);
		close(log);
	}

	if (setenv("SDL_WEBOS_ACCESS_POLICY_KEYS_BACK", "true", 1) < 0)
		perror("setenv SDL_WEBOS_ACCESS_POLICY_KEYS_BACK");

	if (!load_hjson())
		return;

	char gui_language[3];
	set_webos_locale(gui_language);
	ensure_gui_language(gui_language);

	/* A {"target":"<name>"} launch argument becomes the last argument, where
	 * ScummVM expects the target. */
	for (int source = 1; source < argc; ++source) {
		if (argv[source][0] != '{')
			continue;
		char *target = json_value(argv[source], "target");
		if (target == NULL)
			continue;
		if (!valid_target(target)) {
			free(target);
			continue;
		}
		memmove(&argv[source], &argv[source + 1],
		        (size_t)(argc - source - 1) * sizeof(*argv));
		argv[argc - 1] = target;
		break;
	}
}
