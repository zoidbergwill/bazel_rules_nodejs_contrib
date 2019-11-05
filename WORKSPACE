#  Copyright 2018 Ecosia GmbH
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

workspace(
    name = "ecosia_bazel_rules_nodejs_contrib",
    managed_directories = {
        "@npm": ["examples/babel_library/node_modules"],
        "@jest_node_test_example_deps": ["examples/jest_node_test/node_modules"],
        "@nodejs_jest_test_example_deps": ["examples/nodejs_jest_test/node_modules"],
        "@vue_component_deps": ["internal/vue_component/node_modules"],
        "@toml_to_js_deps": ["examples/toml_to_js/node_modules"],
        "@json_to_js_deps": ["internal/json_to_js/node_modules"],
        "@eslint_deps": ["experimental/eslint/node_modules"],
        "@nuxt_build": ["experimental/nuxt_build/node_modules"],
    },
)

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

git_repository(
    name = "bazel_skylib",
    remote = "https://github.com/bazelbuild/bazel-skylib",
    branch = "master",
)

git_repository(
    name = "build_bazel_rules_nodejs",
    remote = "https://github.com/bazelbuild/rules_nodejs",
    branch = "master",
)

load("@build_bazel_rules_nodejs//:defs.bzl", "node_repositories", "yarn_install")

node_repositories(
    package_json = [
        "//internal/json_to_js:package.json",
        "//internal/toml_to_js:package.json",
        "//internal/vue_component:package.json",
        "//experimental/eslint:package.json",
    ],
)

load("//:defs.bzl", "node_contrib_repositories")

node_contrib_repositories(
    symlink_node_modules = True,
)

yarn_install(
    name = "npm",
    data = [
        "@ecosia_bazel_rules_nodejs_contrib//internal/babel_library:babel.js",
        "@ecosia_bazel_rules_nodejs_contrib//internal/babel_library:package.json",
    ],
    exclude_packages = [],
    package_json = "@ecosia_bazel_rules_nodejs_contrib//examples/babel_library:package.json",
    yarn_lock = "@ecosia_bazel_rules_nodejs_contrib//examples/babel_library:yarn.lock",
)

git_repository(
    name = "pax",
    remote = "https://github.com/Globegitter/pax",
    branch = "master",
)

git_repository(
  name = "io_bazel_rules_go",
  remote = "https://github.com/bazelbuild/rules_go",
  branch = "master",
)

git_repository(
  name = "bazel_gazelle",
  remote = "https://github.com/bazelbuild/bazel-gazelle",
  branch = "master",
)

load("@io_bazel_rules_go//go:deps.bzl", "go_register_toolchains", "go_rules_dependencies")

go_rules_dependencies()

go_register_toolchains()

load("@bazel_gazelle//:deps.bzl", "gazelle_dependencies")

gazelle_dependencies()

load("//examples/jest_node_test:deps.bzl", "jest_node_test_example_dependencies")

jest_node_test_example_dependencies()

load("//examples/nodejs_jest_test:deps.bzl", "nodejs_jest_test_example_dependencies")

nodejs_jest_test_example_dependencies()
