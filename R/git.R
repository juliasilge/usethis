#' Initialise a git repository
#'
#' `use_git()` initialises a Git repository and adds important files to
#' `.gitignore`. If user consents, it also makes an initial commit.
#'
#' @param message Message to use for first commit.
#' @family git helpers
#' @export
#' @examples
#' \dontrun{
#' use_git()
#' }
use_git <- function(message = "Initial commit") {
  needs_init <- !uses_git()
  if (needs_init) {
    ui_done("Initialising Git repo")
    git_init()
  }

  use_git_ignore(c(".Rhistory", ".RData", ".Rproj.user"))
  if (git_uncommitted(untracked = TRUE)) {
    git_ask_commit(message, untracked = TRUE)
  }

  if (needs_init) {
    restart_rstudio("A restart of RStudio is required to activate the Git pane")
  }

  invisible(TRUE)
}

#' Add a git hook
#'
#' Sets up a git hook using specified script. Creates hook directory if
#' needed, and sets correct permissions on hook.
#'
#' @param hook Hook name. One of "pre-commit", "prepare-commit-msg",
#'   "commit-msg", "post-commit", "applypatch-msg", "pre-applypatch",
#'   "post-applypatch", "pre-rebase", "post-rewrite", "post-checkout",
#'   "post-merge", "pre-push", "pre-auto-gc".
#' @param script Text of script to run
#' @family git helpers
#' @export
use_git_hook <- function(hook, script) {
  check_uses_git()

  hook_path <- proj_path(".git", "hooks", hook)
  create_directory(path_dir(hook_path))

  write_over(hook_path, script)
  file_chmod(hook_path, "0744")

  invisible()
}

#' Tell Git to ignore files
#'
#' @param ignores Character vector of ignores, specified as file globs.
#' @param directory Directory relative to active project to set ignores
#' @family git helpers
#' @export
use_git_ignore <- function(ignores, directory = ".") {
  write_union(proj_path(directory, ".gitignore"), ignores)
  rstudio_git_tickle()
}

#' Configure Git
#'
#' Sets Git options, for either the user or the project ("global" or "local", in
#' Git terminology). Wraps [gert::git_config_set()] and
#' [gert::git_config_global_set()]. To inspect Git config, see
#' [gert::git_config()].
#'
#' @param ... Name-value pairs, processed as
#'   <[`dynamic-dots`][rlang::dyn-dots]>.
#'
#' @return Invisibly, the previous values of the modified components, as a named
#'   list.
#' @inheritParams edit
#'
#' @family git helpers
#' @export
#' @examples
#' \dontrun{
#' # set the user's global user.name and user.email
#' use_git_config(user.name = "Jane", user.email = "jane@example.org")
#'
#' # set the user.name and user.email locally, i.e. for current repo/project
#' use_git_config(
#'   scope = "project",
#'   user.name = "Jane",
#'   user.email = "jane@example.org"
#' )
#' }
use_git_config <- function(scope = c("user", "project"), ...) {
  scope <- match.arg(scope)

  dots <- list2(...)
  stopifnot(is_dictionaryish(dots))

  orig <- stats::setNames(
    vector(mode = "list", length = length(dots)),
    names(dots)
  )
  for (i in seq_along(dots)) {
    nm <- names(dots)[[i]]
    vl <- dots[[i]]
    if (scope == "user") {
      orig[nm] <- git_cfg_get(nm, "global") %||% list(NULL)
      gert::git_config_global_set(nm, vl)
    } else {
      check_uses_git()
      orig[nm] <- git_cfg_get(nm, "local") %||% list(NULL)
      gert::git_config_set(nm, vl, git_repo())
    }
  }

  invisible(orig)
}

