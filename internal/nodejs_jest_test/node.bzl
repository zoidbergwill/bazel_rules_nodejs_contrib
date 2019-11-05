# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Executing programs

These rules run the node binary with the given sources.

They support module mapping: any targets in the transitive dependencies with
a `module_name` attribute can be `require`d by that name.
"""

load("@build_bazel_rules_nodejs//internal/common:module_mappings.bzl", "module_mappings_runtime_aspect")
load("@build_bazel_rules_nodejs//internal/common:expand_into_runfiles.bzl", "expand_location_into_runfiles")
load("@build_bazel_rules_nodejs//internal/common:npm_package_info.bzl", "NpmPackageInfo", "node_modules_aspect")

def _trim_package_node_modules(package_name):
    # trim a package name down to its path prior to a node_modules
    # segment. 'foo/node_modules/bar' would become 'foo' and
    # 'node_modules/bar' would become ''
    segments = []
    for n in package_name.split("/"):
        if n == "node_modules":
            break
        segments += [n]
    return "/".join(segments)

def _write_loader_script(ctx, entry_point):
    # Generates the JavaScript snippet of module roots mappings, with each entry
    # in the form:
    #   {module_name: /^mod_name\b/, module_root: 'path/to/mod_name'}
    module_mappings = []
    for d in ctx.attr.data:
        if hasattr(d, "runfiles_module_mappings"):
            for [mn, mr] in d.runfiles_module_mappings.items():
                escaped = mn.replace("/", "\/").replace(".", "\.")
                mapping = "{module_name: /^%s\\b/, module_root: '%s'}" % (escaped, mr)
                module_mappings.append(mapping)

    node_modules_root = None
    if ctx.files.node_modules:
        # ctx.files.node_modules is not an empty list
        workspace = ctx.attr.node_modules.label.workspace_root.split("/")[1] if ctx.attr.node_modules.label.workspace_root else ctx.workspace_name
        node_modules_root = "/".join([f for f in [
            workspace,
            _trim_package_node_modules(ctx.attr.node_modules.label.package),
            "node_modules",
        ] if f])
    for d in ctx.attr.data:
        if NpmPackageInfo in d:
            possible_root = "/".join([d[NpmPackageInfo].workspace, "node_modules"])
            if not node_modules_root:
                node_modules_root = possible_root
            elif node_modules_root != possible_root:
                fail("All npm dependencies need to come from a single workspace. Found '%s' and '%s'." % (node_modules_root, possible_root))
    if not node_modules_root:
        # there are no fine grained deps and the node_modules attribute is an empty filegroup
        # but we still need a node_modules_root even if its empty
        workspace = ctx.attr.node_modules.label.workspace_root.split("/")[1] if ctx.attr.node_modules.label.workspace_root else ctx.workspace_name
        node_modules_root = "/".join([f for f in [
            workspace,
            ctx.attr.node_modules.label.package,
            "node_modules",
        ] if f])

    ctx.actions.expand_template(
        template = ctx.file._loader_template,
        output = ctx.outputs.loader,
        substitutions = {
            "TEMPLATED_target": str(ctx.label),
            "TEMPLATED_module_roots": "\n  " + ",\n  ".join(module_mappings),
            "TEMPLATED_bootstrap": "\n  " + ",\n  ".join(
                ["\"" + d + "\"" for d in ctx.attr.bootstrap],
            ),
            "TEMPLATED_entry_point": entry_point,
            "TEMPLATED_user_workspace_name": ctx.workspace_name,
            "TEMPLATED_node_modules_root": node_modules_root,
            "TEMPLATED_install_source_map_support": str(ctx.attr.install_source_map_support).lower(),
            "TEMPLATED_bin_dir": ctx.bin_dir.path,
            "TEMPLATED_gen_dir": ctx.genfiles_dir.path,
        },
        is_executable = True,
    )

def short_path_to_manifest_path(ctx, short_path):
    if short_path.startswith("../"):
        return short_path[3:]
    else:
        return ctx.workspace_name + "/" + short_path

def nodejs_binary_impl(ctx, entry_point = None, files = []):
    node = ctx.file.node
    node_modules = ctx.files.node_modules
    entry_point = entry_point or ctx.attr.entry_point
    sources = []
    for d in ctx.attr.data:
        if hasattr(d, "node_sources"):
            sources += d.node_sources.to_list()
        if hasattr(d, "files"):
            sources += d.files.to_list()

    _write_loader_script(ctx, entry_point)

    # Avoid writing non-normalized paths (workspace/../other_workspace/path)
    if ctx.outputs.loader.short_path.startswith("../"):
        script_path = ctx.outputs.loader.short_path[len("../"):]
    else:
        script_path = "/".join([
            ctx.workspace_name,
            ctx.outputs.loader.short_path,
        ])
    env_vars = "export BAZEL_TARGET=%s\n" % ctx.label
    for k in ctx.attr.configuration_env_vars:
        if k in ctx.var.keys():
            env_vars += "export %s=\"%s\"\n" % (k, ctx.var[k])

    expected_exit_code = 0
    if hasattr(ctx.attr, "expected_exit_code"):
        expected_exit_code = ctx.attr.expected_exit_code

    substitutions = {
        "TEMPLATED_node": short_path_to_manifest_path(ctx, node.short_path),
        "TEMPLATED_args": " ".join([
            expand_location_into_runfiles(ctx, a)
            for a in ctx.attr.templated_args
        ]),
        "TEMPLATED_repository_args": short_path_to_manifest_path(ctx, ctx.file._repository_args.short_path),
        "TEMPLATED_script_path": script_path,
        "TEMPLATED_env_vars": env_vars,
        "TEMPLATED_expected_exit_code": str(expected_exit_code),
    }
    ctx.actions.expand_template(
        template = ctx.file._launcher_template,
        output = ctx.outputs.script,
        substitutions = substitutions,
        is_executable = True,
    )

    runfiles = depset(sources + files + [node, ctx.outputs.loader, ctx.file._repository_args] + node_modules)

    return [DefaultInfo(
        files = depset([ctx.outputs.script]),
        executable = ctx.outputs.script,
        runfiles = ctx.runfiles(
            transitive_files = runfiles,
            # files = [node, ctx.outputs.loader] + node_modules + sources,
            # collect_data = True,
        ),
    )]

NODEJS_EXECUTABLE_ATTRS = {
    "entry_point": attr.string(
        doc = """The script which should be executed first, usually containing a main function.
        This attribute expects a string starting with the workspace name, so that it's not ambiguous
        in cases where a script with the same name appears in another directory or external workspace.
        """,
        mandatory = True,
    ),
    "bootstrap": attr.string_list(
        doc = """JavaScript modules to be loaded before the entry point.
        For example, Angular uses this to patch the Jasmine async primitives for
        zone.js before the first `describe`.
        """,
        default = [],
    ),
    "install_source_map_support": attr.bool(
        doc = """Install the source-map-support package.
        Enable this to get stack traces that point to original sources, e.g. if the program was written
        in TypeScript.""",
        default = True,
    ),
    "configuration_env_vars": attr.string_list(
        doc = """Pass these configuration environment variables to the resulting binary.
        Chooses a subset of the configuration environment variables (taken from ctx.var), which also
        includes anything specified via the --define flag.
        Note, this can lead to different outputs produced by this rule.""",
        default = [],
    ),
    "data": attr.label_list(
        doc = """Runtime dependencies which may be loaded during execution.""",
        allow_files = True,
        aspects = [module_mappings_runtime_aspect, node_modules_aspect],
    ),
    "templated_args": attr.string_list(
        doc = """Arguments which are passed to every execution of the program.
        To pass a node startup option, prepend it with `--node_options=`, e.g.
        `--node_options=--preserve-symlinks`
        """,
    ),
    "node_modules": attr.label(
        doc = """The npm packages which should be available to `require()` during
        execution.

        This attribute is DEPRECATED. As of version 0.13.0 the recommended approach
        to npm dependencies is to use fine grained npm dependencies which are setup
        with the `yarn_install` or `npm_install` rules. For example, in targets
        that used a `//:node_modules` filegroup,

        ```
        nodejs_binary(
          name = "my_binary",
          ...
          node_modules = "//:node_modules",
        )
        ```

        which specifies all files within the `//:node_modules` filegroup
        to be inputs to the `my_binary`. Using fine grained npm dependencies,
        `my_binary` is defined with only the npm dependencies that are
        needed:

        ```
        nodejs_binary(
          name = "my_binary",
          ...
          data = [
              "@npm//foo",
              "@npm//bar",
              ...
          ],
        )
        ```

        In this case, only the `foo` and `bar` npm packages and their
        transitive deps are includes as inputs to the `my_binary` target
        which reduces the time required to setup the runfiles for this
        target (see https://github.com/bazelbuild/bazel/issues/5153).

        The @npm external repository and the fine grained npm package
        targets are setup using the `yarn_install` or `npm_install` rule
        in your WORKSPACE file:

        yarn_install(
          name = "npm",
          package_json = "//:package.json",
          yarn_lock = "//:yarn.lock",
        )

        For other rules such as `jasmine_node_test`, fine grained
        npm dependencies are specified in the `deps` attribute:

        ```
        jasmine_node_test(
            name = "my_test",
            ...
            deps = [
                "@npm//jasmine",
                "@npm//foo",
                "@npm//bar",
                ...
            ],
        )
        ```
        """,
        default = Label("//:node_modules_none"),
    ),
    "node": attr.label(
        doc = """The node entry point target.""",
        default = Label("@nodejs//:node"),
        allow_single_file = True,
    ),
    "_repository_args": attr.label(
        default = Label("@nodejs//:bin/node_repo_args.sh"),
        allow_single_file = True,
    ),
    "_launcher_template": attr.label(
        default = Label("@build_bazel_rules_nodejs//internal/node:node_launcher.sh"),
        allow_single_file = True,
    ),
    "_loader_template": attr.label(
        default = Label("@build_bazel_rules_nodejs//internal/node:node_loader.js"),
        allow_single_file = True,
    ),
}

NODEJS_EXECUTABLE_OUTPUTS = {
    "loader": "%{name}_loader.js",
    "script": "%{name}.sh",
}

# The name of the declared rule appears in
# bazel query --output=label_kind
# So we make these match what the user types in their BUILD file
# and duplicate the definitions to give two distinct symbols.
nodejs_binary = rule(
    implementation = nodejs_binary_impl,
    attrs = NODEJS_EXECUTABLE_ATTRS,
    executable = True,
    outputs = NODEJS_EXECUTABLE_OUTPUTS,
)
"""
Runs some JavaScript code in NodeJS.
"""

nodejs_test = rule(
    implementation = nodejs_binary_impl,
    attrs = dict(NODEJS_EXECUTABLE_ATTRS, **{
        "expected_exit_code": attr.int(
            doc = "The expected exit code for the test. Defaults to 0.",
            default = 0,
        ),
    }),
    test = True,
    outputs = NODEJS_EXECUTABLE_OUTPUTS,
)
