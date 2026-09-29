/*
 * Git: libgit2 repositories for Lua, without a git executable. iOS has no
 * process spawning, so Lua Studio cannot shell out to git; the same module
 * serves the Mac as a standalone plugin (build/Git.dylib, `require("Git")`)
 * and is statically linked and preloaded by the iOS hosts.
 *
 * Operations are synchronous and local. Failures of the repository return
 * `nil, message` like io.open; wrong argument types raise errors.
 */
#include <git2.h>
#include <lauxlib.h>
#include <lua.h>
#include <string.h>

#define REPOSITORY "Git.Repository"
#define STATUS_FIELDS 6

typedef struct {
	git_repository *repo;
} Repository;

static int push_failure(lua_State *L) {
	const git_error *error = git_error_last();
	lua_pushnil(L);
	lua_pushstring(L, error && error->message ? error->message : "git operation failed");
	return 2;
}

static git_repository *check_repo(lua_State *L) {
	Repository *self = luaL_checkudata(L, 1, REPOSITORY);
	if (!self->repo) luaL_error(L, "repository is closed");
	return self->repo;
}

static int push_repo(lua_State *L, git_repository *repo) {
	Repository *self = lua_newuserdatauv(L, sizeof(Repository), 0);
	self->repo = repo;
	luaL_setmetatable(L, REPOSITORY);
	return 1;
}

static void push_oid(lua_State *L, const git_oid *oid) {
	char hex[GIT_OID_MAX_HEXSIZE + 1];
	git_oid_tostr(hex, sizeof(hex), oid);
	lua_pushstring(L, hex);
}

/* A string or array of strings as a pathspec; nil matches every path. The
 * pointer array is a userdata left on the stack, so it lives as long as the
 * call; the strings stay referenced by the argument itself. */
static git_strarray check_pathspec(lua_State *L, int index) {
	git_strarray pathspec = {NULL, 0};
	if (lua_isnoneornil(L, index)) return pathspec;
	if (lua_type(L, index) == LUA_TSTRING) {
		pathspec.strings = lua_newuserdatauv(L, sizeof(char *), 0);
		pathspec.strings[0] = (char *)lua_tostring(L, index);
		pathspec.count = 1;
		return pathspec;
	}
	luaL_argexpected(L, lua_istable(L, index), index, "string or array of paths");
	size_t count = (size_t)luaL_len(L, index);
	pathspec.strings = lua_newuserdatauv(L, (count ? count : 1) * sizeof(char *), 0);
	for (size_t i = 0; i < count; i++) {
		if (lua_rawgeti(L, index, (lua_Integer)i + 1) != LUA_TSTRING)
			luaL_error(L, "path %d must be a string", (int)i + 1);
		pathspec.strings[i] = (char *)lua_tostring(L, -1);
		lua_pop(L, 1);
	}
	pathspec.count = count;
	return pathspec;
}

/* An optional options table: absent or nil, else it must be a table. */
static int check_options(lua_State *L, int index) {
	if (lua_isnoneornil(L, index)) return 0;
	luaL_checktype(L, index, LUA_TTABLE);
	return 1;
}

/* A string field of a table argument, or fallback when absent. The string
 * stays referenced by the table. */
static const char *opt_string_field(lua_State *L, int index, const char *field, const char *fallback) {
	int type = lua_getfield(L, index, field);
	const char *value = fallback;
	if (type == LUA_TSTRING) value = lua_tostring(L, -1);
	else if (type != LUA_TNIL) luaL_error(L, "%s must be a string", field);
	lua_pop(L, 1);
	return value;
}

/* libgit2 caches a repository's index in memory; re-read it so a change made
 * through another handle or process is neither missed nor overwritten. */
static int open_index(git_index **out, git_repository *repo) {
	int result = git_repository_index(out, repo);
	if (result == 0 && (result = git_index_read(*out, 0)) < 0) {
		git_index_free(*out);
		*out = NULL;
	}
	return result;
}