#' Produce or register Git protocol
#'
#' @description
#' Git operations that address a remote use a so-called "transport protocol".
#' usethis supports SSH and HTTPS. The protocol affects this:
#'   * The default URL format for repos with no existing remote protocol:
#'     - `protocol = "https"` implies `https://github.com/<OWNER>/<REPO>.git`
#'     - `protocol = "ssh"` implies `git@@github.com:<OWNER>/<REPO>.git`
#' Two helper functions are available:
#'   * `git_protocol()` returns the user's preferred protocol, if known, and,
#'     otherwise, asks the user (interactive session), or defaults to SSH
#'     (non-interactive session).
#'   * `use_git_protocol()` allows the user to set the Git protocol, which is
#'     stored in the `usethis.protocol` option.
#'
#' Any interactive choice re: `protocol` comes with a reminder of how to set the
#' protocol at startup by setting an option in `.Rprofile`:
#' ```
#' options(usethis.protocol = "ssh")
#' ## or
#' options(usethis.protocol = "https")
#' ```
#'
#' @param protocol Optional. Should be "ssh" or "https", if specified. Defaults
#'   to the option `usethis.protocol` and, if unset, to an interactive choice
#'   or, in non-interactive sessions, "ssh". `NA` triggers the interactive menu.
#'
#' @return "ssh" or "https"
#' @export
#'
#' @examples
#' \dontrun{
#' ## consult the option and maybe get an interactive menu
#' git_protocol()
#'
#' ## explicitly set the protocol
#' use_git_protocol("ssh")
#' use_git_protocol("https")
#' }
git_protocol <- function() {
  protocol <- getOption(
    "usethis.protocol",
    default = if (is_interactive()) NA else "ssh"
  )

  # this is where a user-supplied protocol gets checked, because
  # use_git_protocol() shoves it in the option unconditionally and calls this
  bad_protocol <- length(protocol) != 1 ||
    !(tolower(protocol) %in% c("ssh", "https", NA))
  if (bad_protocol) {
    options(usethis.protocol = NULL)
    ui_stop("
      {ui_code('protocol')} must be one of {ui_value('ssh')}, \\
      {ui_value('https')}', or {ui_value('NA')}."
    )
  }

  if (is.na(protocol)) {
    protocol <- choose_protocol()
    if (is.null(protocol)) {
      ui_stop("
        {ui_code('protocol')} must be either {ui_value('ssh')} or \\
        {ui_value('https')}."
      )
    }
    code <- glue("options(usethis.protocol = \"{protocol}\")")
    ui_todo("
      Tip: To suppress this menu in future, put
      {ui_code(code)}
      in your script or in a user- or project-level startup file, \\
      {ui_value('.Rprofile')}.
      Call {ui_code('usethis::edit_r_profile()')} to open it for editing.")
  }

  protocol <- match.arg(tolower(protocol), c("ssh", "https"))
  options("usethis.protocol" = protocol)
  getOption("usethis.protocol")
}

#' @rdname git_protocol
#' @export
use_git_protocol <- function(protocol) {
  options("usethis.protocol" = protocol)
  git_protocol()
}

choose_protocol <- function() {
  if (!is_interactive()) {
    return(invisible())
  }
  choices <- c(
    ssh   = "ssh   <-- presumes that you have set up ssh keys",
    https = "https <-- choose this if you don't have ssh keys (or don't know if you do)"
  )
  choice <- utils::menu(
    choices = choices,
    title = "Which git protocol to use? (enter 0 to exit)"
  )
  if (choice == 0) {
    invisible()
  } else {
    names(choices)[choice]
  }
}

#' Configure and report Git remotes
#'
#' Two helpers are available:
#'   * `use_git_remote()` sets the remote associated with `name` to `url`.
#'   * `git_remotes()` reports the configured remotes, similar to
#'     `git remote -v`.
#'
#' @param name A string giving the short name of a remote.
#' @param url A string giving the url of a remote.
#' @param overwrite Logical. Controls whether an existing remote can be
#'   modified.
#'
#' @return Named list of Git remotes.
#' @export
#'
#' @examples
#' \dontrun{
#' # see current remotes
#' git_remotes()
#'
#' # add new remote named 'foo', a la `git remote add <name> <url>`
#' use_git_remote(name = "foo", url = "https://github.com/<OWNER>/<REPO>.git")
#'
#' # remove existing 'foo' remote, a la `git remote remove <name>`
#' use_git_remote(name = "foo", url = NULL, overwrite = TRUE)
#'
#' # change URL of remote 'foo', a la `git remote set-url <name> <newurl>`
#' use_git_remote(
#'   name = "foo",
#'   url = "https://github.com/<OWNER>/<REPO>.git",
#'   overwrite = TRUE
#' )
#'
#' # Scenario: Fix remotes when you cloned someone's repo, but you should
#' # have fork-and-cloned (in order to make a pull request).
#'
#' # Store origin = main repo's URL, e.g., "git@github.com:<OWNER>/<REPO>.git"
#' upstream_url <- git_remotes()[["origin"]]
#'
#' # IN THE BROWSER: fork the main GitHub repo and get your fork's remote URL
#' my_url <- "git@github.com:<ME>/<REPO>.git"
#'
#' # Rotate the remotes
#' use_git_remote(name = "origin", url = my_url)
#' use_git_remote(name = "upstream", url = upstream_url)
#' git_remotes()
#'
#' # Scenario: Add upstream remote to a repo that you fork-and-cloned, so you
#' # can pull upstream changes.
#' # Note: If you fork-and-clone via `usethis::create_from_github()`, this is
#' # done automatically!
#'
#' # Get URL of main GitHub repo, probably in the browser
#' upstream_url <- "git@github.com:<OWNER>/<REPO>.git"
#' use_git_remote(name = "upstream", url = upstream_url)
#' }
use_git_remote <- function(name = "origin", url, overwrite = FALSE) {
  stopifnot(is_string(name))
  stopifnot(is.null(url) || is_string(url))
  stopifnot(is_true(overwrite) || is_false(overwrite))

  remotes <- git_remotes()
  repo <- git_repo()

  if (name %in% names(remotes) && !overwrite) {
    ui_stop("
      Remote {ui_value(name)} already exists. Use \\
      {ui_code('overwrite = TRUE')} to edit it anyway.")
  }

  if (name %in% names(remotes)) {
    if (is.null(url)) {
      gert::git_remote_remove(name = name, repo = repo)
    } else {
      gert::git_remote_set_url(url = url, name = name, repo = repo)
    }
  } else if (!is.null(url)) {
    gert::git_remote_add(url = url, name = name, repo = repo)
  }

  invisible(git_remotes())
}

#' @rdname use_git_remote
#' @export
git_remotes <- function() {
  x <- gert::git_remote_list(repo = git_repo())
  if (nrow(x) == 0) {
    return(NULL)
  }
  stats::setNames(as.list(x$url), x$name)
}

#' Git/GitHub sitrep
#'
#' Get a situation report on your current Git/GitHub status. Useful for
#' diagnosing problems. [git_vaccinate()] adds some basic R- and RStudio-related
#' entries to the user-level git ignore file.
#' @export
#' @examples
#' \dontrun{
#' git_sitrep()
#' }
git_sitrep <- function() {
  # git global ----------------------------------------------------------------
  hd_line("Git config (global)")
  kv_line("Name", git_cfg_get("user.name", "global"))
  kv_line("Email", git_cfg_get("user.email", "global"))
  kv_line("Vaccinated", git_vaccinated())

  # git project ---------------------------------------------------------------
  if (proj_active() && uses_git()) {
    local_user <- list(
      user.name = git_cfg_get("user.name", "local"),
      user.email = git_cfg_get("user.email", "local")
    )
    if (!is.null(local_user$user.name) || !is.null(local_user$user.name)) {
      hd_line("Git config (project)")
      kv_line("Name", git_cfg_get("user.name"))
      kv_line("Email", git_cfg_get("user.email"))
    }
  }

  # usethis + gert + credentials -----------------------------------------------
  hd_line("usethis + gert")
  kv_line("Default usethis protocol", getOption("usethis.protocol"))
  kv_line("gert supports HTTPS", gert::libgit2_config()$https)
  kv_line("gert supports SSH", gert::libgit2_config()$ssh)
  # TODO: forward more info from the credentials package when available
  # https://github.com/r-lib/credentials/issues/6

  # github user ---------------------------------------------------------------
  hd_line("GitHub")
  have_token <- have_github_token()
  if (have_token) {
    kv_line("Personal access token", "<found in env var>")
    tryCatch(
      {
        who <- gh::gh_whoami(github_token())
        kv_line("User", who$login)
        kv_line("Name", who$name)
      },
      http_error_401 = function(e) ui_oops("Token is invalid."),
      error = function(e) ui_oops("Can't validate token. Is the network reachable?")
    )
    tryCatch(
      {
        emails <- unlist(gh::gh("/user/emails", .token = github_token()))
        emails <- emails[names(emails) == "email"]
        kv_line("Email(s)", emails)
      },
      http_error_404 = function(e) kv_line("Email(s)", "<unknown>"),
      error = function(e) ui_oops("Can't validate token. Is the network reachable?")
    )
  } else {
    kv_line("Personal access token", NULL)
  }

  # repo overview -------------------------------------------------------------
  hd_line("Repo")
  ui_silence(try(proj_get(), silent = TRUE))
  if (!proj_active()) {
    ui_info("No active usethis project.")
    return(invisible())
  }

  if (!uses_git()) {
    ui_info("Active project is not a Git repo.")
    return(invisible())
  }

  kv_line("Path", git_repo())
  branch <- tryCatch(git_branch(), error = function(e) NULL)
  tracking_branch <- if (is.null(branch)) NA_character_ else git_branch_tracking()
  ## TODO: rework when ui_*() functions make it possible to do better
  branch <- if (is.null(branch)) "<unset>" else branch
  tracking_branch <- if (is.na(tracking_branch)) "<unset>" else tracking_branch
  ui_inform(
    "* ", "Local branch -> remote tracking branch: ",
    ui_value(branch), " -> ", ui_value(tracking_branch)
  )

  # PR outlook -------------------------------------------------------------
  hd_line("GitHub pull request readiness")
  cfg <- classify_github_setup()
  if (cfg$type == "no_github") {
    ui_info("
      This repo has neither {ui_value('origin')} nor {ui_value('upstream')} \\
      remote on GitHub.com.")
    return(invisible())
  }
  # TODO: do something about unsupported configs
  # TODO: get some feedback then make this more attractive
  print(cfg)
}

# Vaccination -------------------------------------------------------------

#' Vaccinate your global gitignore file
#'
#' Adds `.DS_Store`, `.Rproj.user`, `.Rdata`, and `.Rhistory` to your global
#' (a.k.a. user-level) `.gitignore`. This is good practice as it decreases the
#' chance that you will accidentally leak credentials to GitHub.
#'
#' @export
git_vaccinate <- function() {
  path <- git_ignore_path("user")
  write_union(path, git_global_ignore)
}

git_vaccinated <- function() {
  path <- git_ignore_path("user")
  if (!file_exists(path)) {
    return(FALSE)
  }

  lines <- read_utf8(path)
  all(git_global_ignore %in% lines)
}

git_global_ignore <- c(
  ".Rproj.user",
  ".Rhistory",
  ".Rdata",
  ".DS_Store"
)
