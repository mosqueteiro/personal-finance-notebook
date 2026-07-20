{ pkgs, lib, config, inputs, ... }:

{
  # https://devenv.sh/packages/
  packages = [ pkgs.git ];

  # https://devenv.sh/languages/python/
  languages.python = {
    enable = true;
    version = "3.14";
    venv.enable = true;
    uv = {
      enable = true;
      sync.enable = true;
    };
  };

  # https://devenv.sh/processes/
  # `devenv up` launches the Marimo editor.
  processes.marimo.exec = "marimo edit";

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    python --version
  '';
}