static int git_lua_version(lua_State *L) {
	int major, minor, patch;
	git_libgit2_version(&major, &minor, &patch);
	lua_pushfstring(L, "%d.%d.%d", major, minor, patch);
	return 1;
}

/* Git.init(path [, {initialBranch = "main"}]) creates missing parent folders. */
static int git_lua_init(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	git_repository_init_options options = GIT_REPOSITORY_INIT_OPTIONS_INIT;
	options.flags = GIT_REPOSITORY_INIT_MKPATH;
	options.initial_head = "main";
	if (check_options(L, 2)) options.initial_head = opt_string_field(L, 2, "initialBranch", "main");
	git_repository *repo = NULL;
	if (git_repository_init_ext(&repo, path, &options) < 0) return push_failure(L);
	return push_repo(L, repo);
}

/* Git.open(path) opens the repository whose worktree or .git folder is path.
 * It does not search parent folders: an app that keeps a repository in its
 * documents must not silently adopt an enclosing one. */
static int git_lua_open(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	git_repository *repo = NULL;
	if (git_repository_open_ext(&repo, path, GIT_REPOSITORY_OPEN_NO_SEARCH, NULL) < 0) return push_failure(L);
	return push_repo(L, repo);
}

static int repo_close(lua_State *L) {
	Repository *self = luaL_checkudata(L, 1, REPOSITORY);
	if (self->repo) git_repository_free(self->repo);
	self->repo = NULL;
	return 0;
}

static int repo_tostring(lua_State *L) {
	Repository *self = luaL_checkudata(L, 1, REPOSITORY);
	if (!self->repo) lua_pushliteral(L, "Git.Repository (closed)");
	else lua_pushfstring(L, "Git.Repository (%s)", git_repository_path(self->repo));
	return 1;
}

static int repo_workdir(lua_State *L) {
	const char *workdir = git_repository_workdir(check_repo(L));
	if (workdir) lua_pushstring(L, workdir); else lua_pushnil(L);
	return 1;
}

/* {branch, id, unborn, detached}; an unborn branch has a name but no id. */
static int repo_head(lua_State *L) {
	git_repository *repo = check_repo(L);
	lua_createtable(L, 0, 4);
	lua_pushboolean(L, git_repository_head_detached(repo) == 1);
	lua_setfield(L, -2, "detached");
	git_reference *head = NULL;
	int result = git_repository_head(&head, repo);
	if (result == GIT_EUNBORNBRANCH || result == GIT_ENOTFOUND) {
		lua_pushboolean(L, 1);
		lua_setfield(L, -2, "unborn");
		git_reference *symbolic = NULL;
		if (git_reference_lookup(&symbolic, repo, "HEAD") == 0) {
			const char *target = git_reference_symbolic_target(symbolic);
			if (target && strncmp(target, "refs/heads/", 11) == 0) {
				lua_pushstring(L, target + 11);
				lua_setfield(L, -2, "branch");
			}
			git_reference_free(symbolic);
		}
		return 1;
	}
	if (result < 0) return push_failure(L);
	lua_pushboolean(L, 0);
	lua_setfield(L, -2, "unborn");
	if (git_reference_is_branch(head)) {
		lua_pushstring(L, git_reference_shorthand(head));
		lua_setfield(L, -2, "branch");
	}
	push_oid(L, git_reference_target(head));
	lua_setfield(L, -2, "id");
	git_reference_free(head);
	return 1;
}

static const struct {
	unsigned int flag;
	const char *field;
	const char *value;
} STATUS_NAMES[] = {
	{GIT_STATUS_INDEX_NEW, "index", "added"},
	{GIT_STATUS_INDEX_MODIFIED, "index", "modified"},
	{GIT_STATUS_INDEX_DELETED, "index", "deleted"},
	{GIT_STATUS_INDEX_RENAMED, "index", "renamed"},
	{GIT_STATUS_INDEX_TYPECHANGE, "index", "typechange"},
	{GIT_STATUS_WT_NEW, "worktree", "untracked"},
	{GIT_STATUS_WT_MODIFIED, "worktree", "modified"},
	{GIT_STATUS_WT_DELETED, "worktree", "deleted"},
	{GIT_STATUS_WT_RENAMED, "worktree", "renamed"},
	{GIT_STATUS_WT_TYPECHANGE, "worktree", "typechange"},
	{GIT_STATUS_WT_UNREADABLE, "worktree", "unreadable"},
};

