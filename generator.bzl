load("@bazel_skylib//lib:shell.bzl", "shell")
load("//:rules.bzl", "LinterInfo")


# Aspects that accept parameters cannot be called on the command line.
# As I want to call the linter aspect on the command line I can't pass parameters.
# Thus, I can't pass a 'debug' parameter to the aspect.
# So here I make a global to allow switching DEBUG logs on an off
DEBUG=True

def debug(msg):
    if DEBUG:
        print(msg)


def _select_linter(ctx):
    kind = ctx.rule.kind
    if kind in ["py_library", "py_binary"]:
        return ctx.attr._python_linter
    debug("No linter for rule kind: {}".format(kind))
    return None

def _lint_workspace_aspect_impl(target, ctx):
    if (
        # Ignore targets in external repos
        ctx.label.workspace_name or
        # Ignore targets without source files
        not hasattr(ctx.rule.attr, 'srcs')
    ):
        return  []

    linter = _select_linter(ctx)
    if not linter:
        return []

    repo_root = ctx.var["repo_root"]

    out = ctx.actions.declare_file("%s.lint_report" % ctx.rule.attr.name)
    src_files = [
        file for src in ctx.rule.attr.srcs
        for file in src.files.to_list()
    ]

    linter_exe = linter[LinterInfo].executable_path
    cmd = "{linter_exe} {srcs} > {out}".format(
        linter_exe = linter_exe,
        out = shell.quote(out.path),
        srcs = " ".join([
            shell.quote("{}/{}".format(repo_root, src_f.path)) for
            src_f in src_files
        ]),
    )

    ctx.actions.run_shell(
        outputs = [out],
        inputs = src_files,
        command = cmd,
        mnemonic = "Lint",
        use_default_shell_env = True,
        progress_message = "Linting with black: {srcs}".format(srcs=" ".join([src_f.path for src_f in src_files])),
        execution_requirements = {
            "no-sandbox": "1",
        }
    )

    return [
        DefaultInfo(files = depset([out])),
        OutputGroupInfo(
            report = depset([out]),
        )
    ]


def linting_aspect_generator(
        name,
        linters,
):
    return aspect(
        implementation = _lint_workspace_aspect_impl,
        attr_aspects = [],
        attrs = {
            '_python_linter' : attr.label(
                default = linters[0],
            )
        }
    )