/* Array of {path, index?, worktree?, oldPath?, conflicted?}, sorted by path;
 * oldPath is set on renames. Ignored files are left out, and untracked
 * folders are listed file by file. */
static int repo_status(lua_State *L) {
	git_repository *repo = check_repo(L);
	git_status_options options = GIT_STATUS_OPTIONS_INIT;
	options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
	options.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS
		| GIT_STATUS_OPT_SORT_CASE_SENSITIVELY | GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX;
	git_status_list *list = NULL;
	if (git_status_list_new(&list, repo, &options) < 0) return push_failure(L);
	size_t count = git_status_list_entrycount(list);
	lua_createtable(L, (int)count, 0);
	for (size_t i = 0; i < count; i++) {
		const git_status_entry *entry = git_status_byindex(list, i);
		const git_diff_delta *delta = entry->index_to_workdir ? entry->index_to_workdir : entry->head_to_index;
		lua_createtable(L, 0, STATUS_FIELDS);
		lua_pushstring(L, delta->new_file.path ? delta->new_file.path : delta->old_file.path);
		lua_setfield(L, -2, "path");
		if (delta->status == GIT_DELTA_RENAMED) {
			lua_pushstring(L, delta->old_file.path);
			lua_setfield(L, -2, "oldPath");
		}
		for (size_t n = 0; n < sizeof(STATUS_NAMES) / sizeof(STATUS_NAMES[0]); n++) {
			if (!(entry->status & STATUS_NAMES[n].flag)) continue;
			lua_pushstring(L, STATUS_NAMES[n].value);
			lua_setfield(L, -2, STATUS_NAMES[n].field);
		}
		if (entry->status & GIT_STATUS_CONFLICTED) {
			lua_pushboolean(L, 1);
			lua_setfield(L, -2, "conflicted");
		}
		lua_rawseti(L, -2, (lua_Integer)i + 1);
	}
	git_status_list_free(list);
	return 1;
}

/* Tracked paths in the index, like `git ls-files`. */
static int repo_files(lua_State *L) {
	git_repository *repo = check_repo(L);
	git_index *index = NULL;
	if (open_index(&index, repo) < 0) return push_failure(L);
	size_t count = git_index_entrycount(index);
	lua_createtable(L, (int)count, 0);
	for (size_t i = 0; i < count; i++) {
		lua_pushstring(L, git_index_get_byindex(index, i)->path);
		lua_rawseti(L, -2, (lua_Integer)i + 1);
	}
	git_index_free(index);
	return 1;
}

/* repo:add([paths]) stages new, modified and deleted files matching the
 * pathspecs, like `git add --all`. */
static int repo_add(lua_State *L) {
	git_repository *repo = check_repo(L);
	git_strarray pathspec = check_pathspec(L, 2);
	git_index *index = NULL;
	if (open_index(&index, repo) < 0) return push_failure(L);
	int result = git_index_add_all(index, &pathspec, GIT_INDEX_ADD_DEFAULT, NULL, NULL);
	if (result == 0) result = git_index_update_all(index, &pathspec, NULL, NULL);
	if (result == 0) result = git_index_write(index);
	git_index_free(index);
	if (result < 0) return push_failure(L);
	lua_pushboolean(L, 1);
	return 1;
}

/* repo:unstage([paths]) restores index entries from HEAD, like
 * `git restore --staged`. Before the first commit it removes them. */
static int repo_unstage(lua_State *L) {
	git_repository *repo = check_repo(L);
	git_strarray pathspec = check_pathspec(L, 2);
	git_object *head = NULL;
	int result = git_revparse_single(&head, repo, "HEAD");
	if (result == GIT_ENOTFOUND) {
		git_index *index = NULL;
		result = open_index(&index, repo);
		if (result == 0) result = git_index_remove_all(index, &pathspec, NULL, NULL);
		if (result == 0) result = git_index_write(index);
		git_index_free(index);
	} else if (result == 0) {
		result = git_reset_default(repo, head, &pathspec);
		git_object_free(head);
	}
	if (result < 0) return push_failure(L);
	lua_pushboolean(L, 1);
	return 1;
}

static int check_signature(lua_State *L, int index, git_repository *repo, git_signature **out) {
	if (!check_options(L, index)) return git_signature_default(out, repo);
	const char *name = opt_string_field(L, index, "name", NULL);
	const char *email = opt_string_field(L, index, "email", NULL);
	luaL_argcheck(L, name && email, index, "author needs name and email");
	return git_signature_now(out, name, email);
}

/* repo:commit(message [, {name, email}]) commits the index on HEAD and
 * returns the new commit id. Without an author, the repository's
 * user.name/user.email configuration is used. */
static int repo_commit(lua_State *L) {
	git_repository *repo = check_repo(L);
	const char *message = luaL_checkstring(L, 2);
	git_signature *author = NULL;
	git_index *index = NULL;
	git_tree *tree = NULL;
	git_commit *parent = NULL;
	git_oid tree_id, commit_id;
	int result = check_signature(L, 3, repo, &author);
	if (result == 0) result = open_index(&index, repo);
	if (result == 0) result = git_index_write_tree(&tree_id, index);
	if (result == 0) result = git_tree_lookup(&tree, repo, &tree_id);
	if (result == 0) {
		git_object *head = NULL;
		int found = git_revparse_single(&head, repo, "HEAD^{commit}");
		if (found == 0) parent = (git_commit *)head;
		else if (found != GIT_ENOTFOUND) result = found;
	}
	if (result == 0) {
		const git_commit *parents[] = {parent};
		result = git_commit_create(&commit_id, repo, "HEAD", author, author, NULL, message,
			tree, parent ? 1 : 0, parents);
	}
	git_commit_free(parent);
	git_tree_free(tree);
	git_index_free(index);
	git_signature_free(author);
	if (result < 0) return push_failure(L);
	push_oid(L, &commit_id);
	return 1;
}

static void push_commit(lua_State *L, git_commit *commit) {
	const git_signature *author = git_commit_author(commit);
	char short_id[8];
	git_oid_tostr(short_id, sizeof(short_id), git_commit_id(commit));
	lua_createtable(L, 0, 7);
	push_oid(L, git_commit_id(commit));
	lua_setfield(L, -2, "id");
	lua_pushstring(L, short_id);
	lua_setfield(L, -2, "shortId");
	lua_pushstring(L, git_commit_summary(commit) ? git_commit_summary(commit) : "");
	lua_setfield(L, -2, "summary");
	lua_pushstring(L, git_commit_message(commit));
	lua_setfield(L, -2, "message");
	lua_pushstring(L, author->name);
	lua_setfield(L, -2, "author");
	lua_pushstring(L, author->email);
	lua_setfield(L, -2, "email");
	lua_pushinteger(L, (lua_Integer)author->when.time);
	lua_setfield(L, -2, "time");
}

/* repo:log([{limit, from}]) lists commits reachable from `from` (default
 * HEAD), newest first. An unborn branch has an empty log. */
static int repo_log(lua_State *L) {
	git_repository *repo = check_repo(L);
	lua_Integer limit = -1;
	const char *from = "HEAD";
	if (check_options(L, 2)) {
		if (lua_getfield(L, 2, "limit") != LUA_TNIL) {
			int exact = 0;
			limit = lua_tointegerx(L, -1, &exact);
			if (!exact || limit < 0) luaL_error(L, "limit must be a non-negative integer");
		}
		lua_pop(L, 1);
		from = opt_string_field(L, 2, "from", "HEAD");
	}
	git_object *start = NULL;
	int result = git_revparse_single(&start, repo, from);
	if (result == GIT_ENOTFOUND && strcmp(from, "HEAD") == 0) {
		lua_newtable(L);
		return 1;
	}
	if (result < 0) return push_failure(L);
	git_revwalk *walk = NULL;
	result = git_revwalk_new(&walk, repo);
	if (result == 0) result = git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL | GIT_SORT_TIME);
	if (result == 0) result = git_revwalk_push(walk, git_object_id(start));
	git_object_free(start);
	if (result < 0) {
		git_revwalk_free(walk);
		return push_failure(L);
	}
	lua_newtable(L);
	git_oid id;
	lua_Integer count = 0;
	while ((limit < 0 || count < limit) && (result = git_revwalk_next(&id, walk)) == 0) {
		git_commit *commit = NULL;
		if ((result = git_commit_lookup(&commit, repo, &id)) < 0) break;
		push_commit(L, commit);
		git_commit_free(commit);
		lua_rawseti(L, -2, ++count);
	}
	git_revwalk_free(walk);
	if (result < 0 && result != GIT_ITEROVER) return push_failure(L);
	return 1;
}

/* Local branches: array of {name, id, current}. */
static int repo_branches(lua_State *L) {
	git_repository *repo = check_repo(L);
	git_branch_iterator *iterator = NULL;
	if (git_branch_iterator_new(&iterator, repo, GIT_BRANCH_LOCAL) < 0) return push_failure(L);
	lua_newtable(L);
	git_reference *ref = NULL;
	git_branch_t type;
	lua_Integer count = 0;
	int result;
	while ((result = git_branch_next(&ref, &type, iterator)) == 0) {
		const char *name = NULL;
		git_branch_name(&name, ref);
		lua_createtable(L, 0, 3);
		lua_pushstring(L, name);
		lua_setfield(L, -2, "name");
		if (git_reference_target(ref)) {
			push_oid(L, git_reference_target(ref));
			lua_setfield(L, -2, "id");
		}
		lua_pushboolean(L, git_branch_is_head(ref) == 1);
		lua_setfield(L, -2, "current");
		lua_rawseti(L, -2, ++count);
		git_reference_free(ref);
	}
	git_branch_iterator_free(iterator);
	if (result != GIT_ITEROVER) return push_failure(L);
	return 1;
}

/* repo:createBranch(name [, from]) branches from a revision (default HEAD)
 * without checking it out. */
static int repo_create_branch(lua_State *L) {
	git_repository *repo = check_repo(L);
	const char *name = luaL_checkstring(L, 2);
	const char *from = luaL_optstring(L, 3, "HEAD");
	git_object *target = NULL;
	git_reference *branch = NULL;
	int result = git_revparse_single(&target, repo, from);
	if (result == 0) {
		git_commit *commit = NULL;
		result = git_commit_lookup(&commit, repo, git_object_id(target));
		if (result == 0) result = git_branch_create(&branch, repo, name, commit, 0);
		git_commit_free(commit);
	}
	git_object_free(target);
	git_reference_free(branch);
	if (result < 0) return push_failure(L);
	lua_pushboolean(L, 1);
	return 1;
}

/* repo:checkout(branch) switches to a local branch. The checkout is safe:
 * it fails instead of overwriting uncommitted changes to affected files. */
static int repo_checkout(lua_State *L) {
	git_repository *repo = check_repo(L);
	const char *name = luaL_checkstring(L, 2);
	git_reference *branch = NULL;
	git_object *tree = NULL;
	git_checkout_options options = GIT_CHECKOUT_OPTIONS_INIT;
	options.checkout_strategy = GIT_CHECKOUT_SAFE;
	int result = git_branch_lookup(&branch, repo, name, GIT_BRANCH_LOCAL);
	if (result == 0) result = git_reference_peel(&tree, branch, GIT_OBJECT_TREE);
	if (result == 0) result = git_checkout_tree(repo, tree, &options);
	if (result == 0) result = git_repository_set_head(repo, git_reference_name(branch));
	git_object_free(tree);
	git_reference_free(branch);
	if (result < 0) return push_failure(L);
	lua_pushboolean(L, 1);
	return 1;
}

/* repo:diff([{staged = true}]) returns a unified patch: unstaged changes
 * (index to worktree) by default, staged ones (HEAD to index) on request. */
static int repo_diff(lua_State *L) {
	git_repository *repo = check_repo(L);
	int staged = 0;
	if (check_options(L, 2)) {
		lua_getfield(L, 2, "staged");
		staged = lua_toboolean(L, -1);
		lua_pop(L, 1);
	}
	git_diff *diff = NULL;
	int result;
	if (staged) {
		git_object *tree = NULL;
		result = git_revparse_single(&tree, repo, "HEAD^{tree}");
		if (result == GIT_ENOTFOUND) result = 0;
		if (result == 0) result = git_diff_tree_to_index(&diff, repo, (git_tree *)tree, NULL, NULL);
		git_object_free(tree);
	} else {
		result = git_diff_index_to_workdir(&diff, repo, NULL, NULL);
	}
	git_buf patch = GIT_BUF_INIT;
	if (result == 0) result = git_diff_to_buf(&patch, diff, GIT_DIFF_FORMAT_PATCH);
	git_diff_free(diff);
	if (result < 0) {
		git_buf_dispose(&patch);
		return push_failure(L);
	}
	lua_pushlstring(L, patch.ptr ? patch.ptr : "", patch.size);
	git_buf_dispose(&patch);
	return 1;
}

/* repo:show(revision, path) returns a file's bytes at a revision, like
 * `git show revision:path`. */
static int repo_show(lua_State *L) {
	git_repository *repo = check_repo(L);
	const char *revision = luaL_checkstring(L, 2);
	const char *path = luaL_checkstring(L, 3);
	lua_pushfstring(L, "%s:%s", revision, path);
	git_object *object = NULL;
	int result = git_revparse_single(&object, repo, lua_tostring(L, -1));
	lua_pop(L, 1);
	if (result < 0) return push_failure(L);
	if (git_object_type(object) != GIT_OBJECT_BLOB) {
		git_object_free(object);
		lua_pushnil(L);
		lua_pushfstring(L, "%s is not a file at %s", path, revision);
		return 2;
	}
	git_blob *blob = (git_blob *)object;
	lua_pushlstring(L, git_blob_rawcontent(blob), (size_t)git_blob_rawsize(blob));
	git_object_free(object);
	return 1;
}

static const luaL_Reg repo_methods[] = {
	{"close", repo_close},
	{"workdir", repo_workdir},
	{"head", repo_head},
	{"status", repo_status},
	{"files", repo_files},
	{"add", repo_add},
	{"unstage", repo_unstage},
	{"commit", repo_commit},
	{"log", repo_log},
	{"branches", repo_branches},
	{"createBranch", repo_create_branch},
	{"checkout", repo_checkout},
	{"diff", repo_diff},
	{"show", repo_show},
	{NULL, NULL}
};

static const luaL_Reg module_functions[] = {
	{"version", git_lua_version},
	{"init", git_lua_init},
	{"open", git_lua_open},
	{NULL, NULL}
};

int luaopen_Git(lua_State *L) {
	/* Initialization is reference counted and never undone: repositories may
	 * outlive any one Lua state (the iOS host reboots its state on reload). */
	static int initialized;
	if (!initialized) {
		git_libgit2_init();
		initialized = 1;
	}
	if (luaL_newmetatable(L, REPOSITORY)) {
		luaL_newlib(L, repo_methods);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, repo_close);
		lua_setfield(L, -2, "__gc");
		lua_pushcfunction(L, repo_close);
		lua_setfield(L, -2, "__close");
		lua_pushcfunction(L, repo_tostring);
		lua_setfield(L, -2, "__tostring");
	}
	lua_pop(L, 1);
	luaL_newlib(L, module_functions);
	return 1;
}
